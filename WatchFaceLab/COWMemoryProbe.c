#include "COWMemoryProbe.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

volatile int32_t cow_memory_probe_allocate_result = INT32_MIN;
volatile int32_t cow_memory_probe_remap_result = INT32_MIN;
volatile int32_t cow_memory_probe_file_result = INT32_MIN;
volatile int32_t cow_memory_probe_entry_create_result = INT32_MIN;
volatile int32_t cow_memory_probe_entry_map_result = INT32_MIN;
volatile int32_t cow_memory_probe_entry_copy_map_result = INT32_MIN;
volatile int32_t cow_memory_probe_file_entry_create_result = INT32_MIN;
volatile int32_t cow_memory_probe_file_entry_map_result = INT32_MIN;
volatile int32_t cow_memory_probe_file_entry_copy_map_result = INT32_MIN;
volatile int32_t cow_memory_probe_surface_create_result = INT32_MIN;
volatile int32_t cow_memory_probe_surface_lock_result = INT32_MIN;
volatile int32_t cow_memory_probe_mlock_result = INT32_MIN;
volatile int32_t cow_memory_probe_surface_prefetch_result = INT32_MIN;
volatile uint32_t cow_memory_probe_checks = 0;
volatile uint32_t cow_memory_probe_page_size = 0;

enum {
    COW_CHECK_INITIAL_ALIAS = 1U << 0,
    COW_CHECK_ALIAS_WRITE_ISOLATED = 1U << 1,
    COW_CHECK_SOURCE_WRITE_ISOLATED = 1U << 2,
    COW_CHECK_EXPECTED_PROTECTIONS = 1U << 3,
    COW_CHECK_FILE_INITIAL = 1U << 4,
    COW_CHECK_FILE_WRITE_ISOLATED = 1U << 5,
    COW_CHECK_ENTRY_INITIAL = 1U << 6,
    COW_CHECK_ENTRY_WRITE_ISOLATED = 1U << 7,
    COW_CHECK_ENTRY_SOURCE_WRITE_ISOLATED = 1U << 8,
    COW_CHECK_ENTRY_COPY_INITIAL = 1U << 9,
    COW_CHECK_ENTRY_COPY_WRITE_ISOLATED = 1U << 10,
    COW_CHECK_SURFACE_ADDRESS_MATCH = 1U << 11,
    COW_CHECK_SURFACE_INITIAL = 1U << 12,
    COW_CHECK_SURFACE_WRITE_ISOLATED = 1U << 13,
    COW_CHECK_MLOCK_SUCCEEDED = 1U << 14,
    COW_CHECK_SURFACE_PREFETCH_CALLED = 1U << 15,
    COW_CHECK_FILE_ENTRY_INITIAL = 1U << 16,
    COW_CHECK_FILE_ENTRY_COPY_INITIAL = 1U << 17,
    COW_CHECK_FILE_SURFACE_ADDRESS_MATCH = 1U << 18,
    COW_CHECK_FILE_SURFACE_INITIAL = 1U << 19,
    COW_CHECK_FILE_SURFACE_WRITE_ISOLATED = 1U << 20,
    COW_CHECK_FILE_ENTRY_FILE_UNCHANGED = 1U << 21,
};

typedef CFTypeRef (*iosurface_create_fn)(CFDictionaryRef properties);
typedef void *(*iosurface_get_base_address_fn)(CFTypeRef surface);
typedef kern_return_t (*iosurface_lock_fn)(
    CFTypeRef surface, uint32_t options, uint32_t *seed);
typedef void (*iosurface_prefetch_pages_fn)(CFTypeRef surface);

