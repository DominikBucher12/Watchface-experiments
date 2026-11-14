/*
 * Bounded AF_UNIX SCM_RIGHTS lifetime probe.
 *
 * Sequential mode is the default.  --race explicitly races sendmsg(), while
 * it internalizes one file descriptor, against close() of that descriptor.
 * This is a trigger-only diagnostic: no heap spray, grooming, or corruption
 * stage is present.
 */

#include "unix-scm-rights-probe.h"

#include <TargetConditionals.h>
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#define DEFAULT_ROUNDS 64u
#define MAX_ROUNDS 4096u

struct start_gate {
    _Atomic unsigned ready;
    _Atomic bool go;
};

struct race_context {
    int sender;
    int passed_fd;
    int replacement_fd;
    int mode;
    struct start_gate gate;
    ssize_t send_result;
    int send_error;
    int close_result;
    int close_error;
};

struct summary {
    unsigned requested;
    unsigned completed;
    unsigned send_ok;
    unsigned send_ebadf;
    unsigned send_other;
    unsigned close_ok;
    unsigned close_ebadf;
    unsigned recv_ok;
    unsigned recv_failed;
    unsigned recv_fifo;
    unsigned recv_socket;
    unsigned recv_other;
    unsigned replace_ok;
    unsigned replace_failed;
    unsigned setup_failed;
};

static void
gate_wait(struct start_gate *gate)
{
    atomic_fetch_add_explicit(&gate->ready, 1, memory_order_release);
    while (!atomic_load_explicit(&gate->go, memory_order_acquire)) {
        sched_yield();
    }
}

static ssize_t
send_one_fd(int socket_fd, int passed_fd)
{
    char byte = 'R';
    struct iovec iov = {.iov_base = &byte, .iov_len = sizeof(byte)};
    union {
        struct cmsghdr align;
        unsigned char bytes[CMSG_SPACE(sizeof(int))];
    } control = {0};
    struct msghdr message = {0};
    message.msg_iov = &iov;
    message.msg_iovlen = 1;
    message.msg_control = control.bytes;
    message.msg_controllen = sizeof(control.bytes);

    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(header), &passed_fd, sizeof(passed_fd));
    return sendmsg(socket_fd, &message, 0);
}

static int
receive_one_fd(int socket_fd)
{
    char byte = 0;
    struct iovec iov = {.iov_base = &byte, .iov_len = sizeof(byte)};
    union {
        struct cmsghdr align;
        unsigned char bytes[CMSG_SPACE(sizeof(int))];
    } control = {0};
    struct msghdr message = {0};
    message.msg_iov = &iov;
    message.msg_iovlen = 1;
    message.msg_control = control.bytes;
    message.msg_controllen = sizeof(control.bytes);

    if (recvmsg(socket_fd, &message, 0) != 1) {
        return -1;
    }
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    if (header == NULL || header->cmsg_level != SOL_SOCKET ||
        header->cmsg_type != SCM_RIGHTS ||
        header->cmsg_len < CMSG_LEN(sizeof(int))) {
        errno = EBADMSG;
        return -1;
    }
    int received = -1;
    memcpy(&received, CMSG_DATA(header), sizeof(received));
    return received;
}

static void *
send_worker(void *opaque)
{
    struct race_context *context = opaque;
    gate_wait(&context->gate);
    context->send_result = send_one_fd(context->sender, context->passed_fd);
    context->send_error = context->send_result < 0 ? errno : 0;
    return NULL;
}

static void *
close_worker(void *opaque)
{
    struct race_context *context = opaque;
    gate_wait(&context->gate);
    if (context->mode == 2) {
        context->close_result = dup2(context->replacement_fd, context->passed_fd);
    } else {
        context->close_result = close(context->passed_fd);
    }
    context->close_error = context->close_result < 0 ? errno : 0;
    return NULL;
}

