# Deployment with Dokploy

This guide shows how to deploy umami-alerts to Dokploy using environment variables for secure credential management.

## Option A: Dockerfile Deployment (Recommended)

### Setup in Dokploy

1. **Create Application**
   - Choose **Git Repository** deployment
   - Select this repository
   - Use branch: `main`

2. **Configure Build Type**
   - Choose **Dockerfile**
   - Dockerfile Path: `Dockerfile`
   - Docker Context Path: `.`

3. **Add Environment Variables** (in the **Environment** tab)

**Required (use Dokploy Secrets for passwords):**
```
SMTP_HOST=mail.smtp2go.com
SMTP_PORT=2525
SMTP_USERNAME=your-smtp2go-username
SMTP_PASSWORD=your-smtp2go-password  ← Use Dokploy Secrets
SMTP_FROM=your-verified-email@example.com
```

**Optional (default values shown):**
```
CRON_SCHEDULE=0 8 * * *
SMTP_TLS=true
SMTP_SKIP_TLS_VERIFY=false  # Maps to skip_verify in TOML config
APP_DEBUG=false
APP_DRY_RUN=false
APP_MAX_CONCURRENT_JOBS=4
APP_REPORT_TYPE=daily
```

> **Note:** Required environment variables are validated on container startup. The container will fail to start if any required variable is missing.

4. **Configure Websites**

**Recommended: Mount config file** (for one or multiple sites)
- Go to **Advanced** → **Volumes**
- Create a **File Mount** for `/etc/umami-alerts/config.toml`
- Upload your config file with only `[websites.*]` sections
- Example format:
```toml
[websites.site1]
base_url = "https://umami.example.com"
id = "your-website-uuid"
name = "My Website"
username = "umami-username"
password = "umami-password"
recipients = ["user@example.com"]
timezone = "UTC"

[websites.site2]
base_url = "https://analytics.example.com"
id = "another-website-uuid"
name = "Blog"
username = "umami-user"
password = "your-password"
recipients = ["admin@example.com", "reports@example.com"]
timezone = "America/New_York"
```

**Alternative: Single website via `APP_WEBSITES_CONFIG`**
- Add to environment variables (works for a single website)
- Multi-line environment variables can be unreliable in some configs
- Example:
```
APP_WEBSITES_CONFIG=[websites.site1]
base_url = "https://umami.example.com"
id = "your-website-uuid"
name = "My Website"
username = "umami-username"
password = "umami-password"
recipients = ["user@example.com"]
timezone = "UTC"
```

5. **Deploy**
   - Click **Deploy**

---

## Option B: Docker Compose Deployment

1. **Create Application** → **Docker Compose**
2. Select `docker-compose.dokploy.yml`
3. Add environment variables as shown above
4. Deploy

---

## SMTP Configuration

### SMTP2Go (Example)

For SMTP2Go specifically:
- **Host**: `mail.smtp2go.com` or `smtpcorp.com`
- **Port**: Try `2525` (recommended) or `587` (with TLS)
- **Username**: Your SMTP2Go API username
- **Password**: Your SMTP2Go password
- **From**: Must be a verified email address in your SMTP2Go account

### Generic SMTP

Replace the example values with your SMTP provider's settings:
- Host and port from your SMTP provider
- Username and password from your SMTP account
- From address should match your account's verified email

---

## Environment Variable Reference

### Required

| Variable | Description |
|----------|-------------|
| `SMTP_HOST` | SMTP server hostname |
| `SMTP_PORT` | SMTP server port (numeric) |
| `SMTP_USERNAME` | SMTP authentication username |
| `SMTP_PASSWORD` | SMTP authentication password |
| `SMTP_FROM` | From email address for reports |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `CRON_SCHEDULE` | `0 8 * * *` | Cron schedule for report generation |
| `SMTP_TLS` | `true` | Enable TLS for SMTP连接 |
| `SMTP_SKIP_TLS_VERIFY` | `false` | Skip TLS certificate verification (maps to `skip_verify` in TOML) |
| `APP_DEBUG` | `false` | Enable debug logging |
| `APP_DRY_RUN` | `false` | Generate reports without sending (for testing) |
| `APP_MAX_CONCURRENT_JOBS` | `4` | Maximum concurrent website checks |
| `APP_REPORT_TYPE` | `daily` | Report type: `daily` or `weekly` |
| `APP_WEBSITES_CONFIG` | (empty) | Single website config as TOML (use file mount for multiple) |

---

## Testing Deployment

To test without sending real emails:

1. Set `APP_DRY_RUN=true` in environment variables
2. Redeploy
3. Check logs to see report generation (no email sent)

When ready to go live, remove or set `APP_DRY_RUN=false`.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Container fails to start** | Check logs for missing required environment variables (`SMTP_HOST`, `SMTP_PORT`, etc.) |
| **SMTP connection issues** | Try different ports (2525, 8025, 587, 25) |
| **TLS errors** | Set `SMTP_SKIP_TLS_VERIFY=true` |
| **Cron not running** | Check `CRON_SCHEDULE` format (Cron syntax) |
| **Config not loading** | Check Docker logs for config generation errors |
| **Websites ignored when using file mount** | Ensure file mount path is `/etc/umami-alerts/config.toml` and contains only `[websites.*]` sections |

---

## Security Notes

- **Never commit `config.toml` to your repository** - it contains sensitive credentials
- **Use Dokploy's Secrets feature for passwords** - Secrets are stored encrypted at rest and injected as environment variables at runtime
- **Store `SMTP_PASSWORD` and website passwords as Dokploy secrets**, not plain environment variables
- **Rotate credentials regularly** - For best security practice
- **Config files in containers** - The generated `/etc/umami-alerts/config.toml` inside the container contains plaintext passwords. Anyone with `docker exec` access can read these credentials. This is inherent to the app's design, so secure container access accordingly