static void
run_iosurface_address_check(
    vm_size_t size,
    volatile uint8_t *source_bytes,
    volatile uint8_t *mapped_bytes,
    volatile uint8_t *copy_bytes,
    uint8_t expected_first,
    uint8_t expected_last,
    uint32_t address_match_check,
    uint32_t initial_check,
    uint32_t isolated_check)
{
    void *framework = dlopen(
        "/System/Library/Frameworks/IOSurface.framework/IOSurface",
        RTLD_LAZY | RTLD_LOCAL);
    if (framework == NULL) {
        cow_memory_probe_surface_create_result = -1;
        return;
    }

    iosurface_create_fn surface_create = NULL;
    iosurface_get_base_address_fn surface_get_base_address = NULL;
    iosurface_lock_fn surface_lock = NULL;
    iosurface_lock_fn surface_unlock = NULL;
    iosurface_prefetch_pages_fn surface_prefetch_pages = NULL;
    *(void **)(&surface_create) = dlsym(framework, "IOSurfaceCreate");
    *(void **)(&surface_get_base_address) =
        dlsym(framework, "IOSurfaceGetBaseAddress");
    *(void **)(&surface_lock) = dlsym(framework, "IOSurfaceLock");
    *(void **)(&surface_unlock) = dlsym(framework, "IOSurfaceUnlock");
    *(void **)(&surface_prefetch_pages) =
        dlsym(framework, "IOSurfacePrefetchPages");
    if (surface_create == NULL || surface_get_base_address == NULL ||
        surface_lock == NULL || surface_unlock == NULL) {
        cow_memory_probe_surface_create_result = -2;
        dlclose(framework);
        return;
    }

    int64_t address_value = (int64_t)(uintptr_t)copy_bytes;
    int64_t size_value = (int64_t)size;
    CFNumberRef address_number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt64Type, &address_value);
    CFNumberRef size_number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt64Type, &size_value);
    if (address_number == NULL || size_number == NULL) {
        if (address_number != NULL) {
            CFRelease(address_number);
        }
        if (size_number != NULL) {
            CFRelease(size_number);
        }
        cow_memory_probe_surface_create_result = -3;
        dlclose(framework);
        return;
    }

    const void *keys[] = {
        CFSTR("IOSurfaceAddress"),
        CFSTR("IOSurfaceAllocSize"),
    };
    const void *values[] = {address_number, size_number};
    CFDictionaryRef properties = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CFRelease(address_number);
    CFRelease(size_number);
    if (properties == NULL) {
        cow_memory_probe_surface_create_result = -4;
        dlclose(framework);
        return;
    }

    CFTypeRef surface = surface_create(properties);
    CFRelease(properties);
    if (surface == NULL) {
        cow_memory_probe_surface_create_result = -5;
        dlclose(framework);
        return;
    }
    cow_memory_probe_surface_create_result = 0;

    if (surface_prefetch_pages != NULL) {
        surface_prefetch_pages(surface);
        cow_memory_probe_surface_prefetch_result = 0;
        cow_memory_probe_checks |= COW_CHECK_SURFACE_PREFETCH_CALLED;
    } else {
        cow_memory_probe_surface_prefetch_result = -1;
    }

    cow_memory_probe_mlock_result = mlock((const void *)copy_bytes, size);
    if (cow_memory_probe_mlock_result == 0) {
        cow_memory_probe_checks |= COW_CHECK_MLOCK_SUCCEEDED;
    }

    uint32_t seed = 0;
    kern_return_t kr = surface_lock(surface, 0, &seed);
    cow_memory_probe_surface_lock_result = kr;
    if (kr == KERN_SUCCESS) {
        volatile uint8_t *surface_bytes =
            (volatile uint8_t *)surface_get_base_address(surface);
        if (surface_bytes == copy_bytes) {
            cow_memory_probe_checks |= address_match_check;
            if (surface_bytes[0] == expected_first &&
                surface_bytes[size - 1] == expected_last) {
                cow_memory_probe_checks |= initial_check;
            }

            surface_bytes[0] = 0xd7;
            surface_bytes[size - 1] = 0xe8;
            if (source_bytes[0] == expected_first &&
                source_bytes[size - 1] == expected_last &&
                mapped_bytes[0] == expected_first &&
                mapped_bytes[size - 1] == expected_last &&
                copy_bytes[0] == 0xd7 && copy_bytes[size - 1] == 0xe8) {
                cow_memory_probe_checks |= isolated_check;
            }
        }
        (void)surface_unlock(surface, 0, &seed);
    }

    if (cow_memory_probe_mlock_result == 0) {
        (void)munlock((const void *)copy_bytes, size);
    }
    CFRelease(surface);
    dlclose(framework);
}

