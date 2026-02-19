//! Domain event and tool-runtime signal chain for cross-module orchestration.

use std::collections::VecDeque;
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_DOMAIN_CAPACITY: usize = 256;
const DEFAULT_TOOL_SIGNAL_CAPACITY: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DomainEventName {
    DictationReviewCancelled,
}

impl DomainEventName {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::DictationReviewCancelled => "dictation_review_cancelled",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DomainEventPayload {
    DictationReviewCancelled {
        source: String,
        phase_before: String,
        review_transcript_length: u32,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DomainEvent {
    pub id: u64,
    pub timestamp_ms: u64,
    pub name: DomainEventName,
    pub payload: DomainEventPayload,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToolRuntimeAction {
    AbortPendingToolInvocations,
}

impl ToolRuntimeAction {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::AbortPendingToolInvocations => "abort_pending_tool_invocations",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolRuntimeSignal {
    pub id: u64,
    pub timestamp_ms: u64,
    pub action: ToolRuntimeAction,
    pub reason: String,
    pub origin_domain_event_id: u64,
}

#[derive(Debug)]
pub struct DomainEventBus {
    domain_events: VecDeque<DomainEvent>,
    tool_runtime_signals: VecDeque<ToolRuntimeSignal>,
    next_domain_event_id: u64,
    next_tool_signal_id: u64,
    domain_capacity: usize,
    tool_signal_capacity: usize,
}

impl Default for DomainEventBus {
    fn default() -> Self {
        Self::with_capacity(DEFAULT_DOMAIN_CAPACITY, DEFAULT_TOOL_SIGNAL_CAPACITY)
    }
}

impl DomainEventBus {
    #[must_use]
    pub fn with_capacity(domain_capacity: usize, tool_signal_capacity: usize) -> Self {
        Self {
            domain_events: VecDeque::new(),
            tool_runtime_signals: VecDeque::new(),
            next_domain_event_id: 1,
            next_tool_signal_id: 1,
            domain_capacity: domain_capacity.max(1),
            tool_signal_capacity: tool_signal_capacity.max(1),
        }
    }

    pub fn clear(&mut self) {
        self.domain_events.clear();
        self.tool_runtime_signals.clear();
        self.next_domain_event_id = 1;
        self.next_tool_signal_id = 1;
    }

    pub fn record_dictation_review_cancelled(
        &mut self,
        source: &str,
        phase_before: &str,
        review_transcript_length: u32,
    ) -> u64 {
        let domain_event_id = self.push_domain_event(
            DomainEventName::DictationReviewCancelled,
            DomainEventPayload::DictationReviewCancelled {
                source: source.to_owned(),
                phase_before: phase_before.to_owned(),
                review_transcript_length,
            },
        );

        self.push_tool_runtime_signal(
            ToolRuntimeAction::AbortPendingToolInvocations,
            "dictation_review_cancelled",
            domain_event_id,
        );

        domain_event_id
    }

    #[must_use]
    pub fn domain_events_since(&self, last_seen_event_id: u64, limit: usize) -> Vec<DomainEvent> {
        self.domain_events
            .iter()
            .filter(|event| event.id > last_seen_event_id)
            .take(limit.max(1))
            .cloned()
            .collect()
    }

    #[must_use]
    pub fn tool_runtime_signals_since(
        &self,
        last_seen_signal_id: u64,
        limit: usize,
    ) -> Vec<ToolRuntimeSignal> {
        self.tool_runtime_signals
            .iter()
            .filter(|signal| signal.id > last_seen_signal_id)
            .take(limit.max(1))
            .cloned()
            .collect()
    }

    fn push_domain_event(&mut self, name: DomainEventName, payload: DomainEventPayload) -> u64 {
        if self.domain_events.len() >= self.domain_capacity {
            self.domain_events.pop_front();
        }

        let event_id = self.next_domain_event_id;
        self.next_domain_event_id = self.next_domain_event_id.saturating_add(1);
        self.domain_events.push_back(DomainEvent {
            id: event_id,
            timestamp_ms: unix_timestamp_ms(),
            name,
            payload,
        });

        event_id
    }

    fn push_tool_runtime_signal(
        &mut self,
        action: ToolRuntimeAction,
        reason: &str,
        origin_domain_event_id: u64,
    ) -> u64 {
        if self.tool_runtime_signals.len() >= self.tool_signal_capacity {
            self.tool_runtime_signals.pop_front();
        }

        let signal_id = self.next_tool_signal_id;
        self.next_tool_signal_id = self.next_tool_signal_id.saturating_add(1);
        self.tool_runtime_signals.push_back(ToolRuntimeSignal {
            id: signal_id,
            timestamp_ms: unix_timestamp_ms(),
            action,
            reason: reason.to_owned(),
            origin_domain_event_id,
        });

        signal_id
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
    use super::{DomainEventBus, DomainEventPayload, ToolRuntimeAction};

    #[test]
    fn review_cancel_event_enqueues_tool_runtime_signal() {
        let mut bus = DomainEventBus::with_capacity(8, 8);
        let event_id = bus.record_dictation_review_cancelled("ffi.dictation", "reviewing", 18);

        let domain_events = bus.domain_events_since(0, 8);
        assert_eq!(domain_events.len(), 1);
        assert_eq!(domain_events[0].id, event_id);

        match &domain_events[0].payload {
            DomainEventPayload::DictationReviewCancelled {
                source,
                phase_before,
                review_transcript_length,
            } => {
                assert_eq!(source, "ffi.dictation");
                assert_eq!(phase_before, "reviewing");
                assert_eq!(*review_transcript_length, 18);
            }
        }

        let signals = bus.tool_runtime_signals_since(0, 8);
        assert_eq!(signals.len(), 1);
        assert_eq!(signals[0].origin_domain_event_id, event_id);
        assert_eq!(
            signals[0].action,
            ToolRuntimeAction::AbortPendingToolInvocations
        );
    }

    #[test]
    fn clear_resets_event_and_signal_ids() {
        let mut bus = DomainEventBus::with_capacity(4, 4);
        bus.record_dictation_review_cancelled("ffi.dictation", "reviewing", 12);
        bus.clear();

        let event_id = bus.record_dictation_review_cancelled("ffi.dictation", "reviewing", 2);
        assert_eq!(event_id, 1);

        let signals = bus.tool_runtime_signals_since(0, 4);
        assert_eq!(signals.len(), 1);
        assert_eq!(signals[0].id, 1);
    }
}
