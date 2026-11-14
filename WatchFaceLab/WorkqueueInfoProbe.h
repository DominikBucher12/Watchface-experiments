#ifndef WATCHFACELAB_WORKQUEUE_INFO_PROBE_H
#define WATCHFACELAB_WORKQUEUE_INFO_PROBE_H

/* Reads the current process's 16-byte PROC_PIDWORKQUEUEINFO record once. */
int workqueue_info_access_probe_run(void);

/* Enumerates a bounded PID snapshot and reads each other PID at most once. */
int workqueue_info_cross_process_probe_run(void);

#endif
