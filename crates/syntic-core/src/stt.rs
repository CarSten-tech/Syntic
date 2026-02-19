//! STT provider routing rules for command and dictation flows.

/// Preferred provider mode configured by the user.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SttPreferenceMode {
    LocalOnly,
    CloudOnly,
    Auto,
}

/// Available STT providers in MVP.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SttProvider {
    AppleSpeechRecognizer,
    OpenAiWhisper,
}

impl SttProvider {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::AppleSpeechRecognizer => "apple_speech_recognizer",
            Self::OpenAiWhisper => "openai_whisper",
        }
    }
}

/// Input for STT routing decisions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SttRoutingInput {
    pub preference_mode: SttPreferenceMode,
    pub sensitive_mode_enabled: bool,
    pub network_available: bool,
    pub utterance_duration_ms: u32,
}

/// Routing output with selected provider and reason key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SttRoutingDecision {
    pub provider: SttProvider,
    pub reason: &'static str,
}

/// Selects STT provider based on explicit mode and runtime constraints.
#[must_use]
pub fn select_provider(input: SttRoutingInput) -> SttRoutingDecision {
    if input.sensitive_mode_enabled {
        return SttRoutingDecision {
            provider: SttProvider::AppleSpeechRecognizer,
            reason: "sensitive_mode_local_only",
        };
    }

    match input.preference_mode {
        SttPreferenceMode::LocalOnly => SttRoutingDecision {
            provider: SttProvider::AppleSpeechRecognizer,
            reason: "user_preference_local_only",
        },
        SttPreferenceMode::CloudOnly => {
            if input.network_available {
                SttRoutingDecision {
                    provider: SttProvider::OpenAiWhisper,
                    reason: "user_preference_cloud_only",
                }
            } else {
                SttRoutingDecision {
                    provider: SttProvider::AppleSpeechRecognizer,
                    reason: "cloud_unavailable_fallback_local",
                }
            }
        }
        SttPreferenceMode::Auto => {
            if !input.network_available {
                return SttRoutingDecision {
                    provider: SttProvider::AppleSpeechRecognizer,
                    reason: "auto_mode_no_network",
                };
            }

            if input.utterance_duration_ms <= 5_000 {
                return SttRoutingDecision {
                    provider: SttProvider::AppleSpeechRecognizer,
                    reason: "auto_mode_short_utterance_local_first",
                };
            }

            SttRoutingDecision {
                provider: SttProvider::OpenAiWhisper,
                reason: "auto_mode_long_utterance_cloud_primary",
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{SttPreferenceMode, SttProvider, SttRoutingInput, select_provider};

    #[test]
    fn sensitive_mode_enforces_local_provider() {
        let decision = select_provider(SttRoutingInput {
            preference_mode: SttPreferenceMode::CloudOnly,
            sensitive_mode_enabled: true,
            network_available: true,
            utterance_duration_ms: 8_000,
        });

        assert_eq!(decision.provider, SttProvider::AppleSpeechRecognizer);
        assert_eq!(decision.reason, "sensitive_mode_local_only");
    }

    #[test]
    fn cloud_only_without_network_falls_back_to_local() {
        let decision = select_provider(SttRoutingInput {
            preference_mode: SttPreferenceMode::CloudOnly,
            sensitive_mode_enabled: false,
            network_available: false,
            utterance_duration_ms: 8_000,
        });

        assert_eq!(decision.provider, SttProvider::AppleSpeechRecognizer);
        assert_eq!(decision.reason, "cloud_unavailable_fallback_local");
    }

    #[test]
    fn auto_mode_short_utterance_prefers_local() {
        let decision = select_provider(SttRoutingInput {
            preference_mode: SttPreferenceMode::Auto,
            sensitive_mode_enabled: false,
            network_available: true,
            utterance_duration_ms: 2_000,
        });

        assert_eq!(decision.provider, SttProvider::AppleSpeechRecognizer);
        assert_eq!(decision.reason, "auto_mode_short_utterance_local_first");
    }

    #[test]
    fn auto_mode_long_utterance_prefers_cloud() {
        let decision = select_provider(SttRoutingInput {
            preference_mode: SttPreferenceMode::Auto,
            sensitive_mode_enabled: false,
            network_available: true,
            utterance_duration_ms: 10_000,
        });

        assert_eq!(decision.provider, SttProvider::OpenAiWhisper);
        assert_eq!(decision.reason, "auto_mode_long_utterance_cloud_primary");
    }
}
