#!/bin/bash
#
# Traefik Log Rotation and Monitoring Script
# Handles log rotation with configurable parameters and provides real-time log monitoring
#

set -euo pipefail

# Configuration variables with environment defaults
readonly TRAEFIK_LOG_DIR="${TRAEFIK_LOG_DIR:-/var/log/traefik}"
readonly TRAEFIK_LOG_FILENAME="${TRAEFIK_LOG_FILENAME:-traefik.log}"
readonly LOG_LEVEL="${LOG_LEVEL:-info}"
readonly LOGROTATE_LOOP_SLEEP="${LOGROTATE_LOOP_SLEEP:-300}"
readonly LOGROTATE_MAXSIZE="${LOGROTATE_MAXSIZE:-10M}"
readonly LOGROTATE_MAXCOUNT="${LOGROTATE_MAXCOUNT:-20}"
readonly LOGROTATE_ROTATE_FREQ="${LOGROTATE_ROTATE_FREQ:-hourly}"
readonly LOGROTATE_MAXDIR_MB="${LOGROTATE_MAXDIR_MB:-50}"
readonly LOGROTATE_KEEP_GZ="${LOGROTATE_KEEP_GZ:-10}"
readonly LOGROTATE_STATE_FILE="${LOGROTATE_STATE_FILE:-/var/lib/logrotate.status}"
readonly STATUS_CODES="${STATUS_CODES:-100-999}"

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"

# Logging functions with consistent formatting
log_debug() {
    case "$LOG_LEVEL" in
        debug|verbose) 
            echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [DEBUG] [$SCRIPT_NAME] $*"
            ;;
    esac
}

log_info() {
    case "$LOG_LEVEL" in
        debug|verbose|info) 
            echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO] [$SCRIPT_NAME] $*"
            ;;
    esac
}

log_warn() {
    case "$LOG_LEVEL" in
        debug|verbose|info|warning) 
            echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [WARN] [$SCRIPT_NAME] $*"
            ;;
    esac
}

log_error() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] [$SCRIPT_NAME] $*" >&2
}

# Signal handling
cleanup() {
    local exit_code=$?
    log_info "Received termination signal, shutting down gracefully..."
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit $exit_code
}

trap cleanup SIGTERM SIGINT SIGQUIT

# Validation functions
validate_dependencies() {
    local missing_deps=()
    
    # Check for required binaries
    for dep in logrotate jq tail awk sed grep; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        return 1
    fi
}

validate_configuration() {
    log_info "Validating configuration..."
    
    # Check directories
    if [[ ! -d "$TRAEFIK_LOG_DIR" ]]; then
        log_error "TRAEFIK_LOG_DIR does not exist: $TRAEFIK_LOG_DIR"
        return 1
    fi
    
    if [[ ! -w "$TRAEFIK_LOG_DIR" ]]; then
        log_error "Cannot write to TRAEFIK_LOG_DIR: $TRAEFIK_LOG_DIR"
        return 1
    fi
    
    # Validate numeric parameters
    if ! [[ "$LOGROTATE_LOOP_SLEEP" =~ ^[0-9]+$ ]] || [[ "$LOGROTATE_LOOP_SLEEP" -lt 30 ]]; then
        log_error "LOGROTATE_LOOP_SLEEP must be >= 30 seconds (got: $LOGROTATE_LOOP_SLEEP)"
        return 1
    fi
    
    log_info "Configuration validation successful"
}

