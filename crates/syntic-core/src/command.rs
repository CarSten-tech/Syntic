//! Command mode fallback classification and safety-gate logic.

/// Supported command intent classes for the MVP fallback classifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandIntentKind {
    Unknown,
    SetTimer,
    SaveNote,
    MoveFile,
    RenameFile,
}

impl CommandIntentKind {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::SetTimer => "set_timer",
            Self::SaveNote => "save_note",
            Self::MoveFile => "move_file",
            Self::RenameFile => "rename_file",
        }
    }
}

/// Classifier output consumed by command orchestration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandIntent {
    pub kind: CommandIntentKind,
    pub summary: String,
    pub confidence_percent: u8,
    pub requires_confirmation: bool,
    pub arguments: CommandIntentArguments,
}

/// Optional structured arguments extracted from utterance.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CommandIntentArguments {
    pub move_destination: Option<String>,
    pub rename_target: Option<String>,
    pub timer_duration: Option<String>,
}

impl CommandIntent {
    #[must_use]
    pub fn unknown() -> Self {
        Self {
            kind: CommandIntentKind::Unknown,
            summary: "Kein unterstützter Intent erkannt".to_owned(),
            confidence_percent: 0,
            requires_confirmation: false,
            arguments: CommandIntentArguments::default(),
        }
    }
}

/// Safety-gate decision categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SafetyDecisionKind {
    Allow,
    RequireConfirmation,
    Reject,
}

impl SafetyDecisionKind {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Allow => "allow",
            Self::RequireConfirmation => "require_confirmation",
            Self::Reject => "reject",
        }
    }
}

/// Decision payload returned by safety gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CommandSafetyDecision {
    pub decision: SafetyDecisionKind,
    pub destructive: bool,
    pub reason: &'static str,
}

/// Lightweight DE/EN fallback classifier for known MVP intents.
#[must_use]
pub fn fallback_classify(utterance: &str) -> CommandIntent {
    let normalized = utterance.trim().to_lowercase();
    if normalized.is_empty() {
        return CommandIntent::unknown();
    }

    if matches_any_token(&normalized, &["timer", "remind", "erinnere", "countdown"]) {
        let summary = extract_timer_summary(utterance);
        return CommandIntent {
            kind: CommandIntentKind::SetTimer,
            summary,
            confidence_percent: 68,
            requires_confirmation: true,
            arguments: CommandIntentArguments {
                move_destination: None,
                rename_target: None,
                timer_duration: extract_timer_duration_token(utterance),
            },
        };
    }

    if matches_any_token(&normalized, &["notiz", "note", "merk", "remember this"]) {
        return CommandIntent {
            kind: CommandIntentKind::SaveNote,
            summary: "Notiz speichern".to_owned(),
            confidence_percent: 63,
            requires_confirmation: true,
            arguments: CommandIntentArguments::default(),
        };
    }

    if matches_any_token(
        &normalized,
        &["verschieb", "move file", "move", "in den ordner"],
    ) {
        return CommandIntent {
            kind: CommandIntentKind::MoveFile,
            summary: "Datei(en) verschieben".to_owned(),
            confidence_percent: 58,
            requires_confirmation: true,
            arguments: CommandIntentArguments {
                move_destination: extract_move_destination(utterance),
                rename_target: None,
                timer_duration: None,
            },
        };
    }

    if matches_any_token(
        &normalized,
        &["rename", "umbenennen", "new name", "neuer name"],
    ) {
        return CommandIntent {
            kind: CommandIntentKind::RenameFile,
            summary: "Datei/Ordner umbenennen".to_owned(),
            confidence_percent: 58,
            requires_confirmation: true,
            arguments: CommandIntentArguments {
                move_destination: None,
                rename_target: extract_rename_target(utterance),
                timer_duration: None,
            },
        };
    }

    CommandIntent::unknown()
}

/// Applies a conservative safety policy to a classified intent.
#[must_use]
pub fn evaluate_safety(intent: &CommandIntent) -> CommandSafetyDecision {
    match intent.kind {
        CommandIntentKind::Unknown => CommandSafetyDecision {
            decision: SafetyDecisionKind::Reject,
            destructive: false,
            reason: "unknown_intent",
        },
        CommandIntentKind::MoveFile | CommandIntentKind::RenameFile => CommandSafetyDecision {
            decision: SafetyDecisionKind::RequireConfirmation,
            destructive: true,
            reason: "destructive_file_operation",
        },
        CommandIntentKind::SetTimer | CommandIntentKind::SaveNote => CommandSafetyDecision {
            decision: SafetyDecisionKind::RequireConfirmation,
            destructive: false,
            reason: "explicit_user_confirmation_required",
        },
    }
}

