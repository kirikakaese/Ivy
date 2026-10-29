# MollySocket with Ivy's patch: no wake-up for messages the account's own
# devices send each other. Built from a pinned upstream version.
FROM docker.io/rust:bookworm AS builder
ARG MOLLYSOCKET_COMMIT=f1e10c97d4644df4d326b9d7dedb160b297d41ca
WORKDIR /app
RUN git clone https://github.com/mollyim/mollysocket.git . \
    && git checkout "$MOLLYSOCKET_COMMIT"
COPY own-account.patch .
RUN git apply own-account.patch \
    && cargo build --release --bin mollysocket

FROM docker.io/debian:bookworm-slim
WORKDIR /data
ENV MOLLY_HOST=0.0.0.0
ENV MOLLY_PORT=8020
RUN apt-get update \
    && apt-get install -y --no-install-recommends wget libssl3 libsqlite3-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/mollysocket /usr/local/bin/
HEALTHCHECK --interval=1m --timeout=3s \
    CMD wget -q --tries=1 "http://$MOLLY_HOST:$MOLLY_PORT/discover" -O - | grep '"mollysocket":{"version":'
ENTRYPOINT ["/usr/local/bin/mollysocket"]
