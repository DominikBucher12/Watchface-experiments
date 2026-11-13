#include "TTYPtmxProbe.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/event.h>
#include <unistd.h>

#define WATCH_PROBE_MAX_ITERATIONS 256U

struct result_counts {
    uint32_t completed;
    uint32_t setup_failed;
    uint32_t delete_ok;
    uint32_t delete_enoent;
    uint32_t delete_ebadf;
    uint32_t delete_other;
    uint32_t close_failed;
};

struct race_gate {
    atomic_uint ready;
    atomic_bool start;
};

struct close_job {
    struct race_gate *gate;
    int fd;
    int result;
};

struct delete_job {
    struct race_gate *gate;
    int kq;
    int fd;
    int result;
    int error;
};

static void wait_for_start(struct race_gate *gate)
{
    atomic_fetch_add_explicit(&gate->ready, 1U, memory_order_release);
    while (!atomic_load_explicit(&gate->start, memory_order_acquire)) {
        sched_yield();
    }
}

static int delete_knote_pair(int kq, int fd)
{
    struct kevent changes[2];
    EV_SET(&changes[0], (uintptr_t)fd, EVFILT_READ, EV_DELETE, 0, 0, NULL);
    EV_SET(&changes[1], (uintptr_t)fd, EVFILT_WRITE, EV_DELETE, 0, 0, NULL);
    return kevent(kq, changes, 2, NULL, 0, NULL);
}

static void *close_worker(void *opaque)
{
    struct close_job *job = opaque;
    wait_for_start(job->gate);
    job->result = close(job->fd);
    return NULL;
}

static void *delete_worker(void *opaque)
{
    struct delete_job *job = opaque;
    wait_for_start(job->gate);
    errno = 0;
    job->result = delete_knote_pair(job->kq, job->fd);
    job->error = errno;
    return NULL;
}

static void record_delete(struct result_counts *counts, int result, int error)
{
    if (result == 0) {
        counts->delete_ok++;
    } else if (error == ENOENT) {
        counts->delete_enoent++;
    } else if (error == EBADF) {
        counts->delete_ebadf++;
    } else {
        counts->delete_other++;
    }
}

static int open_pty_pair(
    int *master_out,
    int *slave_out,
    const char **stage_out,
    int *error_out)
{
    char slave_name[128];
    int master = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (master < 0) {
        *stage_out = "posix_openpt";
        *error_out = errno;
        return -1;
    }
    if (grantpt(master) != 0) {
        *stage_out = "grantpt";
        *error_out = errno;
        close(master);
        return -1;
    }
    if (unlockpt(master) != 0) {
        *stage_out = "unlockpt";
        *error_out = errno;
        close(master);
        return -1;
    }
    int name_result = ptsname_r(master, slave_name, sizeof(slave_name));
    if (name_result != 0) {
        *stage_out = "ptsname_r";
        *error_out = name_result;
        close(master);
        return -1;
    }

    int slave = open(slave_name, O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (slave < 0) {
        *stage_out = "open-slave";
        *error_out = errno;
        close(master);
        return -1;
    }
    *master_out = master;
    *slave_out = slave;
    return 0;
}

static int run_round(bool race, struct result_counts *counts)
{
    int master = -1;
    int slave = -1;
    int kq = -1;
    struct kevent changes[2];
    const char *setup_stage = NULL;
    int setup_error = 0;

    if (open_pty_pair(
            &master, &slave, &setup_stage, &setup_error) != 0) {
        if (counts->setup_failed == 0U) {
            printf("[tty-ptmx] setup stage=%s error=%d\n",
                setup_stage, setup_error);
        }
        goto setup_failure;
    }
    kq = kqueue();
    if (kq < 0) {
        if (counts->setup_failed == 0U) {
            printf("[tty-ptmx] setup stage=kqueue error=%d\n", errno);
        }
        goto setup_failure;
    }

    EV_SET(&changes[0], (uintptr_t)master, EVFILT_READ,
        EV_ADD | EV_ENABLE, 0, 0, NULL);
    EV_SET(&changes[1], (uintptr_t)master, EVFILT_WRITE,
        EV_ADD | EV_ENABLE, 0, 0, NULL);
    if (kevent(kq, changes, 2, NULL, 0, NULL) != 0) {
        if (counts->setup_failed == 0U) {
            printf("[tty-ptmx] setup stage=kevent-add error=%d\n", errno);
        }
        goto setup_failure;
    }

    if (!race) {
        errno = 0;
        int delete_result = delete_knote_pair(kq, master);
        record_delete(counts, delete_result, errno);
        if (close(master) != 0) {
            counts->close_failed++;
        }
        master = -1;
    } else {
        struct race_gate gate = {.ready = 0U, .start = false};
        struct close_job close_job = {
            .gate = &gate, .fd = master, .result = -1,
        };
        struct delete_job delete_job = {
            .gate = &gate, .kq = kq, .fd = master, .result = -1, .error = 0,
        };
        pthread_t closer;
        pthread_t deleter;
        bool closer_created = false;
        bool deleter_created = false;

        if (pthread_create(&closer, NULL, close_worker, &close_job) == 0) {
            closer_created = true;
        }
        if (closer_created &&
            pthread_create(&deleter, NULL, delete_worker, &delete_job) == 0) {
            deleter_created = true;
        }
        if (!closer_created || !deleter_created) {
            atomic_store_explicit(&gate.start, true, memory_order_release);
            if (closer_created) {
                pthread_join(closer, NULL);
                master = -1;
            }
            goto setup_failure;
        }

        while (atomic_load_explicit(&gate.ready, memory_order_acquire) != 2U) {
            sched_yield();
        }
        atomic_store_explicit(&gate.start, true, memory_order_release);
        pthread_join(closer, NULL);
        pthread_join(deleter, NULL);
        master = -1;

        if (close_job.result != 0) {
            counts->close_failed++;
        }
        record_delete(counts, delete_job.result, delete_job.error);
    }

    close(slave);
    close(kq);
    counts->completed++;
    return 0;

setup_failure:
    if (master >= 0) {
        close(master);
    }
    if (slave >= 0) {
        close(slave);
    }
    if (kq >= 0) {
        close(kq);
    }
    counts->setup_failed++;
    return -1;
}

int tty_ptmx_probe_run(uint32_t iterations, int race_mode)
{
    if (iterations == 0U) {
        iterations = 1U;
    } else if (iterations > WATCH_PROBE_MAX_ITERATIONS) {
        iterations = WATCH_PROBE_MAX_ITERATIONS;
    }

    struct result_counts counts = {0};
    printf("[tty-ptmx] begin mode=%s requested=%u\n",
        race_mode != 0 ? "race" : "sequential", iterations);
    for (uint32_t index = 0; index < iterations; ++index) {
        (void)run_round(race_mode != 0, &counts);
    }
    printf("[tty-ptmx] end mode=%s requested=%u completed=%u "
           "setup_failed=%u delete_ok=%u delete_enoent=%u "
           "delete_ebadf=%u delete_other=%u close_failed=%u\n",
        race_mode != 0 ? "race" : "sequential", iterations,
        counts.completed, counts.setup_failed, counts.delete_ok,
        counts.delete_enoent, counts.delete_ebadf, counts.delete_other,
        counts.close_failed);

    return counts.setup_failed == 0 && counts.delete_other == 0 &&
        counts.close_failed == 0 ? 0 : -1;
}
