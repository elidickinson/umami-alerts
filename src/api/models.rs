use serde::{Deserialize, Deserializer, Serialize};

#[derive(Debug, Clone, Serialize)]
pub struct Stats {
    pub pageviews: MetricValue,
    pub visitors: MetricValue,
    pub visits: MetricValue,
    pub bounces: MetricValue,
    #[serde(rename = "totaltime")]
    pub total_time: MetricValue,
}

// The Umami API returns stats as flat values with a separate comparison object:
//   {"pageviews":9,"visitors":9,...,"comparison":{"pageviews":8,"visitors":6,...}}
// We deserialize into our MetricValue {value, prev} format.
impl<'de> Deserialize<'de> for Stats {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct RawStats {
            pageviews: f64,
            visitors: f64,
            visits: f64,
            bounces: f64,
            totaltime: f64,
            #[serde(default)]
            comparison: Option<RawComparison>,
        }

        #[derive(Deserialize)]
        struct RawComparison {
            pageviews: f64,
            visitors: f64,
            visits: f64,
            bounces: f64,
            totaltime: f64,
        }

        let raw = RawStats::deserialize(deserializer)?;
        let comp = raw.comparison.unwrap_or(RawComparison {
            pageviews: 0.0,
            visitors: 0.0,
            visits: 0.0,
            bounces: 0.0,
            totaltime: 0.0,
        });

        Ok(Stats {
            pageviews: MetricValue { value: raw.pageviews, prev: comp.pageviews },
            visitors: MetricValue { value: raw.visitors, prev: comp.visitors },
            visits: MetricValue { value: raw.visits, prev: comp.visits },
            bounces: MetricValue { value: raw.bounces, prev: comp.bounces },
            total_time: MetricValue { value: raw.totaltime, prev: comp.totaltime },
        })
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct MetricValue {
    pub value: f64,
    pub prev: f64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Metric {
    pub x: String,
    pub y: f64,
}

#[derive(Debug, Deserialize)]
pub(crate) struct AuthResponse {
    pub token: String,
}

#[derive(Debug, Deserialize)]
pub struct ShareResponse {
    pub token: String,
    #[serde(rename = "websiteId")]
    pub website_id: String,
}