static void
run_memory_entry_check(vm_size_t size)
{
    vm_address_t source = 0;
    kern_return_t kr = vm_allocate(
        mach_task_self(), &source, size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        cow_memory_probe_entry_create_result = kr;
        return;
    }

    volatile uint8_t *source_bytes = (volatile uint8_t *)(uintptr_t)source;
    source_bytes[0] = 0x71;
    source_bytes[size - 1] = 0x82;

    memory_object_size_t entry_size = size;
    mach_port_t entry = MACH_PORT_NULL;
    kr = mach_make_memory_entry_64(
        mach_task_self(),
        &entry_size,
        source,
        VM_PROT_DEFAULT | VM_PROT_IS_MASK | MAP_MEM_VM_COPY,
        &entry,
        MACH_PORT_NULL);
    cow_memory_probe_entry_create_result = kr;
    if (kr != KERN_SUCCESS || entry == MACH_PORT_NULL || entry_size < size) {
        if (entry != MACH_PORT_NULL) {
            (void)mach_port_deallocate(mach_task_self(), entry);
        }
        (void)vm_deallocate(mach_task_self(), source, size);
        return;
    }

    vm_address_t mapped = 0;
    kr = vm_map(
        mach_task_self(),
        &mapped,
        size,
        0,
        VM_FLAGS_ANYWHERE,
        entry,
        0,
        FALSE,
        VM_PROT_READ | VM_PROT_WRITE,
        VM_PROT_READ | VM_PROT_WRITE,
        VM_INHERIT_NONE);
    cow_memory_probe_entry_map_result = kr;
    if (kr == KERN_SUCCESS) {
        volatile uint8_t *mapped_bytes =
            (volatile uint8_t *)(uintptr_t)mapped;
        if (mapped_bytes[0] == 0x71 && mapped_bytes[size - 1] == 0x82) {
            cow_memory_probe_checks |= COW_CHECK_ENTRY_INITIAL;
        }

        vm_address_t copy_mapped = 0;
        kr = vm_map(
            mach_task_self(),
            &copy_mapped,
            size,
            0,
            VM_FLAGS_ANYWHERE,
            entry,
            0,
            TRUE,
            VM_PROT_READ | VM_PROT_WRITE,
            VM_PROT_READ | VM_PROT_WRITE,
            VM_INHERIT_NONE);
        cow_memory_probe_entry_copy_map_result = kr;
        if (kr == KERN_SUCCESS) {
            volatile uint8_t *copy_bytes =
                (volatile uint8_t *)(uintptr_t)copy_mapped;
            if (copy_bytes[0] == 0x71 && copy_bytes[size - 1] == 0x82) {
                cow_memory_probe_checks |= COW_CHECK_ENTRY_COPY_INITIAL;
            }

            run_iosurface_address_check(
                size,
                source_bytes,
                mapped_bytes,
                copy_bytes,
                0x71,
                0x82,
                COW_CHECK_SURFACE_ADDRESS_MATCH,
                COW_CHECK_SURFACE_INITIAL,
                COW_CHECK_SURFACE_WRITE_ISOLATED);

            copy_bytes[0] = 0xd7;
            copy_bytes[size - 1] = 0xe8;
            if (source_bytes[0] == 0x71 && source_bytes[size - 1] == 0x82 &&
                mapped_bytes[0] == 0x71 && mapped_bytes[size - 1] == 0x82 &&
                copy_bytes[0] == 0xd7 && copy_bytes[size - 1] == 0xe8) {
                cow_memory_probe_checks |=
                    COW_CHECK_ENTRY_COPY_WRITE_ISOLATED;
            }

            mapped_bytes[0] = 0x93;
            mapped_bytes[size - 1] = 0xa4;
            if (source_bytes[0] == 0x71 && source_bytes[size - 1] == 0x82 &&
                mapped_bytes[0] == 0x93 && mapped_bytes[size - 1] == 0xa4 &&
                copy_bytes[0] == 0xd7 && copy_bytes[size - 1] == 0xe8) {
                cow_memory_probe_checks |= COW_CHECK_ENTRY_WRITE_ISOLATED;
            }

            source_bytes[0] = 0xb5;
            source_bytes[size - 1] = 0xc6;
            if (source_bytes[0] == 0xb5 && source_bytes[size - 1] == 0xc6 &&
                mapped_bytes[0] == 0x93 && mapped_bytes[size - 1] == 0xa4 &&
                copy_bytes[0] == 0xd7 && copy_bytes[size - 1] == 0xe8) {
                cow_memory_probe_checks |=
                    COW_CHECK_ENTRY_SOURCE_WRITE_ISOLATED;
            }

            (void)vm_deallocate(mach_task_self(), copy_mapped, size);
        }

        (void)vm_deallocate(mach_task_self(), mapped, size);
    }

    (void)mach_port_deallocate(mach_task_self(), entry);
    (void)vm_deallocate(mach_task_self(), source, size);
}

