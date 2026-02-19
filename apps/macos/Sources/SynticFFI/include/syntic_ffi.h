#ifndef SYNTIC_FFI_H
#define SYNTIC_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum SynticFfiStatusCode {
  SYNTIC_STATUS_SUCCESS = 0,
  SYNTIC_STATUS_SESSION_ALREADY_ACTIVE = 10,
  SYNTIC_STATUS_DICTATION_NOT_LISTENING = 11,
  SYNTIC_STATUS_DICTATION_NOT_REVIEWING = 12,
  SYNTIC_STATUS_DICTATION_NOT_ACTIVE = 13,
  SYNTIC_STATUS_NULL_POINTER = 20,
  SYNTIC_STATUS_INVALID_UTF8 = 21,
  SYNTIC_STATUS_INVALID_ARGUMENT = 22,
  SYNTIC_STATUS_INTERNAL = 255
};

const char *syntic_core_version(void);
char *syntic_runtime_health_json(void);
char *syntic_dictation_state_json(void);
char *syntic_command_classify_json(const char *utterance);
char *syntic_command_safety_json(const char *utterance);
char *syntic_stt_route_json(uint8_t preference_mode,
                            uint8_t sensitive_mode_enabled,
                            uint8_t network_available,
                            uint32_t utterance_duration_ms);
char *syntic_core_events_since_json(uint64_t last_seen_event_id, uint16_t limit);
char *syntic_domain_events_since_json(uint64_t last_seen_event_id, uint16_t limit);
char *syntic_tool_runtime_signals_since_json(uint64_t last_seen_signal_id, uint16_t limit);
uint8_t syntic_core_event_report_error(const char *source,
                                       const char *code,
                                       const char *message);
uint8_t syntic_core_event_report_permission(const char *source,
                                            const char *permission,
                                            const char *status,
                                            const char *detail);
uint8_t syntic_core_event_report_telemetry(const char *source,
                                           const char *category,
                                           const char *action,
                                           const char *status,
                                           const char *context_json,
                                           uint32_t value_ms);
uint8_t syntic_session_history_record(const char *outcome,
                                      const char *transcript,
                                      const char *locale,
                                      const char *route_provider,
                                      uint32_t duration_ms,
                                      const char *error_code,
                                      const char *injection_disposition);
uint8_t syntic_session_history_mark_last_confirmed_undone(void);
char *syntic_session_history_since_json(uint64_t last_seen_record_id, uint16_t limit);
uint8_t syntic_core_events_clear(void);
uint8_t syntic_domain_events_clear(void);
uint8_t syntic_session_history_clear(void);
uint8_t syntic_dictation_reset(void);
uint8_t syntic_dictation_start(void);
uint8_t syntic_dictation_append_partial(const char *text);
uint8_t syntic_dictation_finalize_review(const char *text);
uint8_t syntic_dictation_confirm(void);
uint8_t syntic_dictation_cancel(void);
uint8_t syntic_dictation_fail(const char *message);
void syntic_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif
