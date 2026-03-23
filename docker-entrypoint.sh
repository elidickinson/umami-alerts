#!/bin/sh
set -e

# Function to extract base URL and share ID from share URL
# Format: https://umami.example.com/share/xxxxx
# Handles subpaths and trailing slashes correctly
parse_share_url() {
    local url="$1"
    # Strip /share/{id} (with optional trailing slash) to get base URL
    base_url=$(echo "$url" | sed -E 's|/share/[^/]+/?$||')
    # Extract share ID (text after /share/, before optional trailing slash)
    share_id=$(echo "$url" | sed -E 's|^.*/share/([^/]+)/?$|\1|')
    echo "$base_url|$share_id"
}

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
    SHARE_URL=$(printenv "${prefix}SHARE_URL" 2>/dev/null || true)
    SHARE_ID=$(printenv "${prefix}SHARE_ID" 2>/dev/null || true)
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

    # Parse share_url if provided
    if [ -n "$SHARE_URL" ]; then
        # Extract base_url and share_id from share_url
        PARSED=$(parse_share_url "$SHARE_URL")
        EXTRACTED_BASE_URL=$(echo "$PARSED" | cut -d'|' -f1)
        EXTRACTED_SHARE_ID=$(echo "$PARSED" | cut -d'|' -f2)
        
        # Use extracted values if they're valid
        if [ -n "$EXTRACTED_BASE_URL" ] && [ -n "$EXTRACTED_SHARE_ID" ]; then
            BASE_URL="$EXTRACTED_BASE_URL"
            SHARE_ID="$EXTRACTED_SHARE_ID"
            echo "Website $i (${NAME}): Using share_url - base_url=$BASE_URL, share_id=$SHARE_ID"
        else
            echo "WARNING: Website $i (${NAME}) - invalid share_url format, skipping"
            i=$((i + 1))
            continue
        fi
    fi

    # Skip if missing required fields
    # Auth priority: SHARE_URL > SHARE_ID > (ID + USERNAME + PASSWORD)
    if [ -z "$BASE_URL" ] || [ -z "$RECIPIENTS" ]; then
        echo "WARNING: Website $i (${NAME}) missing required fields, skipping"
        i=$((i + 1))
        continue
    fi

    # Validate authentication
    if [ -n "$SHARE_ID" ]; then
        debug="Using share_id authentication"
    elif [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        if [ -z "$WEBSITE_ID" ]; then
            echo "WARNING: Website $i (${NAME}) - must provide ID with username/password, skipping"
            i=$((i + 1))
            continue
        fi
        debug="Using username/password authentication"
    else
        echo "WARNING: Website $i (${NAME}) - must provide SHARE_URL, SHARE_ID, or (ID/USERNAME/PASSWORD), skipping"
        i=$((i + 1))
        continue
    fi

    # Convert recipients to TOML array format
    TOML_RECIPIENTS=$(recipients_to_toml "$RECIPIENTS")

    # Start TOML section
    WEBSITE_CONFIG="${WEBSITE_CONFIG}
[websites.website_${i}]
name = \"$(escape_toml "$NAME")\"
base_url = \"$(escape_toml "$BASE_URL")\""

    # Add optional id (for username/password mode)
    if [ -n "$WEBSITE_ID" ]; then
        WEBSITE_CONFIG="${WEBSITE_CONFIG}
id = \"$(escape_toml "$WEBSITE_ID")\""
    fi

    # Add optional username
    if [ -n "$USERNAME" ]; then
        WEBSITE_CONFIG="${WEBSITE_CONFIG}
username = \"$(escape_toml "$USERNAME")\""
    fi

    # Add optional password
    if [ -n "$PASSWORD" ]; then
        WEBSITE_CONFIG="${WEBSITE_CONFIG}
password = \"$(escape_toml "$PASSWORD")\""
    fi

    # Add optional share_id
    if [ -n "$SHARE_ID" ]; then
        WEBSITE_CONFIG="${WEBSITE_CONFIG}
share_id = \"$(escape_toml "$SHARE_ID")\""
    fi

    # Add optional share_url
    if [ -n "$SHARE_URL" ]; then
        WEBSITE_CONFIG="${WEBSITE_CONFIG}
share_url = \"$(escape_toml "$SHARE_URL")\""
    fi

    WEBSITE_CONFIG="${WEBSITE_CONFIG}
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

    # Normalize boolean values to lowercase for TOML
    APP_DEBUG_NORM=$(echo "${APP_DEBUG:-false}" | tr '[:upper:]' '[:lower:]')
    APP_DRY_RUN_NORM=$(echo "${APP_DRY_RUN:-false}" | tr '[:upper:]' '[:lower:]')
    SMTP_SKIP_TLS_VERIFY_NORM=$(echo "${SMTP_SKIP_TLS_VERIFY:-false}" | tr '[:upper:]' '[:lower:]')
    SMTP_TLS_NORM=$(echo "${SMTP_TLS:-true}" | tr '[:upper:]' '[:lower:]')

    cat > /etc/umami-alerts/config.toml <<EOF
[app]
debug = ${APP_DEBUG_NORM}
dry_run = ${APP_DRY_RUN_NORM}
max_concurrent_jobs = ${APP_MAX_CONCURRENT_JOBS:-4}
report_type = "${APP_REPORT_TYPE:-daily}"

[smtp]
host = "${SMTP_HOST}"
port = ${SMTP_PORT}
username = "$(escape_toml "$SMTP_USERNAME")"
password = "$(escape_toml "$SMTP_PASSWORD")"
from = "$(escape_toml "$SMTP_FROM")"
skip_verify = ${SMTP_SKIP_TLS_VERIFY_NORM}
tls = ${SMTP_TLS_NORM}
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
