#ifndef WATCH_FACE_LAB_CONTAINER_TOKEN_PROBE_H
#define WATCH_FACE_LAB_CONTAINER_TOKEN_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Reproduces only the read-only boundary of the 27.0.1 container-token issue.
 * The probe mutates and restores Library/Caches inside its own dedicated App
 * Group, then lists metadata under SystemGroup. It never writes to the target.
 */
__attribute__((visibility("default")))
int32_t watchfacelab_container_token_probe_run(void);

#ifdef __cplusplus
}
#endif

#endif /* WATCH_FACE_LAB_CONTAINER_TOKEN_PROBE_H */
