#!/bin/sh
set -e

CYAN="\033[1;36m"
NC="\033[0m"

TARGET_HOST=${TARGET_HOST}
TARGET_PORT=${TARGET_PORT}
UNIX_SOCKET_NAME=${UNIX_SOCKET_NAME}
UNIX_SOCKET_PATH=${UNIX_SOCKET_PATH}
HOST_SOCKET_PATH=${HOST_SOCKET_PATH}

# Remove trailing slashes to avoid double slashes
UNIX_SOCKET_PATH=${UNIX_SOCKET_PATH%/}
HOST_SOCKET_PATH=${HOST_SOCKET_PATH%/}

FULL_HOST_SOCKET_PATH="$HOST_SOCKET_PATH/$UNIX_SOCKET_NAME"
FULL_UNIX_SOCKET_PATH="$UNIX_SOCKET_PATH/$UNIX_SOCKET_NAME"

VERSION=$(cat VERSION)

echo -e "${CYAN}╭────────────────────────────────────────────────╮${NC}"
echo -e "${CYAN}│${NC}         Socat-proxy - Version ${VERSION}${NC}            ${CYAN}│${NC}"
echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC} Source: https://git.djeex.fr/Djeex/socat-proxy ${CYAN}│${NC}"
echo -e "${CYAN}│${NC} Mirror: https://github.com/Djeex/socat-proxy   ${CYAN}│${NC}"
echo -e "${CYAN}╰────────────────────────────────────────────────╯${NC}"


# Validate required environment variables
if [ -z "$TARGET_HOST" ]; then
    echo "[✗] TARGET_HOST environment variable is required"
    exit 1
fi

if [ -z "$TARGET_PORT" ]; then
    echo "[✗] TARGET_PORT environment variable is required"
    exit 1
fi

if [ -z "$UNIX_SOCKET_NAME" ]; then
    echo "[✗] UNIX_SOCKET_NAME environment variable is required"
    exit 1
fi

if [ -z "$UNIX_SOCKET_PATH" ]; then
    echo "[✗] UNIX_SOCKET_PATH environment variable is required"
    exit 1
fi

if [ -z "$HOST_SOCKET_PATH" ]; then
    echo "[✗] HOST_SOCKET_PATH environment variable is required"
    exit 1
fi

echo "[~] Starting socat proxy..."
echo "[i] TCP target: $TARGET_HOST:$TARGET_PORT"
echo "[i] HOST path: $HOST_SOCKET_PATH"
echo "[i] Full host socket path: $FULL_HOST_SOCKET_PATH"
echo "[i] Full socket path: $FULL_UNIX_SOCKET_PATH"

# Check if socket file/folder exists and handle it
if [ -e "$FULL_UNIX_SOCKET_PATH" ]; then
    echo "[~] Socket file/folder $FULL_UNIX_SOCKET_PATH exists, removing it..."
    if rm -rf "$FULL_UNIX_SOCKET_PATH"; then
        echo "[✓] Removed existing socket $FULL_UNIX_SOCKET_PATH"
    else
        echo "[✗] Failed to remove existing socket $FULL_UNIX_SOCKET_PATH"
        exit 1
    fi
fi

echo [~] Creating socket directory structure...
# Create directory if needed
if mkdir -p "$UNIX_SOCKET_PATH"; then
    echo "[✓] Created directory $UNIX_SOCKET_PATH"
else
    echo "[✗] Failed to create directory $UNIX_SOCKET_PATH"
    exit 1
fi

echo "[~] Creating socket with netcat..."
# Create socket with nc -lU in background and then kill it to create the socket file
if timeout 1 nc -lU "$FULL_UNIX_SOCKET_PATH" 2>/dev/null || true; then
    echo "[✓] Socket created at $FULL_UNIX_SOCKET_PATH"
else
    echo "[!] Socket creation with netcat had issues, but continuing..."
fi

echo "[~] Testing connection to target..."
# Test if we can reach the target before starting socat
if ! nc -z "$TARGET_HOST" "$TARGET_PORT" 2>/dev/null; then
    echo "[!] Cannot connect to $TARGET_HOST:$TARGET_PORT - socat will retry automatically"
else
    echo "[✓] Connection to $TARGET_HOST:$TARGET_PORT is working"
fi

# Signal handler for graceful shutdown
cleanup() {
    echo "[!] Received SIGTERM, shutting down gracefully..."
    if [ ! -z "$SOCAT_PID" ]; then
        echo "[~] Stopping socat process (PID: $SOCAT_PID)..."
        kill "$SOCAT_PID" 2>/dev/null || true
        wait "$SOCAT_PID" 2>/dev/null || true
    fi
    echo "[~] Cleanup completed, exiting..."
    exit 0
}

# Set up signal trap
trap cleanup SIGTERM SIGINT

echo "[~] Starting socat proxy..."
# Start socat with verbose logging and redirect to stdout/stderr
if socat -d -d UNIX-LISTEN:$FULL_UNIX_SOCKET_PATH,fork,unlink-early TCP:$TARGET_HOST:$TARGET_PORT & then
    SOCAT_PID=$!
    echo "[✓] Socat started with PID: $SOCAT_PID"
    echo "[~] Container is ready and running..."
else
    echo "[✗] Failed to start socat proxy"
    exit 1
fi

# Keep the script alive and wait for socat process
while kill -0 "$SOCAT_PID" 2>/dev/null; do
    sleep 1
done

echo "[✗] Socat process has stopped"
exit 1

