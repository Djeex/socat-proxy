# Socat Proxy

A lightweight Docker container that creates a UNIX socket proxy to TCP connections using socat and Alpine Linux.

## 🚀 Features

- **Configurable**: Environment variable driven configuration
- **Socket Management**: Automatic UNIX socket creation and cleanup
- **Production Ready**: Includes proper error handling and logging

## 📋 Use Cases example

- Proxy Docker socket from a docker proxy to a container in host mode

## 🛠️ Configuration

### Environment Variables

| Variable | Default | Description | Example |
|----------|---------|-------------|---------|
| `TARGET_HOST` | - | Target hostname/IP to proxy to | `socket-proxy-beszel` |
| `TARGET_PORT` | - | Target port to proxy to | `2375` |
| `UNIX_SOCKET_NAME` | - | Name of the socket file | `docker.sock` |
| `UNIX_SOCKET_PATH` | - | Path to UNIX socket inside container | `/socket` |
| `HOST_SOCKET_PATH` | - | Host path for socket mounting | `/docker/beszel-agent/sock` |
| `DEBUG_LEVEL` | - | Level of logs verbose | `0`,`1`,`2`,`3`  |

## 🚢 Quick Start

### Using Docker Compose (Recommended)

1. Clone the repository:
```bash
git clone https://git.djeex.fr/Djeex/socat-proxy
cd socat-proxy
```

2. Configure environment variables in `.env` file:
```bash
TARGET_HOST= # Target hostname/IP to proxy to
TARGET_PORT= # Target port to proxy to
UNIX_SOCKET_NAME= # Name of the socket file
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
  -e UNIX_SOCKET_NAME=your-socket-name \
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
