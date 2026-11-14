#ifndef WATCH_FACE_LAB_CVE_112665_PROBE_H
#define WATCH_FACE_LAB_CVE_112665_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Bounded access gate for the public Mach IPC debug query that can return a
 * kernel-object address. This is a leak detector, not an arbitrary read.
 */
__attribute__((visibility("default")))
int32_t cve_2026_112665_probe_run(void);

extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112665_task_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112665_host_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112665_thread_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112665_receive_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_112665_entry_result;
extern __attribute__((visibility("default"))) volatile uint64_t
    cve_2026_112665_task_address;
extern __attribute__((visibility("default"))) volatile uint64_t
    cve_2026_112665_host_address;
extern __attribute__((visibility("default"))) volatile uint64_t
    cve_2026_112665_thread_address;
extern __attribute__((visibility("default"))) volatile uint64_t
    cve_2026_112665_receive_address;
extern __attribute__((visibility("default"))) volatile uint64_t
    cve_2026_112665_entry_address;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_112665_kernel_address_bits;

#ifdef __cplusplus
}
#endif

#endif /* WATCH_FACE_LAB_CVE_112665_PROBE_H */
