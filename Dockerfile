FROM alpine:3.24.1 AS base

RUN apk add --no-cache socat netcat-openbsd su-exec \
    && rm -rf /var/cache/apk/* /tmp/*

COPY entrypoint.sh VERSION /
RUN mkdir -p /socket \
    && chmod +x /entrypoint.sh

FROM base AS test

RUN apk add --no-cache bats bash procps

WORKDIR /app
COPY entrypoint.sh VERSION /app/
COPY tests/ /app/tests/

FROM base AS lint

RUN apk add --no-cache shellcheck
RUN shellcheck --severity=error -s sh /entrypoint.sh

# Kept as the last stage so `docker build .` (no --target) still produces
# the lean prod image, not the `test`/`lint` stages above.
FROM base
ENTRYPOINT ["/entrypoint.sh"]
