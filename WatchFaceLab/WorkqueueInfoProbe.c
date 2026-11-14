#include "WorkqueueInfoProbe.h"

#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

/* libproc.h is not shipped in the watchOS SDK. Resolve the public libproc
 * entry point dynamically and keep the ABI record local to this access gate. */
enum { watchfacelab_proc_pidworkqueueinfo = 12 };
enum {
    watchfacelab_proc_all_pids = 1,
    watchfacelab_max_cross_process_pids = 512,
};

struct watchfacelab_proc_workqueueinfo {
    uint32_t thread_count;
    uint32_t running_thread_count;
    uint32_t blocked_thread_count;
    uint32_t state;
};

typedef int (*watchfacelab_proc_pidinfo_fn)(
    int pid, int flavor, uint64_t argument, void *buffer, int buffer_size);

typedef int (*watchfacelab_proc_listpids_fn)(
    uint32_t type, uint32_t type_info, void *buffer, int buffer_size);

static watchfacelab_proc_pidinfo_fn
resolve_proc_pidinfo(void)
{
    return (watchfacelab_proc_pidinfo_fn)dlsym(RTLD_DEFAULT, "proc_pidinfo");
}

int workqueue_info_access_probe_run(void)
{
    dlerror();
    watchfacelab_proc_pidinfo_fn proc_pidinfo_fn = resolve_proc_pidinfo();
    const char *symbol_error = dlerror();
    if (proc_pidinfo_fn == NULL) {
        printf("[workqueue-info] proc_pidinfo unavailable error=%s\n",
               symbol_error != NULL ? symbol_error : "unknown");
        return 1;
    }

    struct watchfacelab_proc_workqueueinfo info = {0};
    errno = 0;
    int length = proc_pidinfo_fn(
        getpid(), watchfacelab_proc_pidworkqueueinfo, 0,
        &info, (int)sizeof(info));
    int call_error = errno;

    printf("[workqueue-info] self pid=%d length=%d error=%d "
           "threads=%u running=%u blocked=%u state=0x%x\n",
           getpid(), length, call_error,
           info.thread_count, info.running_thread_count,
           info.blocked_thread_count, info.state);
    return length == (int)sizeof(info) ? 0 : 2;
}

int workqueue_info_cross_process_probe_run(void)
{
    dlerror();
    watchfacelab_proc_pidinfo_fn proc_pidinfo_fn = resolve_proc_pidinfo();
    watchfacelab_proc_listpids_fn proc_listpids_fn =
        (watchfacelab_proc_listpids_fn)dlsym(RTLD_DEFAULT, "proc_listpids");
    const char *symbol_error = dlerror();
    if (proc_pidinfo_fn == NULL || proc_listpids_fn == NULL) {
        printf("[workqueue-cross] libproc symbols unavailable error=%s\n",
               symbol_error != NULL ? symbol_error : "unknown");
        return 1;
    }

    int pids[watchfacelab_max_cross_process_pids] = {0};
    errno = 0;
    int listed_bytes = proc_listpids_fn(
        watchfacelab_proc_all_pids, 0, pids, (int)sizeof(pids));
    int list_error = errno;
    if (listed_bytes <= 0) {
        printf("[workqueue-cross] list bytes=%d error=%d\n",
               listed_bytes, list_error);
        return 2;
    }

    int pid_count = listed_bytes / (int)sizeof(pids[0]);
    int queried = 0;
    int succeeded = 0;
    int no_workqueue = 0;
    int denied = 0;
    int other_error = 0;
    pid_t self_pid = getpid();

    for (int index = 0; index < pid_count; index++) {
        int pid = pids[index];
        if (pid <= 0 || pid == self_pid) {
            continue;
        }

        struct watchfacelab_proc_workqueueinfo info = {0};
        errno = 0;
        int length = proc_pidinfo_fn(
            pid, watchfacelab_proc_pidworkqueueinfo, 0,
            &info, (int)sizeof(info));
        int call_error = errno;
        queried++;

        if (length == (int)sizeof(info)) {
            succeeded++;
            printf("[workqueue-cross] readable pid=%d threads=%u running=%u "
                   "blocked=%u state=0x%x\n",
                   pid, info.thread_count, info.running_thread_count,
                   info.blocked_thread_count, info.state);
        } else if (call_error == ESRCH) {
            no_workqueue++;
        } else if (call_error == EPERM || call_error == EACCES) {
            denied++;
        } else {
            other_error++;
        }
    }

    printf("[workqueue-cross] summary listed=%d queried=%d readable=%d "
           "esrch=%d denied=%d other=%d\n",
           pid_count, queried, succeeded, no_workqueue, denied, other_error);
    return succeeded > 0 ? 0 : 3;
}
