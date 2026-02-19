#ifndef SYNTIC_FFI_H
#define SYNTIC_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns pointer to static UTF-8 C string. Do not free.
const char *syntic_core_version(void);

// Returns heap-allocated UTF-8 C string. Release with syntic_string_free.
char *syntic_runtime_health_json(void);

// Releases strings returned by syntic_runtime_health_json.
void syntic_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif
