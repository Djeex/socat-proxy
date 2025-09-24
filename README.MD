# Socat Proxy

A lightweight Docker container that creates a UNIX socket proxy to TCP connections using socat and Alpine Linux.

## 🚀 Features

- **Lightweight**: Based on Alpine Linux (~10-15MB image)
- **Configurable**: Environment variable driven configuration
- **Socket Management**: Automatic UNIX socket creation and cleanup
- **Production Ready**: Includes proper error handling and logging
- **Multi-variant**: Standard and minimal Docker images available

## 📋 Use Cases example

- Proxy Docker socket from a docker proxy to a container in host mode

## 🛠️ Configuration

### Environment Variables

| Variable | Default | Description | Example |
|----------|---------|-------------|---------|
| `TARGET_HOST` | - | Target hostname/IP to proxy to | `socket-proxy-beszel` |
| `TARGET_PORT` | - | Target port to proxy to | `2375` |
| `UNIX_SOCKET_PATH` | - | Path to UNIX socket inside container | `/socket/docker.sock` |
| `SOCKET_PATH` | - | Host path for socket mounting | `/your/container/sock/` |

## 🚢 Quick Start

### Using Docker Compose (Recommended)

1. Clone the repository:
```bash
git clone <repository-url>
cd socat-proxy
```

2. Configure environment variables in `.env` file:
```bash
TARGET_HOST= #  Target hostname/IP to proxy to
TARGET_PORT= # Target port to proxy to
UNIX_SOCKET_PATH= # Path to UNIX socket inside container
HOST_SOCKET_PATH= # Host path for socket mounting
```

3. Start the service:
```bash
docker-compose up -d
```

### Using Docker Run

```bash
docker build -t socat-proxy .

docker run -d \
  --name socat-proxy \
  -e TARGET_HOST=your-target-host \
  -e TARGET_PORT=your-target-port \
  -e UNIX_SOCKET_PATH=your-unix-socket-path \
  -e HOST_SOCKET_PATH=your-socket-host-path \
  -v /your-origin-socket-path:/socket \
  socat-proxy
```

## 🔧 How It Works

1. **Socket Check**: Verifies if UNIX socket exists at startup
2. **Cleanup**: Removes existing socket file/folder if present
3. **Socket Creation**: Creates new UNIX socket using `nc -lU`
4. **Proxy Start**: Starts socat to proxy UNIX socket to TCP endpoint
