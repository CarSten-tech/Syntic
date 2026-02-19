//! Structured runtime events for cross-platform error and permission reporting.

use std::collections::VecDeque;
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_EVENT_CAPACITY: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoreEventKind {
    Error,
    Permission,
    Telemetry,
}

impl CoreEventKind {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Error => "error",
            Self::Permission => "permission",
            Self::Telemetry => "telemetry",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoreEventSeverity {
    Info,
    Warn,
    Error,
}

impl CoreEventSeverity {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Info => "info",
            Self::Warn => "warn",
            Self::Error => "error",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreEventPayload {
    Error {
        code: String,
        message: String,
    },
    Permission {
        permission: String,
        status: String,
        detail: String,
    },
    Telemetry {
        category: String,
        action: String,
        status: String,
        context_json: String,
        value_ms: Option<u32>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreEvent {
    pub id: u64,
    pub timestamp_ms: u64,
    pub source: String,
    pub kind: CoreEventKind,
    pub severity: CoreEventSeverity,
    pub payload: CoreEventPayload,
}

#[derive(Debug)]
pub struct CoreEventJournal {
    entries: VecDeque<CoreEvent>,
    next_id: u64,
    capacity: usize,
}

impl Default for CoreEventJournal {
    fn default() -> Self {
        Self::with_capacity(DEFAULT_EVENT_CAPACITY)
    }
}

impl CoreEventJournal {
    #[must_use]
    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            entries: VecDeque::new(),
            next_id: 1,
            capacity: capacity.max(1),
        }
    }

    pub fn clear(&mut self) {
        self.entries.clear();
        self.next_id = 1;
    }

    pub fn record_error(&mut self, source: &str, code: &str, message: &str) -> u64 {
        self.push_event(
            source,
            CoreEventKind::Error,
            CoreEventSeverity::Error,
            CoreEventPayload::Error {
                code: code.to_owned(),
                message: message.to_owned(),
            },
        )
    }

    pub fn record_permission(
        &mut self,
        source: &str,
        permission: &str,
        status: &str,
        detail: &str,
    ) -> u64 {
        self.push_event(
            source,
            CoreEventKind::Permission,
            permission_severity(status),
            CoreEventPayload::Permission {
                permission: permission.to_owned(),
                status: status.to_owned(),
                detail: detail.to_owned(),
            },
        )
    }

    pub fn record_telemetry(
        &mut self,
        source: &str,
        category: &str,
        action: &str,
        status: &str,
        context_json: &str,
        value_ms: Option<u32>,
    ) -> u64 {
        self.push_event(
            source,
            CoreEventKind::Telemetry,
            telemetry_severity(status),
            CoreEventPayload::Telemetry {
                category: category.to_owned(),
                action: action.to_owned(),
                status: status.to_owned(),
                context_json: context_json.to_owned(),
                value_ms,
            },
        )
    }

    #[must_use]
    pub fn events_since(&self, last_seen_event_id: u64, limit: usize) -> Vec<CoreEvent> {
        self.entries
            .iter()
            .filter(|event| event.id > last_seen_event_id)
            .take(limit.max(1))
            .cloned()
            .collect()
    }

    #[must_use]
    pub fn events_recent(&self, limit: usize) -> Vec<CoreEvent> {
        let limit = limit.max(1);
        let skip_count = self.entries.len().saturating_sub(limit);
        self.entries.iter().skip(skip_count).cloned().collect()
    }

    fn push_event(
        &mut self,
        source: &str,
        kind: CoreEventKind,
        severity: CoreEventSeverity,
        payload: CoreEventPayload,
    ) -> u64 {
        if self.entries.len() >= self.capacity {
            self.entries.pop_front();
        }

        let event_id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);

        self.entries.push_back(CoreEvent {
            id: event_id,
            timestamp_ms: unix_timestamp_ms(),
            source: source.to_owned(),
            kind,
            severity,
            payload,
        });

        event_id
    }
}

#[must_use]
pub fn permission_severity(status: &str) -> CoreEventSeverity {
    match status {
        "granted" | "authorized" => CoreEventSeverity::Info,
        "error" => CoreEventSeverity::Error,
        _ => CoreEventSeverity::Warn,
    }
}

#[must_use]
pub fn telemetry_severity(status: &str) -> CoreEventSeverity {
    match status {
        "error" | "failed" => CoreEventSeverity::Error,
        "warn" | "degraded" | "fallback" => CoreEventSeverity::Warn,
        _ => CoreEventSeverity::Info,
    }
}

fn unix_timestamp_ms() -> u64 {
    let Ok(now) = SystemTime::now().duration_since(UNIX_EPOCH) else {
        return 0;
    };
    u64::try_from(now.as_millis()).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::{CoreEventJournal, CoreEventPayload, CoreEventSeverity};

    #[test]
    fn permission_denied_records_warn_event() {
        let mut journal = CoreEventJournal::with_capacity(8);
        journal.record_permission("macos.audio", "microphone", "denied", "user denied");

        let events = journal.events_since(0, 8);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].severity, CoreEventSeverity::Warn);

        match &events[0].payload {
            CoreEventPayload::Permission {
                permission, status, ..
            } => {
                assert_eq!(permission, "microphone");
                assert_eq!(status, "denied");
            }
            CoreEventPayload::Error { .. } | CoreEventPayload::Telemetry { .. } => {
                panic!("expected permission payload")
            }
        }
    }

    #[test]
    fn ring_buffer_evicts_oldest_entries() {
        let mut journal = CoreEventJournal::with_capacity(2);

        journal.record_error("core", "e1", "error one");
        journal.record_error("core", "e2", "error two");
        journal.record_error("core", "e3", "error three");

        let events = journal.events_since(0, 10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].id, 2);
        assert_eq!(events[1].id, 3);
    }

    #[test]
    fn clear_resets_journal_and_ids() {
        let mut journal = CoreEventJournal::with_capacity(4);
        journal.record_error("core", "old", "error");
        journal.clear();
        let id = journal.record_error("core", "fresh", "error");

        assert_eq!(id, 1);
        let events = journal.events_since(0, 4);
        assert_eq!(events.len(), 1);
    }

    #[test]
    fn telemetry_event_stores_structured_payload() {
        let mut journal = CoreEventJournal::with_capacity(4);
        journal.record_telemetry(
            "macos.pipeline",
            "e2e",
            "route_selected",
            "ok",
            "{\"provider\":\"local\"}",
            Some(120),
        );

        let events = journal.events_since(0, 4);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].severity, CoreEventSeverity::Info);

        match &events[0].payload {
            CoreEventPayload::Telemetry {
                category,
                action,
                status,
                context_json,
                value_ms,
            } => {
                assert_eq!(category, "e2e");
                assert_eq!(action, "route_selected");
                assert_eq!(status, "ok");
                assert_eq!(context_json, "{\"provider\":\"local\"}");
                assert_eq!(*value_ms, Some(120));
            }
            CoreEventPayload::Error { .. } | CoreEventPayload::Permission { .. } => {
                panic!("expected telemetry payload")
            }
        }
    }
}
