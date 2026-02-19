//! Session history journal for cross-platform runtime consistency.

use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionOutcome {
    Confirmed,
    Cancelled,
    Failed,
}

impl SessionOutcome {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Confirmed => "confirmed",
            Self::Cancelled => "cancelled",
            Self::Failed => "failed",
        }
    }

    #[must_use]
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "confirmed" => Some(Self::Confirmed),
            "cancelled" => Some(Self::Cancelled),
            "failed" => Some(Self::Failed),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionInjectionDisposition {
    Injected,
    ClipboardFallback,
    Failed,
    Unknown,
}

impl SessionInjectionDisposition {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Injected => "injected",
            Self::ClipboardFallback => "clipboard_fallback",
            Self::Failed => "failed",
            Self::Unknown => "unknown",
        }
    }

    #[must_use]
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "injected" => Some(Self::Injected),
            "clipboard_fallback" => Some(Self::ClipboardFallback),
            "failed" => Some(Self::Failed),
            "unknown" => Some(Self::Unknown),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionHistoryRecord {
    pub id: u64,
    pub created_at_ms: u64,
    pub duration_ms: Option<u32>,
    pub locale: String,
    pub route_provider: String,
    pub outcome: SessionOutcome,
    pub transcript: String,
    pub error_code: Option<String>,
    pub injection_disposition: Option<SessionInjectionDisposition>,
    pub undone_at_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionHistoryRecordInput<'a> {
    pub duration_ms: Option<u32>,
    pub locale: &'a str,
    pub route_provider: &'a str,
    pub outcome: SessionOutcome,
    pub transcript: &'a str,
    pub error_code: Option<&'a str>,
    pub injection_disposition: Option<SessionInjectionDisposition>,
}

#[derive(Debug, Clone)]
pub struct SessionHistoryJournal {
    records: Vec<SessionHistoryRecord>,
    next_id: u64,
    max_records: usize,
}

impl Default for SessionHistoryJournal {
    fn default() -> Self {
        Self::new(200)
    }
}

impl SessionHistoryJournal {
    #[must_use]
    pub fn new(max_records: usize) -> Self {
        Self {
            records: Vec::new(),
            next_id: 1,
            max_records: max_records.max(1),
        }
    }

    pub fn clear(&mut self) {
        self.records.clear();
        self.next_id = 1;
    }

    #[must_use]
    pub fn records_since(&self, last_seen_id: u64, limit: usize) -> Vec<SessionHistoryRecord> {
        let normalized_limit = if limit == 0 { 50 } else { limit.min(256) };
        self.records
            .iter()
            .filter(|record| record.id > last_seen_id)
            .take(normalized_limit)
            .cloned()
            .collect()
    }

    #[must_use]
    pub fn records_recent(&self, limit: usize) -> Vec<SessionHistoryRecord> {
        if self.records.is_empty() {
            return Vec::new();
        }
        let normalized_limit = if limit == 0 { 50 } else { limit.min(256) };
        let take_count = normalized_limit.min(self.records.len());
        self.records[self.records.len() - take_count..].to_vec()
    }

    pub fn record(&mut self, input: &SessionHistoryRecordInput<'_>) -> u64 {
        let record_id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);

        self.records.push(SessionHistoryRecord {
            id: record_id,
            created_at_ms: now_ms(),
            duration_ms: input.duration_ms,
            locale: input.locale.to_owned(),
            route_provider: input.route_provider.to_owned(),
            outcome: input.outcome,
            transcript: input.transcript.to_owned(),
            error_code: input.error_code.map(str::to_owned),
            injection_disposition: input.injection_disposition,
            undone_at_ms: None,
        });

        if self.records.len() > self.max_records {
            let remove_count = self.records.len() - self.max_records;
            self.records.drain(0..remove_count);
        }

        record_id
    }

    pub fn mark_last_confirmed_as_undone(&mut self) -> Option<u64> {
        let undone_at_ms = now_ms();
        let record = self.records.iter_mut().rfind(|record| {
            record.outcome == SessionOutcome::Confirmed && record.undone_at_ms.is_none()
        })?;
        record.undone_at_ms = Some(undone_at_ms);
        Some(record.id)
    }
}

fn now_ms() -> u64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => u64::try_from(duration.as_millis()).unwrap_or(u64::MAX),
        Err(_) => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        SessionHistoryJournal, SessionHistoryRecordInput, SessionInjectionDisposition,
        SessionOutcome,
    };

    #[test]
    fn journal_records_and_filters_since_last_id() {
        let mut journal = SessionHistoryJournal::new(10);
        journal.record(&SessionHistoryRecordInput {
            duration_ms: Some(1200),
            locale: "de-DE",
            route_provider: "apple_speech_recognizer",
            outcome: SessionOutcome::Confirmed,
            transcript: "eins",
            error_code: None,
            injection_disposition: Some(SessionInjectionDisposition::Injected),
        });
        let second_id = journal.record(&SessionHistoryRecordInput {
            duration_ms: None,
            locale: "de-DE",
            route_provider: "apple_speech_recognizer",
            outcome: SessionOutcome::Cancelled,
            transcript: "zwei",
            error_code: None,
            injection_disposition: None,
        });

        let records = journal.records_since(1, 10);
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].id, second_id);
        assert_eq!(records[0].transcript, "zwei");
    }

    #[test]
    fn journal_marks_last_confirmed_record_as_undone() {
        let mut journal = SessionHistoryJournal::new(10);
        journal.record(&SessionHistoryRecordInput {
            duration_ms: None,
            locale: "de-DE",
            route_provider: "apple_speech_recognizer",
            outcome: SessionOutcome::Confirmed,
            transcript: "first",
            error_code: None,
            injection_disposition: Some(SessionInjectionDisposition::Injected),
        });
        let target_id = journal.record(&SessionHistoryRecordInput {
            duration_ms: None,
            locale: "de-DE",
            route_provider: "apple_speech_recognizer",
            outcome: SessionOutcome::Confirmed,
            transcript: "second",
            error_code: None,
            injection_disposition: Some(SessionInjectionDisposition::Injected),
        });

        let undone_id = journal.mark_last_confirmed_as_undone();
        assert_eq!(undone_id, Some(target_id));

        let records = journal.records_since(0, 10);
        let updated = records
            .iter()
            .find(|record| record.id == target_id)
            .expect("record not found");
        assert!(updated.undone_at_ms.is_some());
    }

    #[test]
    fn journal_enforces_max_record_limit() {
        let mut journal = SessionHistoryJournal::new(2);
        for index in 0..3 {
            journal.record(&SessionHistoryRecordInput {
                duration_ms: None,
                locale: "de-DE",
                route_provider: "apple_speech_recognizer",
                outcome: SessionOutcome::Confirmed,
                transcript: &format!("record-{index}"),
                error_code: None,
                injection_disposition: None,
            });
        }

        let records = journal.records_since(0, 10);
        assert_eq!(records.len(), 2);
        assert_eq!(records[0].transcript, "record-1");
        assert_eq!(records[1].transcript, "record-2");
    }
}
