# Deployment with Dokploy

This guide shows how to deploy umami-alerts to Dokploy using environment variables for all configuration.

## Quick Start

1. Create an Application → **Git Repository**
2. Configure **Dockerfile** build type (not Docker Compose)
3. Add environment variables (see below)
4. Deploy

## Environment Variables

### Required

| Variable | Example | Description |
|----------|---------|-------------|
| `SMTP_HOST` | `mail.smtp2go.com` | SMTP server hostname |
| `SMTP_PORT` | `2525` | SMTP server port (numeric) |
| `SMTP_USERNAME` | `your-username` | SMTP authentication username |
| `SMTP_PASSWORD` | `your-password` | SMTP authentication password |
| `SMTP_FROM` | `reports@example.com` | From email address for reports |

### Optional (App Settings)

| Variable | Default | Description |
|----------|---------|-------------|
| `CRON_SCHEDULE` | `0 8 * * *` | Cron schedule for report generation |
| `SMTP_TLS` | `true` | Enable TLS for SMTP connections |
| `SMTP_SKIP_TLS_VERIFY` | `false` | Skip TLS certificate verification |
| `APP_DEBUG` | `false` | Enable debug logging |
| `APP_DRY_RUN` | `false` | Generate reports without sending (for testing) |
| `APP_MAX_CONCURRENT_JOBS` | `4` | Maximum concurrent website checks |
| `APP_REPORT_TYPE` | `daily` | Report type: `daily` or `weekly` |

### Website Configuration

Configure one or more websites using numbered environment variables:

**For Website 1:**
```
APP_WEBSITE_1_NAME=My Website
APP_WEBSITE_1_BASE_URL=https://umami.example.com
APP_WEBSITE_1_ID=your-website-uuid
APP_WEBSITE_1_USERNAME=umami-user
APP_WEBSITE_1_PASSWORD=umami-password
APP_WEBSITE_1_RECIPIENTS=user1@example.com,user2@example.com
APP_WEBSITE_1_TIMEZONE=UTC
APP_WEBSITE_1_DISABLED=false  # Optional, defaults to false
```

**For Website 2 (add as many as needed):**
```
APP_WEBSITE_2_NAME=Blog
APP_WEBSITE_2_BASE_URL=https://analytics.yourdomain.com
APP_WEBSITE_2_ID=another-website-uuid
APP_WEBSITE_2_USERNAME=admin
APP_WEBSITE_2_PASSWORD=secure-password
APP_WEBSITE_2_RECIPIENTS=admin@example.com
APP_WEBSITE_2_TIMEZONE=America/New_York
```

> **Note:** Numbers must be sequential starting from 1. Missing numbers will stop detection. Use `APP_WEBSITE_X_DISABLED=true` to skip a website without breaking the sequence.

---

## Dokploy Setup Steps

### 1. Create Application
- In Dokploy, click **Create Application**
- Choose **Git Repository**
- Select your `umami-alerts` repository
- Use branch: `main`

### 2. Configure Build
- **Build Type**: Dockerfile
- **Dockerfile Path**: `Dockerfile`
- **Docker Context Path**: `.`

### 3. Add Environment Variables
Navigate to the **Environment** tab and add your variables:

**SMTP Configuration (required):**
```
SMTP_HOST=mail.smtp2go.com
SMTP_PORT=2525
SMTP_USERNAME=your-smtp2go-username
SMTP_PASSWORD=your-smtp2go-password
SMTP_FROM=your-verified-email@example.com
```

**App Settings (optional):**
```
CRON_SCHEDULE=0 8 * * *
APP_REPORT_TYPE=weekly
APP_DEBUG=false
```

**Websites (required - at least one):**
```
APP_WEBSITE_1_NAME=My Site
APP_WEBSITE_1_BASE_URL=https://umami.mysite.com
APP_WEBSITE_1_ID=550e8400-e29b-41d4-a716-446655440000
APP_WEBSITE_1_USERNAME=umami-user
APP_WEBSITE_1_PASSWORD=my-umami-password
APP_WEBSITE_1_RECIPIENTS=me@example.com
APP_WEBSITE_1_TIMEZONE=UTC
```

### 4. Deploy
Click the **Deploy** button

### 5. Verify
Check the logs in Dokploy to confirm:
- "Generating config.toml from environment variables..."
- "Config generated successfully"
- "Starting crond with schedule: 0 8 * * *"

---

## Alternative: Mount Config File

If you prefer managing configuration via a file instead of environment variables:

1. Create a `config.toml` file with all settings (see `config.sample.toml`)
2. Go to **Advanced** → **Volumes**
3. Create a **File Mount** at `/etc/umami-alerts/config.toml`
4. Upload your config file
5. Deploy

> **Note:** When using a file mount, environment variables are NOT used. The mounted file must be a complete, valid config including all `[app]`, `[smtp]`, and `[websites.*]` sections.
>
> **Note:** Environment variable approach is recommended. File mount is useful if you need complex TOML features or multiple websites with very different configurations.

---

## SMTP Configuration Examples

### SMTP2Go
```
SMTP_HOST=mail.smtp2go.com
SMTP_PORT=2525
SMTP_USERNAME=your-api-username
SMTP_PASSWORD=your-api-password
SMTP_FROM=your-verified-email@example.com
```

### SendGrid
```
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=SG.your-sendgrid-api-key
SMTP_FROM=your-sender@example.com
```

### Gmail (with App Password)
```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-specific-password
SMTP_FROM=your-email@gmail.com
```

---

## Testing

To test without sending actual emails:

1. Set `APP_DRY_RUN=true` in environment variables
2. Redeploy
3. Check logs to see report generation (no email sent)

Example:
```
APP_DRY_RUN=true
CRON_SCHEDULE="* * * * *"  # Run every minute for testing
```

When ready to go live, remove `APP_DRY_RUN=true` or set it to `false`.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Container fails to start** | Check logs for "Missing required environment variables" |
| **Missing SMTP vars** | Ensure `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` are all set |
| **Website not detected** | Ensure website numbering is sequential (1, 2, 3...) without gaps |
| **Recipients list broken** | Use comma-separated values without spaces: `user1@example.com,user2@example.com` |
| **Timezone error** | Verify timezone is valid (e.g., `UTC`, `America/New_York`, `Asia/Kolkata`) |
| **SMTP connection issues** | Try different ports (2525, 8025, 587, 25) |
| **TLS errors** | Set `SMTP_SKIP_TLS_VERIFY=true` |
| **Cron not running** | Check `CRON_SCHEDULE` format uses standard cron syntax |

---

## Security Notes

- **Never commit** passwords or API keys to your repository
- **Environment variables** are stored in Dokploy's database - restrict access to Dokploy
- **Rotate credentials regularly** for best security practice
- **File mount approach** - If using a mounted config file, passwords will be stored in plain text on the server. Ensure the server access is restricted.

---

## Getting Website UUID

Find your Umami website UUID:
1. Log into your Umami instance
2. Go to **Settings** → **Websites**
3. Click on your website
4. The UUID is shown in the **Website ID** field

Example: `e97f683e-12e8-4fb5-970b-f5171804fe21`