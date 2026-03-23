#!/bin/sh
set -e

# Function to escape TOML string values
escape_toml() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Function to convert comma-separated recipients to TOML array format
recipients_to_toml() {
    echo "$1" | awk -F',' '{
        result = "["
        for (i = 1; i <= NF; i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)  # trim whitespace
            # Escape quotes and backslashes
            gsub(/\\/, "\\\\", $i)
            gsub(/"/, "\\\"", $i)
            result = result "\"" $i "\""
            if (i < NF) result = result ", "
        }
        result = result "]"
        print result
    }'
}

# Collect all website environment variables
WEBSITE_CONFIG=""
WEBSITE_COUNT=0
i=1

while true; do
    prefix="APP_WEBSITE_${i}_"

    # Get website variables using printenv (safer than eval)
    NAME=$(printenv "${prefix}NAME" 2>/dev/null || true)
    BASE_URL=$(printenv "${prefix}BASE_URL" 2>/dev/null || true)
    WEBSITE_ID=$(printenv "${prefix}ID" 2>/dev/null || true)
    USERNAME=$(printenv "${prefix}USERNAME" 2>/dev/null || true)
    PASSWORD=$(printenv "${prefix}PASSWORD" 2>/dev/null || true)
    RECIPIENTS=$(printenv "${prefix}RECIPIENTS" 2>/dev/null || true)
    TIMEZONE=$(printenv "${prefix}TIMEZONE" 2>/dev/null || true)
    TIMEZONE="${TIMEZONE:-UTC}"
    DISABLED=$(printenv "${prefix}DISABLED" 2>/dev/null || true)

    # If NAME is missing, we've reached the end
    if [ -z "$NAME" ]; then
        break
    fi

    # Check if this website is disabled
    if [ "$DISABLED" = "true" ]; then
        echo "Skipping disabled website $i: ${NAME}"
        i=$((i + 1))
        continue
    fi

    # Skip if missing required fields
    if [ -z "$BASE_URL" ] || [ -z "$WEBSITE_ID" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$RECIPIENTS" ]; then
        echo "WARNING: Website $i (${NAME}) missing required fields, skipping"
        i=$((i + 1))
        continue
    fi

    # Convert recipients to TOML array format
    TOML_RECIPIENTS=$(recipients_to_toml "$RECIPIENTS")

    # Generate TOML for this website
    WEBSITE_CONFIG="${WEBSITE_CONFIG}
[websites.website_${i}]
name = \"$(escape_toml "$NAME")\"
base_url = \"$(escape_toml "$BASE_URL")\"
id = \"$(escape_toml "$WEBSITE_ID")\"
username = \"$(escape_toml "$USERNAME")\"
password = \"$(escape_toml "$PASSWORD")\"
recipients = ${TOML_RECIPIENTS}
timezone = \"$(escape_toml "$TIMEZONE")\"
"

    WEBSITE_COUNT=$((WEBSITE_COUNT + 1))
    i=$((i + 1))
done

# Check if we have required env vars and no mounted config
USE_ENV_VARS=false
if [ -n "$SMTP_HOST" ] && [ -n "$SMTP_PORT" ] && [ -n "$SMTP_USERNAME" ] && [ -n "$SMTP_PASSWORD" ] && [ -n "$SMTP_FROM" ]; then
    USE_ENV_VARS=true
fi

if [ "$USE_ENV_VARS" = "true" ]; then
    # Env vars provided, generate config
    if [ "$WEBSITE_COUNT" -eq 0 ]; then
        echo "ERROR: At least one website configuration is required"
        echo "ERROR: Set APP_WEBSITE_1_* variables to configure a website"
        exit 1
    fi

    echo "Generating config.toml from environment variables..."
    echo "Found ${WEBSITE_COUNT} website(s) configured"

    # Ensure config directory exists
    mkdir -p /etc/umami-alerts

    # Remove existing config if present (to avoid appending to old version)
    if [ -f /etc/umami-alerts/config.toml ]; then
        rm /etc/umami-alerts/config.toml
    fi

    # Generate config.toml
    cat > /etc/umami-alerts/config.toml <<EOF
[app]
debug = ${APP_DEBUG:-false}
dry_run = ${APP_DRY_RUN:-false}
max_concurrent_jobs = ${APP_MAX_CONCURRENT_JOBS:-4}
report_type = "${APP_REPORT_TYPE:-daily}"

[smtp]
host = "${SMTP_HOST}"
port = ${SMTP_PORT}
username = "$(escape_toml "$SMTP_USERNAME")"
password = "$(escape_toml "$SMTP_PASSWORD")"
from = "$(escape_toml "$SMTP_FROM")"
skip_verify = ${SMTP_SKIP_TLS_VERIFY:-false}
tls = ${SMTP_TLS:-true}
${WEBSITE_CONFIG}
EOF

    echo "Config generated successfully"
else
    # No env vars - check if there's a mounted config file
    if [ ! -f /etc/umami-alerts/config.toml ]; then
        echo "ERROR: Missing required environment variables (SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM)"
        echo "ERROR: No config file found at /etc/umami-alerts/config.toml"
        echo "ERROR: Either set environment variables or mount a config file"
        exit 1
    fi

    # Config file exists, use it directly
    echo "Using mounted config file at /etc/umami-alerts/config.toml"
fi

# Setup cron - redirect output to container stdout/stderr so it's visible in logs
echo "${CRON_SCHEDULE} /usr/local/bin/umami-alerts --config /etc/umami-alerts/config.toml >> /proc/1/fd/1 2>> /proc/1/fd/2" \
    | crontab -

echo "Starting crond with schedule: ${CRON_SCHEDULE}"
exec crond -f -l 2