fn matches_any_token(normalized: &str, tokens: &[&str]) -> bool {
    tokens.iter().any(|token| normalized.contains(token))
}

fn extract_timer_summary(utterance: &str) -> String {
    let normalized = utterance.trim();
    if let Some(duration_token) = normalized.split_whitespace().find(|token| {
        token.chars().any(|ch| ch.is_ascii_digit())
            && token.chars().any(|ch| ch.is_ascii_alphabetic())
    }) {
        return format!("Timer setzen: {duration_token}");
    }

    if let Some(number_token) = normalized
        .split_whitespace()
        .find(|token| token.chars().all(|ch| ch.is_ascii_digit()))
    {
        return format!("Timer setzen: {number_token} min");
    }

    "Timer setzen".to_owned()
}

fn extract_timer_duration_token(utterance: &str) -> Option<String> {
    let normalized = utterance.trim().to_lowercase();
    if normalized.is_empty() {
        return None;
    }

    if let Some(duration_token) = normalized.split_whitespace().find(|token| {
        token.chars().any(|ch| ch.is_ascii_digit())
            && token.chars().any(|ch| ch.is_ascii_alphabetic())
    }) {
        return Some(duration_token.to_owned());
    }

    normalized
        .split_whitespace()
        .find(|token| token.chars().all(|ch| ch.is_ascii_digit()))
        .map(|token| format!("{token}min"))
}

fn extract_move_destination(utterance: &str) -> Option<String> {
    let normalized = utterance.trim().to_lowercase();
    if normalized.is_empty() {
        return None;
    }

    if let Some(value) = extract_tail_after_markers(&normalized, &[" to ", " nach "]) {
        return sanitize_argument_token(&value);
    }

    if normalized.contains("desktop") {
        return Some("desktop".to_owned());
    }
    if normalized.contains("documents") || normalized.contains("dokumente") {
        return Some("documents".to_owned());
    }
    if normalized.contains("downloads") {
        return Some("downloads".to_owned());
    }
    None
}

fn extract_rename_target(utterance: &str) -> Option<String> {
    let normalized = utterance.trim().to_lowercase();
    if normalized.is_empty() {
        return None;
    }

    if let Some(value) = extract_tail_after_markers(
        &normalized,
        &[" new name ", " neuer name ", " to ", " zu ", " als "],
    ) {
        return sanitize_argument_token(&value);
    }

    None
}

fn extract_tail_after_markers(normalized: &str, markers: &[&str]) -> Option<String> {
    for marker in markers {
        if let Some((_, tail)) = normalized.rsplit_once(marker) {
            let trimmed = tail.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_owned());
            }
        }
    }
    None
}

fn sanitize_argument_token(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    let without_quotes = trimmed
        .trim_matches('"')
        .trim_matches('\'')
        .trim_end_matches(['.', ',', ';', ':'])
        .trim();

    if without_quotes.is_empty() {
        return None;
    }

    Some(without_quotes.to_owned())
}

#[cfg(test)]
mod tests {
    use super::{CommandIntentKind, SafetyDecisionKind, evaluate_safety, fallback_classify};

    #[test]
    fn german_timer_command_is_detected() {
        let intent = fallback_classify("Stelle einen Timer auf 25min");

        assert_eq!(intent.kind, CommandIntentKind::SetTimer);
        assert!(intent.summary.contains("25min"));
        assert!(intent.requires_confirmation);
    }

    #[test]
    fn english_note_command_is_detected() {
        let intent = fallback_classify("save note buy milk");

        assert_eq!(intent.kind, CommandIntentKind::SaveNote);
        assert_eq!(intent.summary, "Notiz speichern");
    }

    #[test]
    fn unknown_command_gets_rejected_by_safety_gate() {
        let intent = fallback_classify("completely unrelated sentence");
        let decision = evaluate_safety(&intent);

        assert_eq!(decision.decision, SafetyDecisionKind::Reject);
        assert_eq!(decision.reason, "unknown_intent");
    }

    #[test]
    fn move_file_is_marked_destructive() {
        let intent = fallback_classify("move file report.pdf to archive");
        let decision = evaluate_safety(&intent);

        assert_eq!(intent.kind, CommandIntentKind::MoveFile);
        assert_eq!(
            intent.arguments.move_destination.as_deref(),
            Some("archive")
        );
        assert_eq!(decision.decision, SafetyDecisionKind::RequireConfirmation);
        assert!(decision.destructive);
    }

    #[test]
    fn rename_target_argument_is_extracted() {
        let intent = fallback_classify("rename file report to final");
        assert_eq!(intent.kind, CommandIntentKind::RenameFile);
        assert_eq!(intent.arguments.rename_target.as_deref(), Some("final"));
    }
}
