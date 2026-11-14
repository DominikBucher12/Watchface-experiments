#ifndef WATCH_FACE_LAB_COW_MEMORY_PROBE_H
#define WATCH_FACE_LAB_COW_MEMORY_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Performs bounded vm_remap, file-backed, and VM-copy memory-entry checks.
 * This is a reachability and semantic baseline, not an exploit attempt.
 */
__attribute__((visibility("default")))
int32_t cow_memory_probe_run(void);

/* LLDB-readable snapshot. INT32_MIN means that stage was not reached. */
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_allocate_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_remap_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_file_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_entry_create_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_entry_map_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_entry_copy_map_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_file_entry_create_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_file_entry_map_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_file_entry_copy_map_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_surface_create_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_surface_lock_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_mlock_result;
extern __attribute__((visibility("default"))) volatile int32_t
    cow_memory_probe_surface_prefetch_result;
extern __attribute__((visibility("default"))) volatile uint32_t
    cow_memory_probe_checks;
extern __attribute__((visibility("default"))) volatile uint32_t
    cow_memory_probe_page_size;

#ifdef __cplusplus
}
#endif

#endif /* WATCH_FACE_LAB_COW_MEMORY_PROBE_H */
