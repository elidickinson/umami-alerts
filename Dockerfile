FROM rust:1-alpine AS builder

RUN apk add --no-cache musl-dev

WORKDIR /build

# Cache dependencies by copying and building with dummy src
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release --bins && rm -rf src

# Copy actual source and rebuild (uses cached dependencies)
COPY src/ src/
COPY templates/ templates/
RUN cargo build --release

FROM alpine:3.21

RUN apk add --no-cache tini

COPY --from=builder /build/target/release/umami-alerts /usr/local/bin/umami-alerts
COPY docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default: daily at 8:00 AM UTC
ENV CRON_SCHEDULE="0 8 * * *"

ENTRYPOINT ["tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
