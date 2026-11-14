#include "BPFOpenProbe.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int try_path(const char *path)
{
    errno = 0;
    int fd = open(path, O_RDWR | O_CLOEXEC);
    int error = errno;
    if (fd >= 0) {
        printf("[bpf-open] path=%s fd=%d result=accessible\n", path, fd);
        close(fd);
        return 0;
    }

    printf("[bpf-open] path=%s error=%d (%s)\n",
        path, error, strerror(error));
    return error == 0 ? EIO : error;
}

int bpf_open_probe_run(void)
{
    static const char *const paths[] = {
        "/dev/bpf", "/dev/bpf0", "/dev/bpf1", "/dev/bpf2", "/dev/bpf3",
    };
    int last_error = ENOENT;

    for (size_t index = 0; index < sizeof(paths) / sizeof(paths[0]); index++) {
        int result = try_path(paths[index]);
        if (result == 0) {
            return 0;
        }
        last_error = result;
        if (result == EPERM || result == EACCES) {
            break;
        }
    }
    return last_error;
}
