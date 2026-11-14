#ifndef WATCH_FACE_LAB_FACE_SUPPORT_READ_ONLY_PROBE_H
#define WATCH_FACE_LAB_FACE_SUPPORT_READ_ONLY_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Checks the FaceSupport Mach lookup boundary and, only when allowed, requests
 * the descriptor count. No descriptor is ingested and no server state changes. */
__attribute__((visibility("default")))
int32_t watchfacelab_facesupport_readonly_probe_run(void);

#ifdef __cplusplus
}
#endif

#endif /* WATCH_FACE_LAB_FACE_SUPPORT_READ_ONLY_PROBE_H */
