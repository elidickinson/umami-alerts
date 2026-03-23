use std::collections::HashMap;

use crate::config::models::{Config, WebsiteConfig};
use std::env;

/// Load configuration from environment variables.
/// Returns None if no environment variables are set.
pub fn load_from_env() -> Option<Config> {
    // Check if we have some SMTP config but not all - warn the user
    let has_partial_smtp = [
        env::var("SMTP_HOST").is_ok(),
        env::var("SMTP_PORT").is_ok(),
        env::var("SMTP_USERNAME").is_ok(),
        env::var("SMTP_PASSWORD").is_ok(),
        env::var("SMTP_FROM").is_ok(),
    ]
    .iter()
    .filter(|&&x| x)
    .count();

    let smtp_host = env::var("SMTP_HOST").ok()?;
    let smtp_port = env::var("SMTP_PORT").ok()?;
    let smtp_username = env::var("SMTP_USERNAME").ok()?;
    let smtp_password = env::var("SMTP_PASSWORD").ok()?;
    let smtp_from = env::var("SMTP_FROM").ok()?;

    tracing::info!("Loading configuration from environment variables");

    let smtp_port_parsed = smtp_port.parse();
    if smtp_port_parsed.is_err() {
        tracing::warn!(
            "Invalid SMTP_PORT value '{}', using default 587",
            smtp_port
        );
    }

    let config = Config {
        smtp: crate::config::models::SmtpConfig {
            host: smtp_host,
            port: smtp_port_parsed.unwrap_or(587),
            username: smtp_username,
            password: smtp_password,
            from: smtp_from,
            tls: parse_bool_env("SMTP_TLS", true),
            timeout_seconds: 30,
            skip_verify: parse_bool_env("SMTP_SKIP_TLS_VERIFY", false),
        },
        websites: load_websites_from_env(),
        app: crate::config::models::AppConfig {
            debug: parse_bool_env("APP_DEBUG", false),
            dry_run: parse_bool_env("APP_DRY_RUN", false),
            max_concurrent_jobs: parse_usize_env("APP_MAX_CONCURRENT_JOBS", 4),
            report_type: parse_report_type_env("APP_REPORT_TYPE", crate::config::models::ReportType::Daily),
        },
    };

    Some(config)
}

/// Load all websites from environment variables.
/// Reads APP_WEBSITE_1_*, APP_WEBSITE_2_*, etc.
fn load_websites_from_env() -> HashMap<String, WebsiteConfig> {
    let mut websites = HashMap::new();
    let mut i = 1;

    loop {
        let prefix = format!("APP_WEBSITE_{}_", i);

        let name = match env::var(format!("{}NAME", prefix)) {
            Ok(n) if !n.is_empty() => n,
            _ => break,
        };

        let disabled = parse_bool_env(&format!("{}DISABLED", prefix), false);
        if disabled {
            tracing::info!("Skipping disabled website: {} (APP_WEBSITE_{})", name, i);
            i += 1;
            continue;
        }

        let share_url = env::var(&format!("{}SHARE_URL", prefix)).ok();
        let share_id = env::var(&format!("{}SHARE_ID", prefix)).ok();
        let base_url = env::var(&format!("{}BASE_URL", prefix)).ok();
        let id = env::var(&format!("{}ID", prefix)).ok();
        let username = env::var(&format!("{}USERNAME", prefix)).ok();
        let password = env::var(&format!("{}PASSWORD", prefix)).ok();
        let timezone = env::var(&format!("{}TIMEZONE", prefix))
            .ok()
            .filter(|t| !t.is_empty())
            .unwrap_or_else(|| "UTC".to_string());

        let recipients = match env::var(&format!("{}RECIPIENTS", prefix)) {
            Ok(r) if !r.is_empty() => r
                .split(',')
                .map(|s| s.trim().to_string())
                .collect(),
            _ => {
                tracing::warn!(
                    "Website {} ({}) missing required RECIPIENTS field, skipping",
                    i,
                    name
                );
                i += 1;
                continue;
            }
        };

        let key = format!("website_{}", i);
        websites.insert(
            key.clone(),
            WebsiteConfig {
                id: id.unwrap_or_default(),
                name,
                base_url: base_url.unwrap_or_default(),
                username: username.unwrap_or_default(),
                password: password.unwrap_or_default(),
                share_id: share_id.filter(|s| !s.is_empty()),
                share_url: share_url.filter(|s| !s.is_empty()),
                recipients,
                timezone,
                disabled: false,
            },
        );

        tracing::info!("Loaded website from environment: {}", key);
        i += 1;
    }

    websites
}

fn parse_bool_env(key: &str, default: bool) -> bool {
    match env::var(key) {
        Ok(v) => {
            let v = v.to_lowercase();
            matches!(v.as_str(), "true" | "1" | "yes" | "on")
        }
        Err(_) => default,
    }
}

fn parse_usize_env(key: &str, default: usize) -> usize {
    match env::var(key) {
        Ok(v) => v.parse().unwrap_or(default),
        Err(_) => default,
    }
}

fn parse_report_type_env(
    key: &str,
    default: crate::config::models::ReportType,
) -> crate::config::models::ReportType {
    match env::var(key) {
        Ok(v) => match v.to_lowercase().as_str() {
            "daily" => crate::config::models::ReportType::Daily,
            "weekly" => crate::config::models::ReportType::Weekly,
            _ => default,
        },
        Err(_) => default,
    }
}