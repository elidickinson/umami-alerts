# Local Testing Setup Guide

## Prerequisites

```bash
# Install Rust if you haven't already
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## Quick Setup

### Option 1: Using .env File (Recommended for Local Development)

```bash
# Clone the repository
git clone https://github.com/Thunderbottom/umami-alerts.git
cd umami-alerts

# Copy the example .env file
cp .env.example .env

# Edit .env with your actual values
nano .env  # or use your favorite editor

# Build
cargo build --release

# Run (it will automatically use .env)
./target/release/umami-alerts --debug

# With config file override (if you have one)
./target/release/umami-alerts --debug --config config.toml
```

Your `.env` file for share URL authentication:

```bash
# App settings
APP_DEBUG=true
APP_DRY_RUN=true
APP_MAX_CONCURRENT_JOBS=1
APP_REPORT_TYPE=weekly

# SMTP settings
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=your-smtp-username
SMTP_PASSWORD=your-smtp-password
SMTP_FROM=reports@example.com
SMTP_TLS=true

# Website 1 - Using share URL (recommended)
APP_WEBSITE_1_SHARE_URL=https://umami.eli.pizza/share/YOUR-ACTUAL-SHARE-ID
APP_WEBSITE_1_NAME=Your Website
APP_WEBSITE_1_RECIPIENTS=your-email@example.com
APP_WEBSITE_1_TIMEZONE=UTC
```

### Option 2: Using Config File

```bash
cp config.sample.toml config.toml
# Edit config.toml
cargo build --release
./target/release/umami-alerts --debug --config config.toml
```

### Option 3: Environment Variables (No File Needed)

```bash
export APP_DEBUG=true
export APP_DRY_RUN=true
export SMTP_HOST=smtp.example.com
export SMTP_PORT=587
export SMTP_USERNAME=your-username
export SMTP_PASSWORD=your-password
export SMTP_FROM=reports@example.com
export APP_WEBSITE_1_SHARE_URL=https://umami.eli.pizza/share/xxxxx
export APP_WEBSITE_1_NAME=Your Website
export APP_WEBSITE_1_RECIPIENTS=your-email@example.com

cargo build --release
./target/release/umami-alerts --debug
```

## Configuration Precedence

The configuration is loaded in this order (later options override earlier ones):
1. Default values in sample config
2. `config.toml` file values
3. Environment variables
4. Command-line flags (`--debug`, `--config`)

So environment variables will override config file values.

## Development Mode (Faster Builds)

```bash
# Run directly with cargo (slower startup, no compilation)
cargo run -- --debug

# Or build debug mode (faster compilation)
cargo build
./target/debug/umami-alerts --debug
```

## Running Tests

```bash
# Run all tests
cargo test

# Run tests with output
cargo test -- --nocapture

# Run specific test
cargo test website_validation
```

## Finding Your Share URL

1. Go to your Umami dashboard: https://umami.eli.pizza/dashboard
2. Click your website
3. Look for a "Share" button/link
4. Copy the share URL: `https://umami.eli.pizza/share/xxxxx`
5. Paste into your `.env` or `config.toml`

## Configuring Multiple Websites

In `.env`, increment the number:

```bash
# Website 1
APP_WEBSITE_1_SHARE_URL=https://umami.eli.pizza/share/xxxxx
APP_WEBSITE_1_NAME=Blog
APP_WEBSITE_1_RECIPIENTS=you@example.com
APP_WEBSITE_1_TIMEZONE=UTC

# Website 2
APP_WEBSITE_2_SHARE_URL=https://umami.eli.pizza/share/yyyyy
APP_WEBSITE_2_NAME=Shop
APP_WEBSITE_2_RECIPIENTS=sales@example.com,you@example.com
APP_WEBSITE_2_TIMEZONE=America/New_York

# Website 3
APP_WEBSITE_3_BASE_URL=https://umami.eli.pizza
APP_WEBSITE_3_ID=uuid-here
APP_WEBSITE_3_USERNAME=user
APP_WEBSITE_3_PASSWORD=pass
APP_WEBSITE_3_NAME=Marketing Site
APP_WEBSITE_3_RECIPIENTS=marketing@example.com
APP_WEBSITE_3_TIMEZONE=Europe/London
```

## What to Look For

**Successful output:**
```
INFO Starting umami-alerts
INFO Loaded country mappings
INFO Processing website: Blog
INFO Using share URL for authentication
INFO   Extracted: base_url=https://umami.eli.pizza, share_id=xxxxx
INFO Processing complete. 1 succeeded, 0 failed
```

**Error output:**
```
ERROR Website Blog failed: share URL missing /share/ path: invalid-url
ERROR Failed websites: Blog
```

## Switching from Test to Production

Once verified:

In `.env`:
```bash
# Change these:
APP_DRY_RUN=false    # Send actual emails
APP_DEBUG=false      # Reduce log verbosity
```

Or set via environment:
```bash
export APP_DRY_RUN=false
export APP_DEBUG=false
./target/release/umami-alerts
```

## Authentication Methods

### Method 1: Share URL (Recommended)
```bash
APP_WEBSITE_1_SHARE_URL=https://umami.eli.pizza/share/xxxxx
```
- No username/password needed
- Works with any Umami instance
- URL provides both base_url and share_id
- Extracts everything automatically

### Method 2: Share ID + Base URL
```bash
APP_WEBSITE_1_SHARE_ID=xxxxx
APP_WEBSITE_1_BASE_URL=https://umami.eli.pizza
```
- Still passwordless
- Requires specifying base_url separately
- For subpath deployments (e.g., `/umami/share/xxxxx`)

### Method 3: Username/Password
```bash
APP_WEBSITE_1_BASE_URL=https://umami.eli.pizza
APP_WEBSITE_1_ID=website-uuid
APP_WEBSITE_1_USERNAME=user
APP_WEBSITE_1_PASSWORD=pass
```
- Traditional method
- Requires access credentials
- ID is the website UUID from Umami settings

## Common Issues

**Error: "share URL missing /share/ path"**
- Your share URL must contain `/share/`
- Check you copied the full URL from Umami

**Error: "Invalid share URL"**
- URL format is wrong
- Should be: `https://domain/share/xxxxx`

**Error: SMTP connection failed**
- Check SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD
- Verify your SMTP server allows connections from your IP

**No email sent (with dry_run=false)**
- Check SMTP credentials
- Verify recipients email addresses
- Check your SMTP server logs

**.env file not being loaded**
- Make sure .env is in the same directory as you run the command
- Check the file is named `.env` (not `.env.example`)
- Verify file permissions

## Docker Testing with .env

```bash
# Create .env file with your settings
cp .env.example .env
# Edit .env

# Run with Docker (mounts .env)
docker run --rm \
  --env-file .env \
  ghcr.io/thunderbottom/umami-alerts:latest \
  --debug
```