# Setup logrotate configuration
setup_logrotate() {
    log_info "Setting up logrotate configuration..."
    
    # Create the logrotate configuration
    cat > /etc/logrotate.d/traefik << EOF
$TRAEFIK_LOG_DIR/*.log {
    $LOGROTATE_ROTATE_FREQ
    size $LOGROTATE_MAXSIZE
    rotate $LOGROTATE_MAXCOUNT
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
    postrotate
        echo "[POSTROTATE] \$(date -u '+%Y-%m-%dT%H:%M:%SZ') Checking for old gzipped logs..."
        TOTAL_SIZE=\$(du -sm "$TRAEFIK_LOG_DIR" 2>/dev/null | cut -f1 || echo 0)
        echo "[POSTROTATE] Directory size: \$TOTAL_SIZE MB"
        if [ "\$TOTAL_SIZE" -gt "$LOGROTATE_MAXDIR_MB" ]; then
            echo "[POSTROTATE] Cleaning up old gz logs beyond $LOGROTATE_KEEP_GZ most recent"
            find "$TRAEFIK_LOG_DIR" -name "*.gz" -type f -printf '%T@ %p\n' 2>/dev/null | \
                sort -rn | tail -n +$((LOGROTATE_KEEP_GZ + 1)) | cut -d' ' -f2- | \
                xargs -r rm -f
        fi
    endscript
}
EOF
    
    log_info "Logrotate configuration created"
}

# Test logrotate configuration
test_logrotate() {
    log_info "Testing logrotate configuration..."
    
    if ! logrotate -d /etc/logrotate.d/traefik >/dev/null 2>&1; then
        log_error "Logrotate configuration test failed"
        return 1
    fi
    
    # Force initial rotation to ensure everything works
    log_info "Performing initial logrotate run..."
    if ! logrotate -s "$LOGROTATE_STATE_FILE" -v /etc/logrotate.d/traefik 2>&1 | sed 's/^/[INIT] /'; then
        log_error "Initial logrotate run failed"
        return 1
    fi
    
    log_info "Logrotate test successful"
}

# Start logrotate daemon in background
start_logrotate_daemon() {
    log_info "Starting logrotate daemon (check interval: ${LOGROTATE_LOOP_SLEEP}s)..."
    
    (
        while true; do
            log_debug "Logrotate daemon: sleeping ${LOGROTATE_LOOP_SLEEP}s..."
            sleep "$LOGROTATE_LOOP_SLEEP"
            
            if [[ "$LOG_LEVEL" == "debug" ]] || [[ "$LOG_LEVEL" == "verbose" ]]; then
                log_debug "Checking logrotate state..."
                if [[ -f "$LOGROTATE_STATE_FILE" ]]; then
                    sed 's/^/[STATE] /' "$LOGROTATE_STATE_FILE"
                fi
            fi
            
            local timestamp
            timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
            
            if [[ "$LOG_LEVEL" == "debug" ]] || [[ "$LOG_LEVEL" == "verbose" ]]; then
                log_debug "[$timestamp] Running verbose logrotate..."
                if ! logrotate -s "$LOGROTATE_STATE_FILE" -v /etc/logrotate.d/traefik 2>&1 | sed 's/^/[ROTATE] /'; then
                    log_error "Logrotate failed at $timestamp"
                fi
                
                log_debug "Checking log directory size..."
                du -sh "$TRAEFIK_LOG_DIR" 2>&1 | sed 's/^/[SIZE] /'
                ls -lah "$TRAEFIK_LOG_DIR" 2>&1 | sed 's/^/[FILES] /'
            else
                log_info "[$timestamp] Running logrotate..."
                if ! logrotate -s "$LOGROTATE_STATE_FILE" /etc/logrotate.d/traefik 2>&1 | sed 's/^/[ROTATE] /'; then
                    log_error "Logrotate failed at $timestamp"
                fi
            fi
        done
    ) &
    
    local daemon_pid=$!
    log_info "Logrotate daemon started with PID: $daemon_pid"
    echo $daemon_pid > /tmp/logrotate-daemon.pid
}

# Parse status codes for filtering
parse_status_codes() {
    local codes="$1"
    local regex=""
    local IFS=,
    
    for part in $codes; do
        if [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
            # Range (e.g., 400-500)
            local start end
            start=$(echo "$part" | cut -d- -f1)
            end=$(echo "$part" | cut -d- -f2)
            
            # Generate sequence and create regex
            local seq_regex
            seq_regex=$(seq "$start" "$end" | tr '\n' '|' | sed 's/|$//')
            regex="${regex:+$regex|}($seq_regex)"
        else
            # Single code
            regex="${regex:+$regex|}($part)"
        fi
    done
    
    # Return the final regex
    echo "^($regex)$"
}

# Wait for log file and start monitoring
wait_and_monitor_logs() {
    local log_file="$TRAEFIK_LOG_DIR/$TRAEFIK_LOG_FILENAME"
    
    log_info "Waiting for log file to be created: $log_file"
    while [[ ! -f "$log_file" ]]; do
        sleep 5
        log_debug "Still waiting for $log_file..."
    done
    
    log_info "Log file found, starting real-time monitoring with status code filtering..."
    log_info "Monitoring status codes: $STATUS_CODES"
    
    local status_code_regex
    status_code_regex=$(parse_status_codes "$STATUS_CODES")
    log_debug "Status code regex: $status_code_regex"
    
    # Print header
    echo "=================================================================="
    printf "%-19s | %-3s | %-18s | %-25s | %-21s | %-8s | %s\n" \
           "TIMESTAMP" "STA" "CLIENT" "HOST" "METHOD+PATH" "DURATION" "SERVICE"
    echo "=================================================================="
    
    # Monitor logs with tail -F to handle log rotation
    stdbuf -oL -eL tail -n 200 -F "$log_file" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        case "$line" in
            '{'*)
                # Parse JSON log line
                local parsed_line
                parsed_line=$(
                    echo "$line" | jq -r '
                        def ms: ( . // 0 | tonumber) / 1000000 | floor;
                        [
                            (.time // "?"),
                            ((.DownstreamStatus // 0) | tostring),
                            (.ClientAddr // "?"),
                            (.RequestHost // "?"),
                            ((.RequestMethod // "?") + " " + (.RequestPath // "?")),
                            ((.Duration | ms | tostring) + " ms"),
                            (.ServiceName // "?")
                        ] | @tsv
                    ' 2>/dev/null
                ) || continue
                
                # Resolve client IP to domain name if possible
                local client_addr client_ip resolved_addr port_part
                client_addr=$(echo "$parsed_line" | awk -F"\t" '{print $3}')
                client_ip=$(echo "$client_addr" | sed 's/:[0-9]*$//')
                resolved_addr=""
                
                # Only resolve if it's not a private IP
                if [[ ! "$client_ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.) ]]; then
                    resolved_addr=$(nslookup "$client_ip" 2>/dev/null | awk '/name =/ {print $4; exit}' | sed 's/\.$//')
                fi
                
                if [[ -z "$resolved_addr" ]] || [[ "$resolved_addr" == "$client_ip" ]]; then
                    resolved_addr="$client_addr"
                else
                    port_part=$(echo "$client_addr" | grep -o ':[0-9]*$' || echo "")
                    resolved_addr="$resolved_addr$port_part"
                fi
                
                # Update parsed line with resolved address
                parsed_line=$(echo "$parsed_line" | awk -F"\t" -v new_addr="$resolved_addr" 'BEGIN{OFS="\t"} {$3=new_addr; print}')
                
                # Check status code filter
                local status_code
                status_code=$(echo "$parsed_line" | awk -F"\t" '{print $2}')
                
                if echo "$status_code" | grep -Eq "$status_code_regex"; then
                    # Apply color coding based on status code
                    local color
                    case "$status_code" in
                        200) color="\033[1;32m" ;;   # Bright Green
                        201) color="\033[0;32m" ;;   # Green
                        204) color="\033[0;36m" ;;   # Cyan
                        301|302) color="\033[1;34m" ;;   # Bright Blue
                        304) color="\033[1;36m" ;;   # Bright Cyan
                        400) color="\033[1;33m" ;;   # Bright Yellow
                        401|403) color="\033[0;33m" ;;   # Yellow
                        404) color="\033[0;35m" ;;   # Magenta
                        408|429) color="\033[1;31m" ;;   # Bright Red
                        5*) color="\033[1;91m" ;;    # Bright Red
                        *)
                            # Dynamic color assignment for other codes
                            local palette code_num palette_len idx color_code
                            palette="31 32 33 34 35 36 91 92 93 94 95 96"
                            code_num=$(echo "$status_code" | grep -Eo '[0-9]+' || echo 0)
                            palette_len=12
                            idx=$((code_num % palette_len))
                            color_code=$(echo $palette | awk -v n=$((idx+1)) '{split($0,a," "); print a[n]}')
                            color="\033[1;${color_code}m"
                            ;;
                    esac
                    
                    # Print formatted line with colors
                    echo "$parsed_line" | awk -F"\t" -v color="$color" -v reset="\033[0m" '
                        {
                            printf "%s%-19s%s | %s%-3s%s | %-18s | %-25s | %-21s | %-8s | %s\n", \
                                color, $1, reset, color, $2, reset, $3, $4, $5, $6, $7;
                        }
                    '
                fi
                ;;
            *)
                # Non-JSON lines (startup messages, etc.)
                log_debug "Non-JSON log line: $line"
                ;;
        esac
    done
}

# Print startup information
print_startup_info() {
    cat << EOF

=============================================================
    Traefik Log Rotation and Monitoring Service
=============================================================
Version: $SCRIPT_VERSION
Log Directory: $TRAEFIK_LOG_DIR
Log File: $TRAEFIK_LOG_FILENAME
Status Filter: $STATUS_CODES
Rotation Frequency: $LOGROTATE_ROTATE_FREQ
Max Size per Rotation: $LOGROTATE_MAXSIZE
Max Rotated Files: $LOGROTATE_MAXCOUNT
Max Directory Size: ${LOGROTATE_MAXDIR_MB}MB
Daemon Check Interval: ${LOGROTATE_LOOP_SLEEP}s
=============================================================

EOF
}

# Main execution function
main() {
    print_startup_info
    
    # Validate environment
    validate_dependencies
    validate_configuration
    
    # Setup logrotate
    setup_logrotate
    test_logrotate
    
    # Start background processes
    start_logrotate_daemon
    
    # Start monitoring (this runs in foreground)
    wait_and_monitor_logs
}

# Execute main function
main "$@"
