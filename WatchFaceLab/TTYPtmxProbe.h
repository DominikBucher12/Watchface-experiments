#ifndef WATCH_FACE_LAB_TTY_PTMX_PROBE_H
#define WATCH_FACE_LAB_TTY_PTMX_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Runs a bounded public-API PTY/kqueue lifetime probe.
 * race_mode == 0 validates the path sequentially; nonzero races close(2)
 * against EV_DELETE. Iterations are clamped to 256 in the watch application.
 */
__attribute__((visibility("default")))
int tty_ptmx_probe_run(uint32_t iterations, int race_mode);

#ifdef __cplusplus
}
#endif

#endif /* WATCH_FACE_LAB_TTY_PTMX_PROBE_H */
