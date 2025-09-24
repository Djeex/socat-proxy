FROM alpine:latest

# Install socat and netcat in a single RUN command and clean up cache
RUN apk add --no-cache socat netcat-openbsd \
    && rm -rf /var/cache/apk/* /tmp/*

# Create socket directory and copy/set permissions in single layers
COPY entrypoint.sh /entrypoint.sh
RUN mkdir -p /socket \
    && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]