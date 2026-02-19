//! Platform-independent Syntic core runtime primitives.

/// Semantic version of the current core runtime.
pub const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Lightweight health snapshot that can be projected into UI or logs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HealthSnapshot {
    pub service_name: &'static str,
    pub version: &'static str,
    pub status: &'static str,
}

/// Bootstrapped runtime entry point.
#[derive(Debug, Default)]
pub struct CoreRuntime;

impl CoreRuntime {
    #[must_use]
    pub const fn new() -> Self {
        Self
    }

    #[must_use]
    pub fn health_snapshot(&self) -> HealthSnapshot {
        HealthSnapshot {
            service_name: "syntic-core",
            version: CORE_VERSION,
            status: "ready",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{CORE_VERSION, CoreRuntime};

    #[test]
    fn health_snapshot_exposes_core_version() {
        let runtime = CoreRuntime::new();
        let snapshot = runtime.health_snapshot();

        assert_eq!(snapshot.version, CORE_VERSION);
        assert_eq!(snapshot.status, "ready");
    }
}
