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
  SYNTIC_STATUS_INTERNAL = 255
};

// Returns pointer to static UTF-8 C string. Do not free.
const char *syntic_core_version(void);

// Returns heap-allocated UTF-8 C string. Release with syntic_string_free.
char *syntic_runtime_health_json(void);

// Returns heap-allocated JSON string. Release with syntic_string_free.
char *syntic_dictation_state_json(void);
char *syntic_command_classify_json(const char *utterance);
char *syntic_command_safety_json(const char *utterance);
char *syntic_stt_route_json(uint8_t preference_mode,
                            uint8_t sensitive_mode_enabled,
                            uint8_t network_available,
                            uint32_t utterance_duration_ms);

// Dictation flow state transitions.
uint8_t syntic_dictation_reset(void);
uint8_t syntic_dictation_start(void);
uint8_t syntic_dictation_append_partial(const char *text);
uint8_t syntic_dictation_finalize_review(const char *text);
uint8_t syntic_dictation_confirm(void);
uint8_t syntic_dictation_cancel(void);
uint8_t syntic_dictation_fail(const char *message);

// Releases strings returned by syntic_runtime_health_json.
void syntic_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif
