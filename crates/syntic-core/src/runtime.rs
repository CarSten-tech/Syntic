//! Core runtime root object.

use crate::dictation::DictationSessionController;
use crate::events::{CoreEvent, CoreEventJournal};

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
pub struct CoreRuntime {
    dictation_session: DictationSessionController,
    core_events: CoreEventJournal,
}

impl CoreRuntime {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn health_snapshot(&self) -> HealthSnapshot {
        HealthSnapshot {
            service_name: "syntic-core",
            version: CORE_VERSION,
            status: "ready",
        }
    }

    #[must_use]
    pub const fn dictation_session(&self) -> &DictationSessionController {
        &self.dictation_session
    }

    #[must_use]
    pub fn dictation_session_mut(&mut self) -> &mut DictationSessionController {
        &mut self.dictation_session
    }

    pub fn record_error_event(&mut self, source: &str, code: &str, message: &str) {
        self.core_events.record_error(source, code, message);
    }

    pub fn record_permission_event(
        &mut self,
        source: &str,
        permission: &str,
        status: &str,
        detail: &str,
    ) {
        self.core_events
            .record_permission(source, permission, status, detail);
    }

    pub fn clear_core_events(&mut self) {
        self.core_events.clear();
    }

    #[must_use]
    pub fn core_events_since(&self, last_seen_event_id: u64, limit: usize) -> Vec<CoreEvent> {
        self.core_events.events_since(last_seen_event_id, limit)
    }

    #[must_use]
    pub fn core_events_recent(&self, limit: usize) -> Vec<CoreEvent> {
        self.core_events.events_recent(limit)
    }
}

#[cfg(test)]
mod tests {
    use super::{CORE_VERSION, CoreRuntime};
    use crate::events::CoreEventPayload;

    #[test]
    fn health_snapshot_exposes_core_version() {
        let runtime = CoreRuntime::new();
        let snapshot = runtime.health_snapshot();

        assert_eq!(snapshot.version, CORE_VERSION);
        assert_eq!(snapshot.status, "ready");
    }

    #[test]
    fn runtime_exposes_error_and_permission_events() {
        let mut runtime = CoreRuntime::new();
        runtime.record_error_event("core.test", "audio_failed", "microphone blocked");
        runtime.record_permission_event("core.test", "microphone", "denied", "user denied");

        let events = runtime.core_events_since(0, 10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].source, "core.test");
        assert_eq!(events[1].source, "core.test");

        match &events[0].payload {
            CoreEventPayload::Error { code, .. } => assert_eq!(code, "audio_failed"),
            CoreEventPayload::Permission { .. } => panic!("expected error payload"),
        }
    }
}
