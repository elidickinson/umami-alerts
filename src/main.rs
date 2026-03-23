use clap::Parser;
use futures::stream::{self, StreamExt};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Semaphore;
use tracing::{debug, error, info};

// Load .env file if it exists
let _ = dotenvy::dotenv();

mod api;
mod config;
mod error;
mod report;

use crate::{
    api::client::AuthMode,
    config::{validation::validate_config, Config, WebsiteConfig},
    error::{AppError, Result},
    report::generator::ReportGenerator,
};

#[derive(Clone)]
struct AppState {
    config: Arc<Config>,
    report_generator: Arc<ReportGenerator>,
    semaphore: Arc<Semaphore>,
}

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Path to the configuration file
    #[arg(short, long, default_value = "config.toml")]
    config: PathBuf,
    /// Enable debug mode
    #[arg(short, long, default_value = "false")]
    debug: bool,
}

#[tokio::main]
async fn main() {
    let args = Args::parse();

    // Initialize logging with full error details
    let env_filter = tracing_subscriber::EnvFilter::builder()
        .with_default_directive(
            if args.debug {
                tracing::Level::DEBUG
            } else {
                tracing::Level::INFO
            }
            .into(),
        )
        .from_env_lossy();

    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_file(true)
        .with_line_number(true)
        .with_thread_ids(true)
        .with_target(false)
        .pretty()
        .with_thread_names(true)
        .with_level(true)
        .init();

    // Run the application and log any errors
    if let Err(e) = run_app(args).await {
        // Log the full error hierarchy
        error!("Application error: {}", e);
        if let Some(source) = std::error::Error::source(&e) {
            error!("Caused by: {}", source);
            let mut src = source.source();
            while let Some(next_src) = src {
                error!("  caused by: {}", next_src);
                src = next_src.source();
            }
        }

        std::process::exit(1);
    }
}

async fn run_app(args: Args) -> Result<()> {
    // Load configuration - try config file first, then environment variables
    let config = if args.config.exists() {
        info!("Loading configuration from: {}", args.config.display());
        Config::load(&args.config).await?
    } else if let Some(env_config) = config::env::load_from_env() {
        env_config
    } else {
        error!("Config file not found: {}", args.config.display());
        error!("");
        error!("To get started, use one of these options:");
        error!("  1. Copy the sample config: cp config.sample.toml config.toml");
        error!("  2. Create a .env file: cp .env.example .env");
        error!("     Then set your environment variables in .env");
        error!("");
        error!("Required environment variables:");
        error!("  - SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM");
        error!("  - APP_WEBSITE_1_NAME, APP_WEBSITE_1_RECIPIENTS");
        error!("     (plus either APP_WEBSITE_1_SHARE_URL or APP_WEBSITE_1_BASE_URL + credentials)");
        error!("");
        error!("See .env.example for all available options.");
        return Err(format!("Config file not found: {}", args.config.display()).into());
    };

    validate_config(&config)
        .map_err(|e| AppError::api(format!("Config validation failed: {e}")))?;
    let max_concurrent_jobs = config.app.max_concurrent_jobs;

    // Update log level based on config
    if config.app.debug {
        tracing::info!("Debug mode enabled - all logs will be shown");
    }

    info!("Starting umami-alerts");
    debug!("Debug mode enabled");
    debug!("Report type: {:?}", config.app.report_type);

    config::load_country_map().await?;
    info!("Loaded country mappings");

    // Initialize template engine
    let mut handlebars = handlebars::Handlebars::new();
    handlebars.register_template_string(
        "email",
        include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/templates/email.html")),
    )?;
    handlebars.register_helper("formatNumber", Box::new(report::helpers::format_number));
    handlebars.register_helper("percentage", Box::new(report::helpers::percentage));
    handlebars.register_helper("formatFloat", Box::new(report::helpers::format_float));
    handlebars.set_strict_mode(false);
    handlebars::handlebars_helper!(sub: |x:f64, y:f64| x - y);
    handlebars.register_helper("sub", Box::new(sub));
    let handlebars = Arc::new(handlebars);

    // Create application state
    let state = AppState {
        config: Arc::new(config),
        report_generator: Arc::new(ReportGenerator::new(handlebars)),
        semaphore: Arc::new(Semaphore::new(max_concurrent_jobs)),
    };

    // Process all enabled websites concurrently
    let results = stream::iter(state.config.enabled_websites())
        .map(|(name, website)| {
            let state = state.clone();
            async move {
                let _permit = state.semaphore.acquire().await.unwrap();
                match process_website(&state, name, website).await {
                    Ok(_) => Ok(name.to_string()),
                    Err(e) => {
                        error!("Website {} failed: {} (chain: {:?})", name, e, e);
                        Err((name.to_string(), e))
                    }
                }
            }
        })
        .buffer_unordered(max_concurrent_jobs)
        .collect::<Vec<_>>()
        .await;

    // Report results
    let (successes, failures): (Vec<_>, Vec<_>) = results.into_iter().partition(|r| r.is_ok());

    info!(
        "Processing complete. {} succeeded, {} failed",
        successes.len(),
        failures.len()
    );

    if !failures.is_empty() {
        let failed_sites: Vec<_> = failures
            .iter()
            .map(|r| r.as_ref().unwrap_err().0.clone())
            .collect();
        error!("Failed websites: {}", failed_sites.join(", "));
        
        // Log full error details for each failure
        for failure in &failures {
            let (site, err) = failure.as_ref().unwrap_err();
            error!("[{}]: Error: {}", site, err);
            if let Some(source) = std::error::Error::source(err) {
                error!("[{}]: Caused by: {}", site, source);
                let mut src = source.source();
                while let Some(next_src) = src {
                    error!("[{}]:   caused by: {}", site, next_src);
                    src = next_src.source();
                }
            }
        }
        
        return Err(AppError::task(format!(
            "Failed to process {} websites",
            failures.len()
        )));
    }

    Ok(())
}

