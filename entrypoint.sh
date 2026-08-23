#!/bin/sh
set -e

CYAN="\033[1;36m"
NC="\033[0m"

log()  { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
fail() { echo "$(date '+%Y-%m-%d %H:%M:%S') [!] $*" >&2; exit 1; }

print_banner() {
    version=$(cat VERSION 2>/dev/null || echo "unknown")
    title="Socat Proxy - Version ${version}"
    lines="Source: https://git.djeex.fr/Djeex/socat-proxy
Mirror: https://github.com/Djeex/socat-proxy"

    width=${#title}
    old_ifs=$IFS
    IFS='
'
    for l in $lines; do
        [ ${#l} -gt "$width" ] && width=${#l}
    done
    IFS=$old_ifs
    width=$((width + 2))

    border=""
    i=0
    while [ "$i" -lt "$width" ]; do
        border="${border}─"
        i=$((i + 1))
    done
    printf "${CYAN}╭%s╮${NC}\n" "$border"

    total_pad=$((width - ${#title}))
    left=$((total_pad / 2))
    right=$((total_pad - left))
    printf "${CYAN}│${NC}%*s%s%*s${CYAN}│${NC}\n" "$left" "" "$title" "$right" ""

    printf "${CYAN}├%s┤${NC}\n" "$border"

    IFS='
'
    for l in $lines; do
        printf "${CYAN}│${NC} %-*s${CYAN}│${NC}\n" "$((width - 1))" "$l"
    done
    IFS=$old_ifs

    printf "${CYAN}╰%s╯${NC}\n" "$border"
}

print_banner

DEBUG_LEVEL=${DEBUG_LEVEL:-1}
UNIX_SOCKET_PATH=${UNIX_SOCKET_PATH%/}
HOST_SOCKET_PATH=${HOST_SOCKET_PATH%/}

FULL_HOST_SOCKET_PATH="$HOST_SOCKET_PATH/$UNIX_SOCKET_NAME"
FULL_UNIX_SOCKET_PATH="$UNIX_SOCKET_PATH/$UNIX_SOCKET_NAME"

# Validate required environment variables
[ -n "$TARGET_HOST" ] || fail "TARGET_HOST environment variable is required"
[ -n "$TARGET_PORT" ] || fail "TARGET_PORT environment variable is required"
[ -n "$UNIX_SOCKET_NAME" ] || fail "UNIX_SOCKET_NAME environment variable is required"
[ -n "$UNIX_SOCKET_PATH" ] || fail "UNIX_SOCKET_PATH environment variable is required"
[ -n "$HOST_SOCKET_PATH" ] || fail "HOST_SOCKET_PATH environment variable is required"

PUID=${PUID:-911}
PGID=${PGID:-911}

case "$PGID" in
    ''|*[!0-9]*) fail "PGID '$PGID' is not a valid numeric group id." ;;
esac
case "$PUID" in
    ''|*[!0-9]*) fail "PUID '$PUID' is not a valid numeric user id." ;;
esac

log "[i] Requested PUID=$PUID, PGID=$PGID"

log "[~] Checking group for GID $PGID..."
GROUP_NAME=$(getent group "$PGID" | cut -d: -f1 || true)
if [ -z "$GROUP_NAME" ]; then
    log "[→] No existing group with GID $PGID, creating 'appgroup'."
    addgroup -g "$PGID" appgroup || fail "Failed to create group with GID $PGID (addgroup exited $?)."
    GROUP_NAME=appgroup
else
    log "[i] Reusing existing group '$GROUP_NAME' (GID $PGID)."
fi
log "[✓] Group ready: $GROUP_NAME"

log "[~] Checking user for UID $PUID..."
USER_NAME=$(getent passwd "$PUID" | cut -d: -f1 || true)
if [ -z "$USER_NAME" ]; then
    log "[→] No existing user with UID $PUID, creating 'appuser'."
    adduser -D -u "$PUID" -G "$GROUP_NAME" appuser || fail "Failed to create user with UID $PUID (adduser exited $?)."
    USER_NAME=appuser
else
    log "[i] Reusing existing user '$USER_NAME' (UID $PUID)."
fi
log "[✓] User ready: $USER_NAME"

log "[~] Starting socat proxy..."
log "[i] TCP target: $TARGET_HOST:$TARGET_PORT"
log "[i] HOST path: $HOST_SOCKET_PATH"
log "[i] Full host socket path: $FULL_HOST_SOCKET_PATH"
log "[i] Full socket path: $FULL_UNIX_SOCKET_PATH"

# Check if socket file/folder exists and handle it
if [ -e "$FULL_UNIX_SOCKET_PATH" ]; then
    log "[~] Socket file/folder $FULL_UNIX_SOCKET_PATH exists, removing it..."
    if rm -rf "$FULL_UNIX_SOCKET_PATH"; then
        log "[✓] Removed existing socket $FULL_UNIX_SOCKET_PATH"
    else
        fail "Failed to remove existing socket $FULL_UNIX_SOCKET_PATH"
    fi
fi

log "[~] Creating socket directory structure..."
# Create directory if needed
if mkdir -p "$UNIX_SOCKET_PATH"; then
    log "[✓] Created directory $UNIX_SOCKET_PATH"
else
    fail "Failed to create directory $UNIX_SOCKET_PATH"
fi

# Grant the target user write access to the socket directory so the
# su-exec'd socat process below can create the socket file in it.
log "[~] Setting ownership of $UNIX_SOCKET_PATH to $USER_NAME:$GROUP_NAME..."
chown "$USER_NAME:$GROUP_NAME" "$UNIX_SOCKET_PATH" || fail "chown on $UNIX_SOCKET_PATH failed — check that the host directory permissions allow it."
log "[✓] Ownership set on $UNIX_SOCKET_PATH"

log "[~] Preparing socket path..."
# Create socket file by touching it, then remove it (this creates the path but leaves it clean for socat)
touch "$FULL_UNIX_SOCKET_PATH"
rm "$FULL_UNIX_SOCKET_PATH"
log "[✓] Socket path prepared at $FULL_UNIX_SOCKET_PATH"

# Debug: Check if socket file exists and its permissions
if [ -S "$FULL_UNIX_SOCKET_PATH" ]; then
    log "[✓] Socket file exists and is a socket"
    ls -la "$FULL_UNIX_SOCKET_PATH"
else
    log "[!] Socket file does not exist or is not a socket"
    ls -la "$UNIX_SOCKET_PATH"
fi

log "[~] Testing connection to target..."
# Test if we can reach the target before starting socat
if ! nc -z "$TARGET_HOST" "$TARGET_PORT" 2>/dev/null; then
    log "[!] Cannot connect to $TARGET_HOST:$TARGET_PORT - socat will retry automatically"
else
    log "[✓] Connection to $TARGET_HOST:$TARGET_PORT is working"
fi

# Signal handler for graceful shutdown
cleanup() {
    log "[!] Received SIGTERM, shutting down gracefully..."
    if [ -n "$SOCAT_PID" ]; then
        log "[~] Stopping socat process (PID: $SOCAT_PID)..."
        kill "$SOCAT_PID" 2>/dev/null || true
        wait "$SOCAT_PID" 2>/dev/null || true
    fi
    log "[~] Cleanup completed, exiting..."
    exit 0
}

# Set up signal trap
trap cleanup SIGTERM SIGINT

log "[~] Starting socat proxy..."
# Start socat with configurable verbosity
DEBUG_FLAGS=""
if [ "$DEBUG_LEVEL" -eq 1 ]; then
    DEBUG_FLAGS="-d"
elif [ "$DEBUG_LEVEL" -eq 2 ]; then
    DEBUG_FLAGS="-d -d"
elif [ "$DEBUG_LEVEL" -eq 3 ]; then
    DEBUG_FLAGS="-d -d -d"
fi

log "[i] Using debug level: $DEBUG_LEVEL ($DEBUG_FLAGS)"

# mode=666 keeps the socket connectable from another container's UID
# regardless of PUID/PGID here — see project notes on the socket
# permission trade-off (this proxy's own threat model is the host/network
# boundary, not multi-tenant isolation between containers on the same host).
log "[→] Dropping privileges to $USER_NAME:$GROUP_NAME and starting socat"
if su-exec "$USER_NAME:$GROUP_NAME" socat $DEBUG_FLAGS UNIX-LISTEN:$FULL_UNIX_SOCKET_PATH,fork,unlink-early,mode=666 TCP:$TARGET_HOST:$TARGET_PORT & then
    SOCAT_PID=$!
    log "[✓] Socat started with PID: $SOCAT_PID"
    log "[i] Socat command: socat $DEBUG_FLAGS UNIX-LISTEN:$FULL_UNIX_SOCKET_PATH,fork,unlink-early,mode=666 TCP:$TARGET_HOST:$TARGET_PORT"
    log "[~] Container is ready and running..."

    # Debug: Check socket after socat starts
    sleep 2
    if [ -S "$FULL_UNIX_SOCKET_PATH" ]; then
        log "[✓] Socat socket is active"
        ls -la "$FULL_UNIX_SOCKET_PATH"
    else
        log "[!] Socat socket not found"
    fi
else
    fail "Failed to start socat proxy"
fi

# Keep the script alive and wait for socat process
while kill -0 "$SOCAT_PID" 2>/dev/null; do
    sleep 1
done

fail "Socat process has stopped"
