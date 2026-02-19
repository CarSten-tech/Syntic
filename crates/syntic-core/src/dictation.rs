//! Dictation flow state machine used by platform adapters and FFI.

/// Runtime phase for one dictation interaction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DictationPhase {
    #[default]
    Idle,
    Listening,
    Reviewing,
    Confirmed,
    Cancelled,
    Failed,
}

impl DictationPhase {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Listening => "listening",
            Self::Reviewing => "reviewing",
            Self::Confirmed => "confirmed",
            Self::Cancelled => "cancelled",
            Self::Failed => "failed",
        }
    }
}

/// Transition errors for dictation state operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DictationTransitionError {
    SessionAlreadyActive,
    DictationNotListening,
    DictationNotReviewing,
    DictationNotActive,
}

impl DictationTransitionError {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::SessionAlreadyActive => "session_already_active",
            Self::DictationNotListening => "dictation_not_listening",
            Self::DictationNotReviewing => "dictation_not_reviewing",
            Self::DictationNotActive => "dictation_not_active",
        }
    }
}

/// Immutable view on current dictation state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DictationSnapshot {
    pub phase: DictationPhase,
    pub live_transcript: String,
    pub review_transcript: String,
    pub last_error: Option<String>,
    pub requires_confirmation: bool,
}

/// Stateful dictation session controller.
#[derive(Debug, Default)]
pub struct DictationSessionController {
    phase: DictationPhase,
    live_transcript: String,
    review_transcript: String,
    last_error: Option<String>,
}

impl DictationSessionController {
    #[must_use]
    pub fn snapshot(&self) -> DictationSnapshot {
        DictationSnapshot {
            phase: self.phase,
            live_transcript: self.live_transcript.clone(),
            review_transcript: self.review_transcript.clone(),
            last_error: self.last_error.clone(),
            requires_confirmation: self.phase == DictationPhase::Reviewing,
        }
    }

    pub fn reset(&mut self) {
        self.phase = DictationPhase::Idle;
        self.live_transcript.clear();
        self.review_transcript.clear();
        self.last_error = None;
    }

    /// Starts a new dictation session in listening mode.
    ///
    /// # Errors
    ///
    /// Returns `DictationTransitionError::SessionAlreadyActive` if a dictation
    /// session is already in progress.
    pub fn start_listening(&mut self) -> Result<(), DictationTransitionError> {
        if matches!(
            self.phase,
            DictationPhase::Listening | DictationPhase::Reviewing
        ) {
            return Err(DictationTransitionError::SessionAlreadyActive);
        }

        self.phase = DictationPhase::Listening;
        self.live_transcript.clear();
        self.review_transcript.clear();
        self.last_error = None;
        Ok(())
    }

    /// Updates the live partial transcript while listening.
    ///
    /// # Errors
    ///
    /// Returns `DictationTransitionError::DictationNotListening` when called
    /// outside the listening phase.
    pub fn append_partial(&mut self, transcript: &str) -> Result<(), DictationTransitionError> {
        if self.phase != DictationPhase::Listening {
            return Err(DictationTransitionError::DictationNotListening);
        }

        transcript.clone_into(&mut self.live_transcript);
        Ok(())
    }

    /// Finalizes dictation and enters review mode.
    ///
    /// # Errors
    ///
    /// Returns `DictationTransitionError::DictationNotListening` when called
    /// outside the listening phase.
    pub fn finalize_review(&mut self, transcript: &str) -> Result<(), DictationTransitionError> {
        if self.phase != DictationPhase::Listening {
            return Err(DictationTransitionError::DictationNotListening);
        }

        transcript.clone_into(&mut self.review_transcript);
        self.live_transcript.clear();
        self.phase = DictationPhase::Reviewing;
        Ok(())
    }

    /// Confirms reviewed dictation text.
    ///
    /// # Errors
    ///
    /// Returns `DictationTransitionError::DictationNotReviewing` when the
    /// session is not currently in review mode.
    pub fn confirm(&mut self) -> Result<(), DictationTransitionError> {
        if self.phase != DictationPhase::Reviewing {
            return Err(DictationTransitionError::DictationNotReviewing);
        }

        self.phase = DictationPhase::Confirmed;
        Ok(())
    }

    /// Cancels an active dictation session.
    ///
    /// # Errors
    ///
    /// Returns `DictationTransitionError::DictationNotActive` when no active
    /// session is running.
    pub fn cancel(&mut self) -> Result<(), DictationTransitionError> {
        if !matches!(
            self.phase,
            DictationPhase::Listening | DictationPhase::Reviewing
        ) {
            return Err(DictationTransitionError::DictationNotActive);
        }

        self.phase = DictationPhase::Cancelled;
        self.live_transcript.clear();
        self.review_transcript.clear();
        Ok(())
    }

    pub fn fail(&mut self, message: &str) {
        self.phase = DictationPhase::Failed;
        self.last_error = Some(message.to_owned());
        self.live_transcript.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::{DictationPhase, DictationSessionController, DictationTransitionError};

    #[test]
    fn new_controller_starts_idle() {
        let controller = DictationSessionController::default();
        let snapshot = controller.snapshot();

        assert_eq!(snapshot.phase, DictationPhase::Idle);
        assert!(!snapshot.requires_confirmation);
        assert!(snapshot.live_transcript.is_empty());
    }

    #[test]
    fn listening_review_confirm_flow() {
        let mut controller = DictationSessionController::default();

        controller.start_listening().expect("start listening");
        controller
            .append_partial("hello world")
            .expect("append partial");
        controller
            .finalize_review("hello world")
            .expect("finalize review");
        controller.confirm().expect("confirm");

        let snapshot = controller.snapshot();
        assert_eq!(snapshot.phase, DictationPhase::Confirmed);
        assert_eq!(snapshot.review_transcript, "hello world");
    }

    #[test]
    fn cancel_requires_active_dictation() {
        let mut controller = DictationSessionController::default();

        let error = controller.cancel().expect_err("cancel should fail in idle");
        assert_eq!(error, DictationTransitionError::DictationNotActive);

        controller.start_listening().expect("start listening");
        controller.cancel().expect("cancel active dictation");

        let snapshot = controller.snapshot();
        assert_eq!(snapshot.phase, DictationPhase::Cancelled);
        assert!(snapshot.review_transcript.is_empty());
    }

    #[test]
    fn start_fails_when_session_already_active() {
        let mut controller = DictationSessionController::default();
        controller.start_listening().expect("first start");

        let error = controller
            .start_listening()
            .expect_err("second start must fail");
        assert_eq!(error, DictationTransitionError::SessionAlreadyActive);
    }

    #[test]
    fn fail_moves_controller_to_failed_state() {
        let mut controller = DictationSessionController::default();
        controller.start_listening().expect("start listening");
        controller.fail("microphone unavailable");

        let snapshot = controller.snapshot();
        assert_eq!(snapshot.phase, DictationPhase::Failed);
        assert_eq!(
            snapshot.last_error.as_deref(),
            Some("microphone unavailable")
        );
    }

    #[test]
    fn reset_returns_controller_to_idle() {
        let mut controller = DictationSessionController::default();
        controller.start_listening().expect("start listening");
        controller
            .append_partial("transcript")
            .expect("append partial transcript");
        controller.reset();

        let snapshot = controller.snapshot();
        assert_eq!(snapshot.phase, DictationPhase::Idle);
        assert!(snapshot.live_transcript.is_empty());
        assert!(snapshot.review_transcript.is_empty());
    }
}
