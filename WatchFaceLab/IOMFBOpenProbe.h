#ifndef WATCH_FACE_LAB_IOMFB_OPEN_PROBE_H
#define WATCH_FACE_LAB_IOMFB_OPEN_PROBE_H

int iomfb_open_probe_run(void);
int iomfb_lifecycle_probe_run(void);
int iomfb_owned_client_probe_run(void);
int iomfb_end_lifecycle_probe_run(void);
int iomfb_teardown_race_probe_run(unsigned int iterations);
int iomfb_end_teardown_race_probe_run(void);
int iomfb_end_teardown_race_matrix_probe_run(unsigned int iterations);

#endif /* WATCH_FACE_LAB_IOMFB_OPEN_PROBE_H */
