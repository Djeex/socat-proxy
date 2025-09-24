#!/bin/sh
set -e

# Set default values if not provided
TARGET_HOST=${TARGET_HOST}
TARGET_PORT=${TARGET_PORT}
UNIX_SOCKET_PATH=${UNIX_SOCKET_PATH}
UNIX_SOCKET_NAME=$(basename "$UNIX_SOCKET_PATH")
HOST_SOCKET_PATH=${HOST_SOCKET_PATH}

# Validate required environment variables
if [ -z "$TARGET_HOST" ]; then
    echo "ERROR: TARGET_HOST environment variable is required"
    exit 1
fi

if [ -z "$TARGET_PORT" ]; then
    echo "ERROR: TARGET_PORT environment variable is required"
    exit 1
fi

if [ -z "$UNIX_SOCKET_PATH" ]; then
    echo "ERROR: UNIX_SOCKET_PATH environment variable is required"
    exit 1
fi

if [ -z "$HOST_SOCKET_PATH" ]; then
    echo "ERROR: HOST_SOCKET_PATH environment variable is required"
    exit 1
fi

echo "Starting socat proxy..."
echo "UNIX socket: $UNIX_SOCKET_PATH"
echo "TCP target: $TARGET_HOST:$TARGET_PORT"
echo "HOST path: $HOST_SOCKET_PATH"
echo "Socket name: $UNIX_SOCKET_NAME"

# Calculate full socket path
FULL_SOCKET_PATH="$HOST_SOCKET_PATH/$UNIX_SOCKET_NAME"
echo "Full socket path: $FULL_SOCKET_PATH"

# Check if socket file/folder exists and handle it
if [ -e "$FULL_SOCKET_PATH" ]; then
    echo "Socket file/folder $FULL_SOCKET_PATH exists, removing it..."
    if rm -rf "$FULL_SOCKET_PATH"; then
        echo "SUCCESS: Removed existing socket $FULL_SOCKET_PATH"
    else
        echo "ERROR: Failed to remove existing socket $FULL_SOCKET_PATH"
        exit 1
    fi
fi

echo "Creating socket directory structure..."
# Create directory if needed
if mkdir -p "$HOST_SOCKET_PATH"; then
    echo "SUCCESS: Created directory $HOST_SOCKET_PATH"
else
    echo "ERROR: Failed to create directory $HOST_SOCKET_PATH"
    exit 1
fi

echo "Creating socket with netcat..."
# Create socket with nc -lU in background and then kill it to create the socket file
if timeout 1 nc -lU "$FULL_SOCKET_PATH" 2>/dev/null || true; then
    echo "SUCCESS: Socket created at $FULL_SOCKET_PATH"
else
    echo "WARNING: Socket creation with netcat had issues, but continuing..."
fi

echo "Testing connection to target..."
# Test if we can reach the target before starting socat
if ! nc -z "$TARGET_HOST" "$TARGET_PORT" 2>/dev/null; then
    echo "WARNING: Cannot connect to $TARGET_HOST:$TARGET_PORT - socat will retry automatically"
else
    echo "SUCCESS: Connection to $TARGET_HOST:$TARGET_PORT is working"
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
if socat -d -d UNIX-LISTEN:$UNIX_SOCKET_PATH,fork,unlink-early TCP:$TARGET_HOST:$TARGET_PORT & then
    SOCAT_PID=$!
    echo "SUCCESS: Socat started with PID: $SOCAT_PID"
    echo "Container is ready and running..."
else
    echo "ERROR: Failed to start socat proxy"
    exit 1
fi

# Keep the script alive and wait for socat process
while kill -0 "$SOCAT_PID" 2>/dev/null; do
    sleep 1
done

echo "Socat process has stopped"
exit 1