static int
run_round(int mode, struct summary *summary)
{
    int sockets[2] = {-1, -1};
    int pipe_fds[2] = {-1, -1};
    int replacements[2] = {-1, -1};
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sockets) != 0 ||
        pipe(pipe_fds) != 0 ||
        (mode == 2 && socketpair(AF_UNIX, SOCK_STREAM, 0, replacements) != 0)) {
        summary->setup_failed++;
        goto fail;
    }

    ssize_t sent = -1;
    int send_error = 0;
    int close_result = -1;
    int close_error = 0;

    if (mode == 0) {
        sent = send_one_fd(sockets[0], pipe_fds[0]);
        send_error = sent < 0 ? errno : 0;
        close_result = close(pipe_fds[0]);
        close_error = close_result < 0 ? errno : 0;
        pipe_fds[0] = -1;
    } else {
        struct race_context context = {
            .sender = sockets[0],
            .passed_fd = pipe_fds[0],
            .replacement_fd = replacements[0],
            .mode = mode,
            .gate = {.ready = 0, .go = false},
            .send_result = -1,
            .close_result = -1,
        };
        pthread_t sender_thread;
        pthread_t closer_thread;
        if (pthread_create(&sender_thread, NULL, send_worker, &context) != 0) {
            summary->setup_failed++;
            goto fail;
        }
        if (pthread_create(&closer_thread, NULL, close_worker, &context) != 0) {
            atomic_store_explicit(&context.gate.go, true, memory_order_release);
            (void)pthread_join(sender_thread, NULL);
            summary->setup_failed++;
            goto fail;
        }
        while (atomic_load_explicit(&context.gate.ready, memory_order_acquire) != 2) {
            sched_yield();
        }
        atomic_store_explicit(&context.gate.go, true, memory_order_release);
        (void)pthread_join(sender_thread, NULL);
        (void)pthread_join(closer_thread, NULL);
        sent = context.send_result;
        send_error = context.send_error;
        close_result = context.close_result;
        close_error = context.close_error;
        if (mode == 1) {
            pipe_fds[0] = -1;
        }
    }

    if (sent == 1) {
        summary->send_ok++;
        int received = receive_one_fd(sockets[1]);
        if (received >= 0) {
            summary->recv_ok++;
            struct stat status;
            if (fstat(received, &status) == 0 && S_ISFIFO(status.st_mode)) {
                summary->recv_fifo++;
            } else if (fstat(received, &status) == 0 && S_ISSOCK(status.st_mode)) {
                summary->recv_socket++;
            } else {
                summary->recv_other++;
            }
            (void)close(received);
        } else {
            summary->recv_failed++;
        }
    } else if (send_error == EBADF) {
        summary->send_ebadf++;
    } else {
        summary->send_other++;
    }
    if (mode == 2) {
        if (close_result == pipe_fds[0]) {
            summary->replace_ok++;
        } else {
            summary->replace_failed++;
        }
    } else {
        if (close_result == 0) {
            summary->close_ok++;
        } else if (close_error == EBADF) {
            summary->close_ebadf++;
        }
    }
    summary->completed++;

    (void)close(pipe_fds[1]);
    if (pipe_fds[0] >= 0) (void)close(pipe_fds[0]);
    if (replacements[0] >= 0) (void)close(replacements[0]);
    if (replacements[1] >= 0) (void)close(replacements[1]);
    (void)close(sockets[0]);
    (void)close(sockets[1]);
    return 0;

fail:
    if (pipe_fds[0] >= 0) (void)close(pipe_fds[0]);
    if (pipe_fds[1] >= 0) (void)close(pipe_fds[1]);
    if (replacements[0] >= 0) (void)close(replacements[0]);
    if (replacements[1] >= 0) (void)close(replacements[1]);
    if (sockets[0] >= 0) (void)close(sockets[0]);
    if (sockets[1] >= 0) (void)close(sockets[1]);
    return -1;
}

int
scm_rights_probe_run(uint32_t requested_rounds, int mode)
{
    if (mode < 0 || mode > 2) {
        return 2;
    }
    unsigned rounds = requested_rounds == 0 ? DEFAULT_ROUNDS : requested_rounds;
#if TARGET_OS_WATCH
    const unsigned limit = 256u;
#else
    const unsigned limit = MAX_ROUNDS;
#endif
    if (rounds > limit) {
        rounds = limit;
    }

    struct summary summary = {.requested = rounds};
    for (unsigned round = 0; round < rounds; round++) {
        (void)run_round(mode, &summary);
    }
    const char *mode_name = mode == 0 ? "sequential" :
        (mode == 1 ? "close-race" : "replace-race");
    printf("[scm-rights] mode=%s requested=%u completed=%u setup_failed=%u "
           "send_ok=%u send_ebadf=%u send_other=%u close_ok=%u "
           "close_ebadf=%u replace_ok=%u replace_failed=%u recv_ok=%u "
           "recv_failed=%u recv_fifo=%u recv_socket=%u recv_other=%u\n",
           mode_name, summary.requested,
           summary.completed, summary.setup_failed, summary.send_ok,
           summary.send_ebadf, summary.send_other, summary.close_ok,
           summary.close_ebadf, summary.replace_ok, summary.replace_failed,
           summary.recv_ok, summary.recv_failed, summary.recv_fifo,
           summary.recv_socket, summary.recv_other);
    return summary.setup_failed == 0 && summary.recv_failed == 0 ? 0 : 1;
}

#if !TARGET_OS_WATCH
int
main(int argc, char **argv)
{
    int mode = 0;
    unsigned rounds = DEFAULT_ROUNDS;
    if (argc >= 2 && strcmp(argv[1], "--race") == 0) {
        mode = 1;
    } else if (argc >= 2 && strcmp(argv[1], "--replace-race") == 0) {
        mode = 2;
    } else if (argc >= 2 && strcmp(argv[1], "--sequential") != 0) {
        fprintf(stderr, "usage: %s [--sequential|--race|--replace-race] [rounds]\n", argv[0]);
        return 2;
    }
    if (argc >= 3) {
        char *end = NULL;
        unsigned long parsed = strtoul(argv[2], &end, 10);
        if (end == argv[2] || *end != '\0' || parsed == 0 || parsed > MAX_ROUNDS) {
            fprintf(stderr, "rounds must be in 1..%u\n", MAX_ROUNDS);
            return 2;
        }
        rounds = (unsigned)parsed;
    }

    return scm_rights_probe_run(rounds, mode);
}
#endif