static void
run_file_memory_entry_check(vm_size_t size)
{
    const char *temporary_directory = getenv("TMPDIR");
    if (temporary_directory == NULL) {
        cow_memory_probe_file_entry_create_result = -1;
        return;
    }

    char path[PATH_MAX];
    int length = snprintf(
        path, sizeof(path), "%s/cow-file-entry-XXXXXX", temporary_directory);
    if (length < 0 || (size_t)length >= sizeof(path)) {
        cow_memory_probe_file_entry_create_result = -2;
        return;
    }

    int fd = mkstemp(path);
    if (fd < 0) {
        cow_memory_probe_file_entry_create_result = -errno;
        return;
    }
    (void)unlink(path);

    if (ftruncate(fd, (off_t)size) != 0 ||
        pwrite(fd, "\x51", 1, 0) != 1 ||
        pwrite(fd, "\x62", 1, (off_t)size - 1) != 1) {
        cow_memory_probe_file_entry_create_result = -3;
        close(fd);
        return;
    }

    volatile uint8_t *source_bytes = mmap(
        NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (source_bytes == MAP_FAILED) {
        cow_memory_probe_file_entry_create_result = -4;
        close(fd);
        return;
    }

    memory_object_size_t entry_size = size;
    mach_port_t entry = MACH_PORT_NULL;
    kern_return_t kr = mach_make_memory_entry_64(
        mach_task_self(),
        &entry_size,
        (memory_object_offset_t)(uintptr_t)source_bytes,
        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_IS_MASK,
        &entry,
        MACH_PORT_NULL);
    cow_memory_probe_file_entry_create_result = kr;
    if (kr != KERN_SUCCESS || entry == MACH_PORT_NULL || entry_size < size) {
        if (entry != MACH_PORT_NULL) {
            (void)mach_port_deallocate(mach_task_self(), entry);
        }
        munmap((void *)source_bytes, size);
        close(fd);
        return;
    }

    vm_address_t mapped = 0;
    kr = vm_map(
        mach_task_self(),
        &mapped,
        size,
        0,
        VM_FLAGS_ANYWHERE,
        entry,
        0,
        FALSE,
        VM_PROT_READ | VM_PROT_WRITE,
        VM_PROT_READ | VM_PROT_WRITE,
        VM_INHERIT_NONE);
    cow_memory_probe_file_entry_map_result = kr;
    if (kr == KERN_SUCCESS) {
        volatile uint8_t *mapped_bytes =
            (volatile uint8_t *)(uintptr_t)mapped;
        if (source_bytes[0] == 0x51 && source_bytes[size - 1] == 0x62 &&
            mapped_bytes[0] == 0x51 && mapped_bytes[size - 1] == 0x62) {
            cow_memory_probe_checks |= COW_CHECK_FILE_ENTRY_INITIAL;
        }

        vm_address_t copy_mapped = 0;
        kr = vm_map(
            mach_task_self(),
            &copy_mapped,
            size,
            0,
            VM_FLAGS_ANYWHERE,
            entry,
            0,
            TRUE,
            VM_PROT_READ | VM_PROT_WRITE,
            VM_PROT_READ | VM_PROT_WRITE,
            VM_INHERIT_NONE);
        cow_memory_probe_file_entry_copy_map_result = kr;
        if (kr == KERN_SUCCESS) {
            volatile uint8_t *copy_bytes =
                (volatile uint8_t *)(uintptr_t)copy_mapped;
            if (copy_bytes[0] == 0x51 && copy_bytes[size - 1] == 0x62) {
                cow_memory_probe_checks |= COW_CHECK_FILE_ENTRY_COPY_INITIAL;
            }

            run_iosurface_address_check(
                size,
                source_bytes,
                mapped_bytes,
                copy_bytes,
                0x51,
                0x62,
                COW_CHECK_FILE_SURFACE_ADDRESS_MATCH,
                COW_CHECK_FILE_SURFACE_INITIAL,
                COW_CHECK_FILE_SURFACE_WRITE_ISOLATED);

            uint8_t file_edges[2] = {0, 0};
            ssize_t first_read = pread(fd, &file_edges[0], 1, 0);
            ssize_t last_read =
                pread(fd, &file_edges[1], 1, (off_t)size - 1);
            if (first_read == 1 && last_read == 1 &&
                file_edges[0] == 0x51 && file_edges[1] == 0x62 &&
                source_bytes[0] == 0x51 &&
                source_bytes[size - 1] == 0x62 &&
                mapped_bytes[0] == 0x51 &&
                mapped_bytes[size - 1] == 0x62) {
                cow_memory_probe_checks |=
                    COW_CHECK_FILE_ENTRY_FILE_UNCHANGED;
            }
            (void)vm_deallocate(mach_task_self(), copy_mapped, size);
        }
        (void)vm_deallocate(mach_task_self(), mapped, size);
    }

    (void)mach_port_deallocate(mach_task_self(), entry);
    munmap((void *)source_bytes, size);
    close(fd);
}

static void
run_file_backed_check(vm_size_t size)
{
    const char *temporary_directory = getenv("TMPDIR");
    if (temporary_directory == NULL) {
        cow_memory_probe_file_result = -1;
        return;
    }

    char path[PATH_MAX];
    int length = snprintf(
        path, sizeof(path), "%s/cow-memory-XXXXXX", temporary_directory);
    if (length < 0 || (size_t)length >= sizeof(path)) {
        cow_memory_probe_file_result = -2;
        return;
    }

    int fd = mkstemp(path);
    if (fd < 0) {
        cow_memory_probe_file_result = -errno;
        return;
    }
    (void)unlink(path);

    cow_memory_probe_file_result = -3;
    if (ftruncate(fd, (off_t)size) != 0 ||
        pwrite(fd, "\x51", 1, 0) != 1 ||
        pwrite(fd, "\x62", 1, (off_t)size - 1) != 1) {
        close(fd);
        return;
    }

    volatile uint8_t *first = mmap(
        NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    volatile uint8_t *second = mmap(
        NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    if (first == MAP_FAILED || second == MAP_FAILED) {
        if (first != MAP_FAILED) {
            munmap((void *)first, size);
        }
        if (second != MAP_FAILED) {
            munmap((void *)second, size);
        }
        close(fd);
        cow_memory_probe_file_result = -4;
        return;
    }

    if (first[0] == 0x51 && first[size - 1] == 0x62 &&
        second[0] == 0x51 && second[size - 1] == 0x62) {
        cow_memory_probe_checks |= COW_CHECK_FILE_INITIAL;
    }

    first[0] = 0xc3;
    first[size - 1] = 0x3c;
    uint8_t file_edges[2] = {0, 0};
    ssize_t first_read = pread(fd, &file_edges[0], 1, 0);
    ssize_t last_read = pread(fd, &file_edges[1], 1, (off_t)size - 1);
    if (first[0] == 0xc3 && first[size - 1] == 0x3c &&
        second[0] == 0x51 && second[size - 1] == 0x62 &&
        first_read == 1 && last_read == 1 &&
        file_edges[0] == 0x51 && file_edges[1] == 0x62) {
        cow_memory_probe_checks |= COW_CHECK_FILE_WRITE_ISOLATED;
    }

    munmap((void *)second, size);
    munmap((void *)first, size);
    close(fd);
    cow_memory_probe_file_result = 0;
}

int32_t
cow_memory_probe_run(void)
{
    cow_memory_probe_allocate_result = INT32_MIN;
    cow_memory_probe_remap_result = INT32_MIN;
    cow_memory_probe_file_result = INT32_MIN;
    cow_memory_probe_entry_create_result = INT32_MIN;
    cow_memory_probe_entry_map_result = INT32_MIN;
    cow_memory_probe_entry_copy_map_result = INT32_MIN;
    cow_memory_probe_file_entry_create_result = INT32_MIN;
    cow_memory_probe_file_entry_map_result = INT32_MIN;
    cow_memory_probe_file_entry_copy_map_result = INT32_MIN;
    cow_memory_probe_surface_create_result = INT32_MIN;
    cow_memory_probe_surface_lock_result = INT32_MIN;
    cow_memory_probe_mlock_result = INT32_MIN;
    cow_memory_probe_surface_prefetch_result = INT32_MIN;
    cow_memory_probe_checks = 0;

    long queried_page_size = sysconf(_SC_PAGESIZE);
    if (queried_page_size <= 0 ||
        (uint64_t)queried_page_size > (uint64_t)UINT32_MAX) {
        return -1;
    }

    vm_size_t size = (vm_size_t)queried_page_size;
    cow_memory_probe_page_size = (uint32_t)size;

    vm_address_t source = 0;
    kern_return_t kr = vm_allocate(
        mach_task_self(), &source, size, VM_FLAGS_ANYWHERE);
    cow_memory_probe_allocate_result = kr;
    if (kr != KERN_SUCCESS) {
        return -2;
    }

    volatile uint8_t *source_bytes = (volatile uint8_t *)(uintptr_t)source;
    source_bytes[0] = 0x11;
    source_bytes[size - 1] = 0x22;

    vm_address_t alias = 0;
    vm_prot_t current_protection = VM_PROT_NONE;
    vm_prot_t maximum_protection = VM_PROT_NONE;
    kr = vm_remap(
        mach_task_self(),
        &alias,
        size,
        0,
        VM_FLAGS_ANYWHERE,
        mach_task_self(),
        source,
        TRUE,
        &current_protection,
        &maximum_protection,
        VM_INHERIT_NONE);
    cow_memory_probe_remap_result = kr;
    if (kr != KERN_SUCCESS) {
        (void)vm_deallocate(mach_task_self(), source, size);
        return -3;
    }

    volatile uint8_t *alias_bytes = (volatile uint8_t *)(uintptr_t)alias;
    if (alias_bytes[0] == 0x11 && alias_bytes[size - 1] == 0x22) {
        cow_memory_probe_checks |= COW_CHECK_INITIAL_ALIAS;
    }

    alias_bytes[0] = 0xa5;
    alias_bytes[size - 1] = 0x5a;
    if (source_bytes[0] == 0x11 && source_bytes[size - 1] == 0x22 &&
        alias_bytes[0] == 0xa5 && alias_bytes[size - 1] == 0x5a) {
        cow_memory_probe_checks |= COW_CHECK_ALIAS_WRITE_ISOLATED;
    }

    source_bytes[0] = 0x33;
    source_bytes[size - 1] = 0x44;
    if (source_bytes[0] == 0x33 && source_bytes[size - 1] == 0x44 &&
        alias_bytes[0] == 0xa5 && alias_bytes[size - 1] == 0x5a) {
        cow_memory_probe_checks |= COW_CHECK_SOURCE_WRITE_ISOLATED;
    }

    if ((current_protection & VM_PROT_WRITE) != 0 &&
        (maximum_protection & VM_PROT_WRITE) != 0) {
        cow_memory_probe_checks |= COW_CHECK_EXPECTED_PROTECTIONS;
    }

    (void)vm_deallocate(mach_task_self(), alias, size);
    (void)vm_deallocate(mach_task_self(), source, size);

    run_file_backed_check(size);
    run_memory_entry_check(size);
    run_file_memory_entry_check(size);

    printf("[cow-memory] allocate=%d remap=%d file=%d entry-create=%d "
           "entry-map=%d entry-copy-map=%d surface-create=%d "
           "surface-lock=%d surface-prefetch=%d mlock=%d "
           "file-entry-create=%d file-entry-map=%d "
           "file-entry-copy-map=%d "
           "checks=0x%x page=%u\n",
           cow_memory_probe_allocate_result,
           cow_memory_probe_remap_result,
           cow_memory_probe_file_result,
           cow_memory_probe_entry_create_result,
           cow_memory_probe_entry_map_result,
           cow_memory_probe_entry_copy_map_result,
           cow_memory_probe_surface_create_result,
           cow_memory_probe_surface_lock_result,
           cow_memory_probe_surface_prefetch_result,
           cow_memory_probe_mlock_result,
           cow_memory_probe_file_entry_create_result,
           cow_memory_probe_file_entry_map_result,
           cow_memory_probe_file_entry_copy_map_result,
           cow_memory_probe_checks,
           cow_memory_probe_page_size);
    return (cow_memory_probe_checks & 0x7ffU) == 0x7ffU ? 0 : 1;
}
