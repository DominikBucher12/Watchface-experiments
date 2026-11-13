/*
 * Bounded PTY/kqueue lifetime probe for the tty_ptmx.c candidate fix.
 *
 * The default mode is a sequential reachability check.  The close-vs-delete
 * race is only enabled with --race, so merely launching this binary cannot
 * stress the kernel.  There is no heap spray, descriptor churn outside the
 * selected iteration count, or attempt to turn a fault into exploitation.
 */

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/types.h>
#include <unistd.h>

#define DEFAULT_ITERATIONS 64U
#define MAX_ITERATIONS 4096U

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
    int error;
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
    errno = 0;
    job->result = close(job->fd);
    job->error = errno;
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

static int open_pty_pair(int *master_out, int *slave_out)
{
    char slave_name[128];
    int master = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (master < 0) {
        return -1;
    }
    if (grantpt(master) != 0 || unlockpt(master) != 0 ||
        ptsname_r(master, slave_name, sizeof(slave_name)) != 0) {
        close(master);
        return -1;
    }

    int slave = open(slave_name, O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (slave < 0) {
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

    if (open_pty_pair(&master, &slave) != 0 || (kq = kqueue()) < 0) {
        goto setup_failure;
    }

    EV_SET(&changes[0], (uintptr_t)master, EVFILT_READ,
        EV_ADD | EV_ENABLE, 0, 0, NULL);
    EV_SET(&changes[1], (uintptr_t)master, EVFILT_WRITE,
        EV_ADD | EV_ENABLE, 0, 0, NULL);
    if (kevent(kq, changes, 2, NULL, 0, NULL) != 0) {
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
        struct race_gate gate = {
            .ready = 0U,
            .start = false,
        };
        struct close_job close_job = {
            .gate = &gate, .fd = master, .result = -1, .error = 0,
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

static int parse_iterations(const char *text, uint32_t *value_out)
{
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || value == 0 ||
        value > MAX_ITERATIONS) {
        return -1;
    }
    *value_out = (uint32_t)value;
    return 0;
}

int main(int argc, char **argv)
{
    bool race = false;
    uint32_t iterations = DEFAULT_ITERATIONS;

    for (int index = 1; index < argc; ++index) {
        if (strcmp(argv[index], "--race") == 0) {
            race = true;
        } else if (strcmp(argv[index], "--iterations") == 0 &&
            index + 1 < argc) {
            if (parse_iterations(argv[++index], &iterations) != 0) {
                fprintf(stderr, "invalid iteration count (1-%u)\n",
                    MAX_ITERATIONS);
                return 2;
            }
        } else {
            fprintf(stderr,
                "usage: %s [--race] [--iterations 1-%u]\n",
                argv[0], MAX_ITERATIONS);
            return 2;
        }
    }

    struct result_counts counts = {0};
    for (uint32_t index = 0; index < iterations; ++index) {
        (void)run_round(race, &counts);
    }

    printf("mode=%s requested=%u completed=%u setup_failed=%u "
           "delete_ok=%u delete_enoent=%u delete_ebadf=%u "
           "delete_other=%u close_failed=%u\n",
        race ? "race" : "sequential", iterations, counts.completed,
        counts.setup_failed, counts.delete_ok, counts.delete_enoent,
        counts.delete_ebadf, counts.delete_other, counts.close_failed);
    return counts.setup_failed == 0 && counts.delete_other == 0 &&
        counts.close_failed == 0 ? 0 : 1;
}
