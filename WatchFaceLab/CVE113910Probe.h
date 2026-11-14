#ifndef WATCH_FACE_LAB_CVE_113910_PROBE_H
#define WATCH_FACE_LAB_CVE_113910_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Performs one bounded decmpfs reachability/integrity check in base_directory.
 * A nonzero unexpected-byte count is a disclosure candidate, not CVE proof.
 */
__attribute__((visibility("default")))
int32_t cve_2026_113910_probe_run(const char *base_directory);

extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_113910_setxattr_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_113910_setflags_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_113910_truncate_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cve_2026_113910_stat_result;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_113910_observed_flags;
extern __attribute__((visibility("default"))) volatile int64_t
    cve_2026_113910_observed_size;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_113910_payload_size;
extern __attribute__((visibility("default"))) volatile int64_t
    cve_2026_113910_read_count;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_113910_unexpected_bytes;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_113910_untouched_sentinel_bytes;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_113910_zero_filled_bytes;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_113910_other_bytes;
extern __attribute__((visibility("default"))) volatile uint32_t
    cve_2026_113910_canonical_pointer_words;
extern __attribute__((visibility("default"))) volatile int64_t
    cve_2026_113910_first_unexpected_offset;
extern __attribute__((visibility("default"))) volatile uint64_t
    cve_2026_113910_observed_hash;

#ifdef __cplusplus
}
#endif

#endif /* WATCH_FACE_LAB_CVE_113910_PROBE_H */
