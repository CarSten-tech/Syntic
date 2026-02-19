//! Core runtime root object.

use crate::dictation::DictationSessionController;
use crate::domain::{DomainEvent, DomainEventBus, ToolRuntimeSignal};
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
    domain_event_bus: DomainEventBus,
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

    pub fn record_telemetry_event(
        &mut self,
        source: &str,
        category: &str,
        action: &str,
        status: &str,
        context_json: &str,
        value_ms: Option<u32>,
    ) {
        self.core_events
            .record_telemetry(source, category, action, status, context_json, value_ms);
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

    pub fn record_dictation_review_cancelled_domain_event(
        &mut self,
        source: &str,
        phase_before: &str,
        review_transcript_length: u32,
    ) {
        self.domain_event_bus.record_dictation_review_cancelled(
            source,
            phase_before,
            review_transcript_length,
        );
    }

    pub fn record_dictation_review_confirmed_domain_event(
        &mut self,
        source: &str,
        phase_before: &str,
        review_transcript_length: u32,
    ) {
        self.domain_event_bus.record_dictation_review_confirmed(
            source,
            phase_before,
            review_transcript_length,
        );
    }

    pub fn clear_domain_events(&mut self) {
        self.domain_event_bus.clear();
    }

    #[must_use]
    pub fn domain_events_since(&self, last_seen_event_id: u64, limit: usize) -> Vec<DomainEvent> {
        self.domain_event_bus
            .domain_events_since(last_seen_event_id, limit)
    }

    #[must_use]
    pub fn tool_runtime_signals_since(
        &self,
        last_seen_signal_id: u64,
        limit: usize,
    ) -> Vec<ToolRuntimeSignal> {
        self.domain_event_bus
            .tool_runtime_signals_since(last_seen_signal_id, limit)
    }
}

#[cfg(test)]
mod tests {
    use super::{CORE_VERSION, CoreRuntime};
    use crate::domain::{DomainEventPayload, ToolRuntimeAction};
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
            CoreEventPayload::Permission { .. } | CoreEventPayload::Telemetry { .. } => {
                panic!("expected error payload")
            }
        }
    }

    #[test]
    fn runtime_exposes_telemetry_events() {
        let mut runtime = CoreRuntime::new();
        runtime.record_telemetry_event(
            "core.test",
            "e2e",
            "phase_changed",
            "ok",
            "{\"phase\":\"listening\"}",
            Some(55),
        );

        let events = runtime.core_events_since(0, 10);
        assert_eq!(events.len(), 1);

        match &events[0].payload {
            CoreEventPayload::Telemetry {
                category, action, ..
            } => {
                assert_eq!(category, "e2e");
                assert_eq!(action, "phase_changed");
            }
            CoreEventPayload::Error { .. } | CoreEventPayload::Permission { .. } => {
                panic!("expected telemetry payload")
            }
        }
    }

    #[test]
    fn runtime_exposes_review_cancel_domain_event_and_tool_signal() {
        let mut runtime = CoreRuntime::new();
        runtime.record_dictation_review_cancelled_domain_event("ffi.dictation", "reviewing", 32);

        let domain_events = runtime.domain_events_since(0, 8);
        assert_eq!(domain_events.len(), 1);
        match &domain_events[0].payload {
            DomainEventPayload::DictationReviewCancelled {
                phase_before,
                review_transcript_length,
                ..
            } => {
                assert_eq!(phase_before, "reviewing");
                assert_eq!(*review_transcript_length, 32);
            }
            DomainEventPayload::DictationReviewConfirmed { .. } => {
                panic!("expected cancelled payload")
            }
        }

        let tool_signals = runtime.tool_runtime_signals_since(0, 8);
        assert_eq!(tool_signals.len(), 1);
        assert_eq!(tool_signals[0].origin_domain_event_id, domain_events[0].id);
        assert_eq!(
            tool_signals[0].action,
            ToolRuntimeAction::AbortPendingToolInvocations
        );
    }

    #[test]
    fn runtime_exposes_review_confirm_domain_event_and_tool_signal() {
        let mut runtime = CoreRuntime::new();
        runtime.record_dictation_review_confirmed_domain_event("ffi.dictation", "reviewing", 14);

        let domain_events = runtime.domain_events_since(0, 8);
        assert_eq!(domain_events.len(), 1);
        match &domain_events[0].payload {
            DomainEventPayload::DictationReviewConfirmed {
                phase_before,
                review_transcript_length,
                ..
            } => {
                assert_eq!(phase_before, "reviewing");
                assert_eq!(*review_transcript_length, 14);
            }
            DomainEventPayload::DictationReviewCancelled { .. } => {
                panic!("expected confirmed payload")
            }
        }

        let tool_signals = runtime.tool_runtime_signals_since(0, 8);
        assert_eq!(tool_signals.len(), 1);
        assert_eq!(tool_signals[0].origin_domain_event_id, domain_events[0].id);
        assert_eq!(
            tool_signals[0].action,
            ToolRuntimeAction::CommitPendingToolInvocations
        );
    }
}
