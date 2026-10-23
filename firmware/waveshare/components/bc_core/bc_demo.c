#include "bc_demo.h"

void bc_demo_init(bc_demo_t *d, int base_w, bool with_hr)
{
    d->t = 0; d->seed = 12345u; d->with_hr = with_hr; d->base_w = base_w > 60 ? base_w : 160; d->hr = 95;
}

static int noise(bc_demo_t *d, int amp)
{
    d->seed = d->seed * 1103515245u + 12345u;
    return (int)((d->seed >> 16) % (2 * amp + 1)) - amp;
}

bc_sample_t bc_demo_next(bc_demo_t *d)
{
    uint32_t t = d->t++ % 1200;          /* 20-min script */
    int b = d->base_w, w, cad;
    if (t < 240) { w = 80 + (b - 80) * (int)t / 240; cad = 78 + (int)t / 30; }               /* warm-up ramp */
    else if (t < 600) { w = b; cad = 88; }                                                    /* steady */
    else if (t < 640) { w = (t % 20) < 6 ? b * 17 / 10 : b; cad = 92; }                       /* surges */
    else if (t < 700) { w = b * 12 / 10; cad = 90; }                                          /* above target */
    else if (t < 730) { w = 0; cad = 0; }                                                     /* coasting */
    else if (t < 738) { bc_sample_t gap = { -1, -1, d->with_hr ? (int16_t)d->hr : (int16_t)-1 }; return gap; }   /* meter dropout */
    else if (t < 840) { w = b * 9 / 10; cad = 66; }                                           /* low-cadence grind */
    else if (t < 960) { w = b * 7 / 10; cad = 86; }                                           /* fading */
    else { w = b; cad = 89; }
    if (w > 0) w += noise(d, 8);
    if (cad > 0) cad += noise(d, 2);
    if (w < 0) w = 0;
    bc_sample_t s = { (int16_t)w, (int16_t)cad, -1 };
    if (d->with_hr) {
        int target = 90 + w / 3;
        d->hr += (target - d->hr) / 8 + (target > d->hr ? 1 : target < d->hr ? -1 : 0);
        s.hr = (int16_t)d->hr;
    }
    return s;
}
