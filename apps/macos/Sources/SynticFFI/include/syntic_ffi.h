#ifndef SYNTIC_FFI_H
#define SYNTIC_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *syntic_core_version(void);
char *syntic_runtime_health_json(void);
void syntic_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif
