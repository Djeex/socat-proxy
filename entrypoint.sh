#!/bin/sh
set -e

# Set default values if not provided
TARGET_HOST=${TARGET_HOST}
TARGET_PORT=${TARGET_PORT}
UNIX_SOCKET_PATH=${UNIX_SOCKET_PATH}

echo "Starting socat proxy..."
echo "UNIX socket: $UNIX_SOCKET_PATH"
echo "TCP target: $TARGET_HOST:$TARGET_PORT"

# Check if socket file/folder exists and handle it
if [ -e "$UNIX_SOCKET_PATH" ]; then
    echo "Socket file/folder $UNIX_SOCKET_PATH exists, removing it..."
    rm -rf "$UNIX_SOCKET_PATH"
fi

echo "Creating socket directory structure..."
# Create directory if needed
mkdir -p "$(dirname "$UNIX_SOCKET_PATH")"

echo "Creating socket with netcat..."
# Create socket with nc -lU in background and then kill it to create the socket file
timeout 1 nc -lU "$UNIX_SOCKET_PATH" || true

# Execute socat to proxy UNIX socket to TCP
exec socat UNIX-LISTEN:$UNIX_SOCKET_PATH,fork,unlink-early TCP:$TARGET_HOST:$TARGET_PORT

