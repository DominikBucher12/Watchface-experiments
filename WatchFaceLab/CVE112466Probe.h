#ifndef WATCH_FACE_LAB_CVE_112466_PROBE_H
#define WATCH_FACE_LAB_CVE_112466_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Performs one no-frame VideoToolbox H.264 capability query. This is only a
 * reachability gate; it does not submit media or attempt to trigger the CVE.
 */
__attribute__((visibility("default")))
int32_t cve_2026_112466_probe_run(void);

extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112466_dlopen_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112466_symbol_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112466_query_status;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112466_property_count;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112466_property_mask;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112466_encoder_id_present;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112466_relevant_key_count;

#ifdef __cplusplus
}
#endif

#endif /* WATCH_FACE_LAB_CVE_112466_PROBE_H */
