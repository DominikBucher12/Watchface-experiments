#ifndef WATCH_FACE_LAB_CVE_112474_PROBE_H
#define WATCH_FACE_LAB_CVE_112474_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Runs one bounded IOSurface teardown-registration probe.
 *
 * This exercises a kernel path that changed between watchOS 27.0.1 and 27.2,
 * but the public CVE record does not identify its affected subsystem.  A
 * successful registration is evidence of reachability, not proof that the
 * path is CVE-2026-112474 and not proof of kernel memory corruption.
 */
__attribute__((visibility("default")))
void cve_2026_112474_probe_run(void);

/* LLDB-readable result snapshot. INT32_MIN means the call was not reached. */
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112474_surface_id;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112474_register_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112474_remove_result;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112474_reborn_surface_id;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112474_receive_after_increment;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112474_receive_after_decrement;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112474_live_registered_bits;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112474_live_initial_delivery_bits;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112474_live_increment_delivery_bits;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112474_live_decrement_delivery_bits;

#ifdef __cplusplus
}
#endif

#endif /* WATCH_FACE_LAB_CVE_112474_PROBE_H */