async fn process_website(state: &AppState, site_name: &str, website: &WebsiteConfig) -> Result<()> {
    info!("Processing website: {}", site_name);

    // Resolve effective auth parameters
    let effective_share_url = website.share_url.as_deref().filter(|s| !s.is_empty());
    let effective_share_id = website.share_id.as_deref().filter(|s| !s.is_empty());

    // Authenticate and get website_id
    let (client, token, website_id) = if let Some(share_url) = effective_share_url {
        info!("Using share URL for authentication");

        // Parse share URL to extract base_url and share_id
        let parsed = url::Url::parse(share_url)
            .map_err(|e| AppError::Config(format!("Invalid share URL: {e}")))?;

        // Get path segments and find the share ID
        let path_segments: Vec<&str> = parsed.path_segments()
            .map(|s| s.collect())
            .unwrap_or_default();

        let share_idx = path_segments.iter().position(|&s| s == "share")
            .ok_or_else(|| AppError::Config("share URL missing /share/ path".to_string()))?;

        let share_id = path_segments.get(share_idx + 1)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| AppError::Config("share URL missing share ID after /share/".to_string()))?;

        // Reconstruct base URL without /share/xxxxx
        let path_prefix = if share_idx > 0 {
            format!("/{}", path_segments[..share_idx].join("/"))
        } else {
            String::new()
        };
        let base_url = format!(
            "{}://{}{}",
            parsed.scheme(),
            parsed.authority(),
            path_prefix
        );

        info!("  Extracted: base_url={}", base_url);

        let client = crate::api::UmamiClient::new(base_url)?;
        let share = client.authenticate_with_share(share_id).await?;
        (client, share.token, share.website_id)
    } else if let Some(share_id) = effective_share_id {
        info!("Using Share ID for authentication");
        let client = crate::api::UmamiClient::new(website.base_url.clone())?;
        let share = client.authenticate_with_share(share_id).await?;
        (client, share.token, share.website_id)
    } else {
        info!("Using username/password for authentication");
        let client = crate::api::UmamiClient::new(website.base_url.clone())?;
        let token = client
            .authenticate(&website.username, &website.password)
            .await?;
        (client, token, website.id.clone())
    };

    // Determine auth mode
    let auth_mode = if effective_share_url.is_some() || effective_share_id.is_some() {
        AuthMode::Share
    } else {
        AuthMode::Bearer
    };

    state
        .report_generator
        .generate_and_send(
            &client,
            &state.config.app.dry_run,
            website,
            &website_id,
            &state.config.app.report_type,
            &state.config.smtp,
            &token,
            auth_mode,
        )
        .await?;

    Ok(())
}
