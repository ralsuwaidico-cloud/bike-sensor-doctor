/*
 * bc_core — DEMO MODE sensor simulator. Clearly SIMULATED data for testing the device without a bicycle.
 * It exists only so screens, ride controls, coaching and results can be exercised; everything it feeds is marked demo,
 * demo rides are stored separately from real history and never change the FTP.
 *
 * Script (repeats every 20 min): warm-up ramp → steady endurance with small noise → surges → a coasting stretch →
 * an 8-s meter dropout (tests NO DATA) → low-cadence grind → back to steady. Optional simulated HR strap.
 */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "bc_ride.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t t;          /* seconds since demo start */
    uint32_t seed;
    bool with_hr;
    int base_w;          /* rider's steady power */
    int hr;              /* simulated heart rate state */
} bc_demo_t;

void bc_demo_init(bc_demo_t *d, int base_w, bool with_hr);
/** Next simulated second. Missing values are -1 exactly like a real sensor gap. */
bc_sample_t bc_demo_next(bc_demo_t *d);

#ifdef __cplusplus
}
#endif
