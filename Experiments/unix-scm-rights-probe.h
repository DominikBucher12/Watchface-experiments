#ifndef UNIX_SCM_RIGHTS_PROBE_H
#define UNIX_SCM_RIGHTS_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Runs a bounded public-API SCM_RIGHTS lifetime probe.
 * mode 0 is sequential, mode 1 races close, mode 2 races dup2 replacement.
 */
__attribute__((visibility("default")))
int scm_rights_probe_run(uint32_t rounds, int mode);

#ifdef __cplusplus
}
#endif

#endif /* UNIX_SCM_RIGHTS_PROBE_H */
