#!/bin/sh
set -e

# Set default values if not provided
TARGET_HOST=${TARGET_HOST}
TARGET_PORT=${TARGET_PORT}
UNIX_SOCKET_PATH=${UNIX_SOCKET_PATH:-/socket/docker.sock}

# Validate required environment variables
if [ -z "$TARGET_HOST" ]; then
    echo "ERROR: TARGET_HOST environment variable is required"
    exit 1
fi

if [ -z "$TARGET_PORT" ]; then
    echo "ERROR: TARGET_PORT environment variable is required"
    exit 1
fi

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

echo "Testing connection to target..."
# Test if we can reach the target before starting socat
if ! nc -z "$TARGET_HOST" "$TARGET_PORT" 2>/dev/null; then
    echo "WARNING: Cannot connect to $TARGET_HOST:$TARGET_PORT - socat will retry automatically"
fi

# Signal handler for graceful shutdown
cleanup() {
    echo "Received SIGTERM, shutting down gracefully..."
    if [ ! -z "$SOCAT_PID" ]; then
        echo "Stopping socat process (PID: $SOCAT_PID)..."
        kill "$SOCAT_PID" 2>/dev/null || true
        wait "$SOCAT_PID" 2>/dev/null || true
    fi
    echo "Cleanup completed, exiting..."
    exit 0
}

# Set up signal trap
trap cleanup SIGTERM SIGINT

echo "Starting socat proxy..."
# Start socat with verbose logging and redirect to stdout/stderr
socat -d -d UNIX-LISTEN:$UNIX_SOCKET_PATH,fork,unlink-early TCP:$TARGET_HOST:$TARGET_PORT &
SOCAT_PID=$!

echo "Socat started with PID: $SOCAT_PID"
echo "Container is ready and running..."

# Keep the script alive and wait for socat process
while kill -0 "$SOCAT_PID" 2>/dev/null; do
    sleep 1
done

echo "Socat process has stopped"
exit 1

