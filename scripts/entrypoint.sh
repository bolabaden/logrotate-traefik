#!/bin/bash
#
# Entrypoint script for Traefik Log Rotation Container
# Handles initialization, signal management, and proper shutdown
#

set -euo pipefail

# Global variables
readonly SCRIPT_NAME="$(basename "$0")"
readonly PID_FILE="/tmp/traefik-logrotate.pid"

# Logging functions
log_info() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO] [$SCRIPT_NAME] $*"
}

log_warn() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [WARN] [$SCRIPT_NAME] $*"
}

log_error() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] [$SCRIPT_NAME] $*" >&2
}

log_debug() {
    if [[ "${LOG_LEVEL:-info}" == "debug" ]]; then
        echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [DEBUG] [$SCRIPT_NAME] $*"
    fi
}

# Signal handlers
cleanup() {
    local exit_code=$?
    log_info "Received termination signal, cleaning up..."
    
    # Kill background processes
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping process with PID: $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                log_warn "Process $pid still running, sending KILL signal"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
    
    log_info "Cleanup completed"
    exit $exit_code
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# Validation functions
validate_environment() {
    log_info "Validating environment variables..."
    
    # Check required directories
    if [[ ! -d "$TRAEFIK_LOG_DIR" ]]; then
        log_error "TRAEFIK_LOG_DIR ($TRAEFIK_LOG_DIR) does not exist or is not accessible"
        return 1
    fi
    
    # Check if we can write to log directory
    if [[ ! -w "$TRAEFIK_LOG_DIR" ]]; then
        log_error "Cannot write to TRAEFIK_LOG_DIR ($TRAEFIK_LOG_DIR)"
        return 1
    fi
    
    # Validate numeric values
    if ! [[ "$LOGROTATE_LOOP_SLEEP" =~ ^[0-9]+$ ]] || [[ "$LOGROTATE_LOOP_SLEEP" -lt 1 ]]; then
        log_error "LOGROTATE_LOOP_SLEEP must be a positive integer (got: $LOGROTATE_LOOP_SLEEP)"
        return 1
    fi
    
    if ! [[ "$LOGROTATE_MAXCOUNT" =~ ^[0-9]+$ ]] || [[ "$LOGROTATE_MAXCOUNT" -lt 1 ]]; then
        log_error "LOGROTATE_MAXCOUNT must be a positive integer (got: $LOGROTATE_MAXCOUNT)"
        return 1
    fi
    
    log_info "Environment validation successful"
}

print_configuration() {
    log_info "=== Container Configuration ==="
    log_info "TRAEFIK_LOG_DIR: $TRAEFIK_LOG_DIR"
    log_info "TRAEFIK_LOG_FILENAME: $TRAEFIK_LOG_FILENAME"
    log_info "LOG_LEVEL: $LOG_LEVEL"
    log_info "LOGROTATE_LOOP_SLEEP: ${LOGROTATE_LOOP_SLEEP}s"
    log_info "LOGROTATE_MAXSIZE: $LOGROTATE_MAXSIZE"
    log_info "LOGROTATE_MAXCOUNT: $LOGROTATE_MAXCOUNT"
    log_info "LOGROTATE_ROTATE_FREQ: $LOGROTATE_ROTATE_FREQ"
    log_info "LOGROTATE_MAXDIR_MB: ${LOGROTATE_MAXDIR_MB}MB"
    log_info "LOGROTATE_KEEP_GZ: $LOGROTATE_KEEP_GZ"
    log_info "STATUS_CODES: $STATUS_CODES"
    log_info "TZ: ${TZ:-UTC}"
    log_info "==============================="
}

initialize_directories() {
    log_info "Initializing directories and permissions..."
    
    # Ensure required directories exist
    mkdir -p "$TRAEFIK_LOG_DIR" /var/lib /etc/logrotate.d
    
    # Ensure state file exists
    touch "$LOGROTATE_STATE_FILE"
    
    # Set proper permissions
    chmod 755 "$TRAEFIK_LOG_DIR"
    chmod 644 "$LOGROTATE_STATE_FILE"
    
    log_info "Directory initialization completed"
}

# Main execution
main() {
    log_info "Starting Traefik Log Rotation Container"
    log_info "Container version: 1.0.0"
    
    # Print configuration
    print_configuration
    
    # Validate environment
    validate_environment
    
    # Initialize directories
    initialize_directories
    
    # Check if we have arguments (command to run)
    if [[ $# -eq 0 ]]; then
        log_error "No command specified"
        exit 1
    fi
    
    local cmd="$1"
    shift
    
    # Handle different commands
    case "$cmd" in
        "traefik-logrotate.sh")
            log_info "Starting Traefik log rotation and monitoring service"
            exec /usr/local/bin/traefik-logrotate.sh "$@"
            ;;
        "bash"|"sh")
            log_info "Starting interactive shell"
            exec "$cmd" "$@"
            ;;
        *)
            log_info "Executing custom command: $cmd $*"
            exec "$cmd" "$@"
            ;;
    esac
}

# Run main function
main "$@"
