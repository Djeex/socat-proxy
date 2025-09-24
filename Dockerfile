FROM alpine:latest

RUN apk add --no-cache socat netcat-openbsd \
    && rm -rf /var/cache/apk/* /tmp/*

COPY entrypoint.sh VERSION /
RUN mkdir -p /socket \
    && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]