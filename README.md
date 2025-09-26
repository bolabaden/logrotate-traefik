# Traefik Log Rotation and Monitoring

[![Docker Build](https://github.com/bolabaden/logrotate-traefik/actions/workflows/docker-build.yml/badge.svg)](https://github.com/bolabaden/logrotate-traefik/actions)
[![Docker Push](https://github.com/bolabaden/logrotate-traefik/actions/workflows/docker-push.yml/badge.svg)](https://github.com/bolabaden/logrotate-traefik/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker Image Size](https://img.shields.io/docker/image-size/bolabaden/logrotate-traefik/latest)](https://hub.docker.com/r/bolabaden/logrotate-traefik)

A lightweight, Alpine-based Docker container that provides automated log rotation and real-time monitoring for Traefik access logs. Features configurable retention policies, colored log output, DNS resolution, and robust error handling.

## 🚀 Features

- **Automated Log Rotation**: Configurable size and time-based rotation
- **Real-time Monitoring**: Live log tailing with colored output
- **DNS Resolution**: Automatically resolves client IPs to hostnames
- **Status Code Filtering**: Configurable HTTP status code filtering
- **Resource Efficient**: <64MB memory footprint
- **Signal Handling**: Graceful shutdown on container stop
- **Health Checks**: Built-in container health monitoring
- **Comprehensive Logging**: Structured logging with multiple levels
- **Zero Dependencies**: Self-contained with all required tools

## 📋 Quick Start

### Using Docker Compose (Recommended)

1. **Download the example compose file:**
   ```bash
   curl -o docker-compose.yml https://raw.githubusercontent.com/bolabaden/logrotate-traefik/master/examples/docker-compose.simple.yml
   ```

2. **Start the service:**
   ```bash
   docker-compose up -d logrotate-traefik
   ```

3. **View real-time logs:**
   ```bash
   docker-compose logs -f logrotate-traefik
   ```

### Using Docker Run

```bash
docker run -d \
  --name logrotate-traefik \
  --restart unless-stopped \
  -v /path/to/traefik/logs:/var/log/traefik:rw \
  -e TZ=America/Chicago \
  -e LOG_LEVEL=info \
ghcr.io/bolabaden/logrotate-traefik:latest
```

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TRAEFIK_LOG_DIR` | `/var/log/traefik` | Directory containing Traefik logs |
| `TRAEFIK_LOG_FILENAME` | `traefik.log` | Name of the main log file |
| `LOG_LEVEL` | `info` | Service log level (`debug`, `info`, `warning`, `error`) |
| `LOGROTATE_LOOP_SLEEP` | `300` | Check interval in seconds (min: 30) |
| `LOGROTATE_MAXSIZE` | `10M` | Max file size before rotation |
| `LOGROTATE_MAXCOUNT` | `20` | Number of rotated files to keep |
| `LOGROTATE_ROTATE_FREQ` | `hourly` | Rotation frequency (`hourly`, `daily`, `weekly`, `monthly`) |
| `LOGROTATE_MAXDIR_MB` | `50` | Max total directory size in MB |
| `LOGROTATE_KEEP_GZ` | `10` | Compressed files to keep during cleanup |
| `STATUS_CODES` | `100-999` | Status codes to display (comma-separated) |
| `TZ` | `UTC` | Container timezone |

### Status Code Filtering Examples

- `100-999` - All status codes (default)
- `200,201,204` - Specific success codes only
- `400-499` - Client errors only
- `500-599` - Server errors only
- `200,300-399,404` - Mixed ranges and specific codes

## 📁 Directory Structure

```
logrotate-traefik/
├── Dockerfile              # Multi-stage Docker build
├── Makefile                # Development and build tasks
├── README.md               # This file
├── scripts/
│   ├── entrypoint.sh       # Container initialization
│   └── traefik-logrotate.sh # Main log rotation script
├── config/
│   ├── logrotate.conf      # Example logrotate config
│   └── environment.env.example # Environment variables reference
└── examples/
    ├── docker-compose.yml      # Full example with Traefik
    └── docker-compose.simple.yml # Simple service only
```

## 🐳 Docker Integration

### With Existing Traefik Setup

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:v3.0
    # ... your existing Traefik configuration
    volumes:
      - traefik-logs:/var/log/traefik
    command:
      - --log.filePath=/var/log/traefik/traefik.log
      - --log.format=json

  logrotate-traefik:
    image: ghcr.io/bolabaden/logrotate-traefik:latest
    container_name: logrotate-traefik
    restart: unless-stopped
    volumes:
      - traefik-logs:/var/log/traefik:rw
    environment:
      TZ: America/Chicago
      LOG_LEVEL: info
    depends_on:
      - traefik

volumes:
  traefik-logs:
    driver: local
```

### Resource Limits

```yaml
deploy:
  resources:
    limits:
      cpus: '0.1'
      memory: 64M
    reservations:
      memory: 8M
```

## 🔍 Monitoring Output

The service provides real-time colored log monitoring:

```
==================================================================
TIMESTAMP           | STA | CLIENT             | HOST                      | METHOD+PATH           | DURATION | SERVICE
==================================================================
2024-01-15T10:30:45Z | 200 | example.com:54321  | api.mysite.com           | GET /api/users        | 45 ms    | api-service
2024-01-15T10:30:46Z | 404 | 192.168.1.100:6789| mysite.com               | GET /missing          | 12 ms    | web-service
2024-01-15T10:30:47Z | 500 | client.example.org | api.mysite.com           | POST /api/data        | 1205 ms  | api-service
```

### Color Coding
- **Green**: 2xx success responses
- **Blue**: 3xx redirects
- **Yellow**: 4xx client errors
- **Red**: 5xx server errors
- **Dynamic**: Other codes get unique colors

## 🛠️ Development

### Prerequisites

- Docker
- Docker Compose
- Make (optional, for convenience)

### Local Development

1. **Clone the repository:**
   ```bash
   git clone https://github.com/bolabaden/logrotate-traefik.git
   cd logrotate-traefik
   ```

2. **Set up development environment:**
   ```bash
   make dev-setup
   ```

3. **Build and test locally:**
   ```bash
   make build
   make test
   ```

4. **Run with test logs:**
   ```bash
   make run
   ```

### Available Make Targets

| Target | Description |
|--------|-------------|
| `build` | Build the Docker image |
| `test` | Run basic functionality tests |
| `run` | Run container locally with test logs |
| `shell` | Start interactive shell in container |
| `lint` | Lint shell scripts with shellcheck |
| `clean` | Clean up images and test files |
| `push` | Push to registry |
| `release` | Complete release pipeline |

## 🔒 Security

### Security Features

- **Non-root execution**: Runs as dedicated `logrotate` user (UID 1001)
- **Minimal attack surface**: Alpine-based with minimal packages
- **Read-only filesystem**: Only log directory requires write access
- **Signal handling**: Proper cleanup on container termination
- **Health checks**: Built-in container health monitoring

### Security Scanning

```bash
# Scan for vulnerabilities
make security-scan

# Check image size and layers
make size
```

## 📊 Performance

### Resource Usage
- **Memory**: ~8-64MB (depending on log volume)
- **CPU**: <0.1 core (burst during rotation)
- **Disk I/O**: Minimal (rotation and compression only)
- **Network**: Minimal (DNS lookups only)

### Optimization Tips
- Adjust `LOGROTATE_LOOP_SLEEP` based on log volume
- Use `STATUS_CODES` filtering to reduce output
- Set `LOGROTATE_MAXSIZE` appropriate to your log volume
- Monitor `LOGROTATE_MAXDIR_MB` to prevent disk usage spikes

## 🚨 Troubleshooting

### Common Issues

1. **Container exits immediately**
   ```bash
   # Check if log directory is mounted and accessible
   docker logs logrotate-traefik
   ```

2. **No logs appearing**
   ```bash
   # Verify Traefik is writing JSON logs to the mounted volume
   ls -la /path/to/traefik/logs/
   ```

3. **Permission denied errors**
   ```bash
   # Ensure log directory has correct permissions
   chmod 755 /path/to/traefik/logs/
   chmod 644 /path/to/traefik/logs/*.log
   ```

4. **High memory usage**
   ```bash
   # Reduce log retention or increase rotation frequency
   docker exec logrotate-traefik env | grep LOGROTATE
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
docker run -e LOG_LEVEL=debug your-registry/logrotate-traefik:latest
```

### Log Analysis

```bash
# Check rotation status
docker exec logrotate-traefik cat /var/lib/logrotate.status

# Check directory size
docker exec logrotate-traefik du -sh /var/log/traefik

# List rotated files
docker exec logrotate-traefik ls -lah /var/log/traefik/
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`make test lint`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Guidelines

- Follow shell script best practices
- Add tests for new features
- Update documentation
- Maintain backward compatibility
- Keep Docker image size minimal

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/bolabaden/logrotate-traefik/issues)
- **Discussions**: [GitHub Discussions](https://github.com/bolabaden/logrotate-traefik/discussions)
- **Documentation**: [Wiki](https://github.com/bolabaden/logrotate-traefik/wiki)

## 🙏 Acknowledgments

- [Traefik](https://traefik.io/) - The amazing reverse proxy
- [Alpine Linux](https://alpinelinux.org/) - Lightweight container base
- [logrotate](https://github.com/logrotate/logrotate) - Log rotation utility

---

**Made with ❤️ for the Traefik community**
