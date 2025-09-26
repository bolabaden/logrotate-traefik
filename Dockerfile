# Dockerfile for Traefik Log Rotation and Monitoring
FROM alpine:3.19

# Metadata
LABEL maintainer="Boden Crouch <contact@bolabaden.org>" \
      description="Alpine-based container for Traefik log rotation and real-time monitoring" \
      version="1.0.0"

# Install required packages
RUN apk add --no-cache \
    logrotate \
    findutils \
    coreutils \
    jq \
    bind-tools \
    bash \
    && rm -rf /var/cache/apk/*

# Create necessary directories and set permissions
RUN mkdir -p /var/log/traefik \
    /var/lib/logrotate \
    /etc/logrotate.d \
    && touch /var/lib/logrotate.status

# Copy scripts
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/traefik-logrotate.sh /usr/local/bin/traefik-logrotate.sh

# Make scripts executable
RUN chmod +x /entrypoint.sh /usr/local/bin/traefik-logrotate.sh

ARG PUID=1001
ENV PUID=${PUID}

ARG PGID=1001
ENV PGID=${PGID}

# Set up non-root user for better security
RUN addgroup -g ${PGID} logrotate && \
    adduser -D -u ${PUID} -G logrotate logrotate

# Set working directory
WORKDIR /app

# Environment variables with defaults
ARG TRAEFIK_LOG_DIR="/var/log/traefik" \
    TRAEFIK_LOG_FILENAME="traefik.log" \
    LOG_LEVEL="info" \
    LOGROTATE_LOOP_SLEEP="300" \
    LOGROTATE_MAXSIZE="10M" \
    LOGROTATE_MAXCOUNT="20" \
    LOGROTATE_ROTATE_FREQ="hourly" \
    LOGROTATE_MAXDIR_MB="50" \
    LOGROTATE_KEEP_GZ="10" \
    LOGROTATE_STATE_FILE="/var/lib/logrotate.status" \
    STATUS_CODES="100-999" \
    TZ="UTC"
ENV TRAEFIK_LOG_DIR="$TRAEFIK_LOG_DIR" \
    TRAEFIK_LOG_FILENAME="$TRAEFIK_LOG_FILENAME" \
    LOG_LEVEL="$LOG_LEVEL" \
    LOGROTATE_LOOP_SLEEP="$LOGROTATE_LOOP_SLEEP" \
    LOGROTATE_MAXSIZE="$LOGROTATE_MAXSIZE" \
    LOGROTATE_MAXCOUNT="$LOGROTATE_MAXCOUNT" \
    LOGROTATE_ROTATE_FREQ="$LOGROTATE_ROTATE_FREQ" \
    LOGROTATE_MAXDIR_MB="$LOGROTATE_MAXDIR_MB" \
    LOGROTATE_KEEP_GZ="$LOGROTATE_KEEP_GZ" \
    LOGROTATE_STATE_FILE="$LOGROTATE_STATE_FILE" \
    STATUS_CODES="$STATUS_CODES" \
    TZ="$TZ"

# Expose no ports (this is a utility container)
# EXPOSE - not needed

# Health check to ensure the container is functioning
#HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
#    CMD [ -f "$TRAEFIK_LOG_DIR/$TRAEFIK_LOG_FILENAME" ] || exit 1

# Use entrypoint for proper signal handling and initialization
ENTRYPOINT ["/entrypoint.sh"]
CMD ["traefik-logrotate.sh"]
