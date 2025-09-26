# Socat Proxy

A lightweight Docker container that creates a UNIX socket proxy to TCP connections using socat and Alpine Linux.

> [!NOTE]
>_Github repo is a mirror of https://git.djeex.fr/Djeex/socat-proxy. You'll find full package, history and release note there._

## 📑 Table of Contents

- [🚀 Features](#-features)
- [🔧 How It Works](#-how-it-works)
- [📋 Use Case](#-use-case)
- [🛠️ Configuration](#️-configuration)
  - [Environment Variables](#environment-variables)
- [🚢 Quick Start](#-quick-start)
  - [Using Docker Compose (Recommended)](#using-docker-compose-recommended)
  - [Using Docker Run](#using-docker-run)
- [💡 Deployment example for Beszel](#-example-secure-docker-socket-access-for-host-mode-containers)

## 🚀 Features

- **Configurable**: Environment variable driven configuration
- **Socket Management**: Automatic UNIX socket creation and cleanup
- **Production Ready**: Includes proper error handling and logging

## 🔧 How It Works

1. **Socket Check**: Verifies if UNIX socket exists at startup
2. **Cleanup**: Removes existing socket file/folder if present
3. **Socket Creation**: Creates new UNIX socket using `nc -lU`
4. **Proxy Start**: Starts socat to proxy UNIX socket to TCP endpoint

## 📋 Use Case

Proxy Docker socket from a docker proxy to a container in host mode without directly exposing socket to host. For example:

[Beszel](https://beszel.dev/) is a monitoring tool that requires `network_mode: host` to function properly. This creates a security challenge: Beszel needs access to the Docker socket, but it cannot reach a containerized docker-socket-proxy due to the network isolation. Running docker-socket-proxy in host mode or exposing port to host would also be highly insecure.

**Socat-proxy solves this problem** by creating a secure bridge between host-mode containers and containerized socket proxies. It exposes a UNIX socket file on the host filesystem that Beszel can access, while securely forwarding all Docker API requests to the socket-proxy running on the bridge network.

![](https://git.djeex.fr/Djeex/socat-proxy/raw/branch/main/assets/img/socat-proxy.svg)

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

1. Create a `.env` file with your configuration:
```bash
TARGET_HOST= #your target host
TARGET_PORT= #your target host port
UNIX_SOCKET_NAME= #your socket file name
UNIX_SOCKET_PATH= #your socket folder path inside socat-proxy
HOST_SOCKET_PATH= #your socket folder path inside your host
DEBUG_LEVEL=1
```

2. Create a `compose.yml` file:
```yaml
services:
  socat-proxy:
    image: git.djeex.fr/djeex/socat-proxy:latest
    environment:
      - TARGET_HOST=${TARGET_HOST}
      - TARGET_PORT=${TARGET_PORT}
      - UNIX_SOCKET_NAME=${UNIX_SOCKET_NAME}
      - UNIX_SOCKET_PATH=${UNIX_SOCKET_PATH}
      - HOST_SOCKET_PATH=${HOST_SOCKET_PATH}
      - DEBUG_LEVEL=${DEBUG_LEVEL}
    volumes:
      - ${HOST_SOCKET_PATH}:${UNIX_SOCKET_PATH}
    restart: unless-stopped
```

3. Start the service:
```bash
docker compose up -d
```

### Using Docker Run

```bash
docker run -d \
  --name socat-proxy \
  -e TARGET_HOST= #your target host \
  -e TARGET_PORT= #your target host port \
  -e UNIX_SOCKET_NAME= #your socket file name \
  -e UNIX_SOCKET_PATH= #your socket folder path inside socat-proxy \
  -e HOST_SOCKET_PATH= #your socket folder path inside your host\
  -e DEBUG_LEVEL=1 \
  -v ${HOST_SOCKET_PATH}:${UNIX_SOCKET_PATH}$ \
  git.djeex.fr/djeex/socat-proxy:latest
```


## 💡 Deployment example for Beszel

```yaml
services:
  socat-proxy:
    image: git.djeex.fr/djeex/socat-proxy:latest
    container_name: socat-proxy-beszel
    environment:
      - TARGET_HOST=${TARGET_HOST}
      - TARGET_PORT=${TARGET_PORT}
      - UNIX_SOCKET_PATH=${UNIX_SOCKET_PATH}
      - HOST_SOCKET_PATH=${HOST_SOCKET_PATH}
      - UNIX_SOCKET_NAME=${UNIX_SOCKET_NAME}
    volumes:
      - ${HOST_SOCKET_PATH}:${UNIX_SOCKET_PATH}
    restart: unless-stopped
    depends_on:
      - ${TARGET_HOST}

  socket-proxy:
    image: lscr.io/linuxserver/socket-proxy:latest
    container_name: ${TARGET_HOST}
    security_opt:
      - no-new-privileges:true
    environment:
      - CONTAINERS=1
      - INFO=1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /run

  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    security_opt:
      - no-new-privileges:true
    volumes:
      - ${HOST_SOCKET_PATH}/${UNIX_SOCKET_NAME}:/var/run/docker.sock:ro
    environment:
      - #... your Beszel environment var 
    depends_on:
      - socat-proxy
```

