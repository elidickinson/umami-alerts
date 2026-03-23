#!/bin/sh
set -e

# Validate required environment variables
if [ -z "$SMTP_HOST" ]; then
    echo "ERROR: SMTP_HOST environment variable is required"
    exit 1
fi

if [ -z "$SMTP_PORT" ]; then
    echo "ERROR: SMTP_PORT environment variable is required"
    exit 1
fi

if [ -z "$SMTP_USERNAME" ]; then
    echo "ERROR: SMTP_USERNAME environment variable is required"
    exit 1
fi

if [ -z "$SMTP_PASSWORD" ]; then
    echo "ERROR: SMTP_PASSWORD environment variable is required"
    exit 1
fi

if [ -z "$SMTP_FROM" ]; then
    echo "ERROR: SMTP_FROM environment variable is required"
    exit 1
fi

# Ensure config directory exists
mkdir -p /etc/umami-alerts

# Generate config.toml from environment variables if not provided
if [ ! -f /etc/umami-alerts/config.toml ]; then
    echo "Generating config.toml from environment variables..."

    cat > /etc/umami-alerts/config.toml <<EOF
[app]
debug = ${APP_DEBUG:-false}
dry_run = ${APP_DRY_RUN:-false}
max_concurrent_jobs = ${APP_MAX_CONCURRENT_JOBS:-4}
report_type = "${APP_REPORT_TYPE:-daily}"

[smtp]
host = "${SMTP_HOST}"
port = ${SMTP_PORT}
username = "${SMTP_USERNAME}"
password = "${SMTP_PASSWORD}"
from = "${SMTP_FROM}"
skip_verify = ${SMTP_SKIP_TLS_VERIFY:-false}
tls = ${SMTP_TLS:-true}
EOF
fi

# Append websites configuration if provided
if [ -n "$APP_WEBSITES_CONFIG" ]; then
    echo "$APP_WEBSITES_CONFIG" >> /etc/umami-alerts/config.toml
fi

echo "${CRON_SCHEDULE} /usr/local/bin/umami-alerts --config /etc/umami-alerts/config.toml" \
    | crontab -

echo "Starting crond with schedule: ${CRON_SCHEDULE}"
exec crond -f -l 2