// Pointer input for the lab: move the virtual pointer and send wheel or
// touchpad scroll. The seat helper only keeps the devices alive; this one
// drives them.
//
//   hns-lab-scroll [--at X Y] [--finger] [--delay MS] STEPS...
//
// Each STEP is a signed number: wheel clicks by default (positive scrolls
// down), pixels with --finger. Without --at the pointer is left where it is.
#define _GNU_SOURCE
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "pointer.h"

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *pm;

static void global(void *data, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
    if (!strcmp(iface, "wl_seat")) seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
    if (!strcmp(iface, "zwlr_virtual_pointer_manager_v1")) pm = wl_registry_bind(r, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void removed(void *data, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener listener = { global, removed };

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(int argc, char **argv) {
    int finger = 0, have_at = 0, delay_ms = 40;
    uint32_t at_x = 0, at_y = 0, ex = 1920, ey = 1080;
    double steps[256];
    int nsteps = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--finger")) finger = 1;
        else if (!strcmp(argv[i], "--at") && i + 2 < argc) { have_at = 1; at_x = atoi(argv[++i]); at_y = atoi(argv[++i]); }
        else if (!strcmp(argv[i], "--extent") && i + 2 < argc) { ex = atoi(argv[++i]); ey = atoi(argv[++i]); }
        else if (!strcmp(argv[i], "--delay") && i + 1 < argc) delay_ms = atoi(argv[++i]);
        else if (nsteps < 256) steps[nsteps++] = atof(argv[i]);
    }
    struct wl_display *d = wl_display_connect(NULL);
    if (!d) { fprintf(stderr, "no display\n"); return 1; }
    struct wl_registry *r = wl_display_get_registry(d);
    wl_registry_add_listener(r, &listener, NULL);
    wl_display_roundtrip(d);
    if (!seat || !pm) { fprintf(stderr, "missing wlr-virtual-pointer\n"); return 2; }
    struct zwlr_virtual_pointer_v1 *p = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pm, seat);

    if (have_at) {
        zwlr_virtual_pointer_v1_motion_absolute(p, now_ms(), at_x, at_y, ex, ey);
        zwlr_virtual_pointer_v1_frame(p);
        wl_display_roundtrip(d);
        usleep(60000);
    }
    for (int i = 0; i < nsteps; i++) {
        uint32_t t = now_ms();
        if (finger) {
            zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_FINGER);
            zwlr_virtual_pointer_v1_axis(p, t, WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(steps[i]));
        } else {
            zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_WHEEL);
            zwlr_virtual_pointer_v1_axis_discrete(p, t, WL_POINTER_AXIS_VERTICAL_SCROLL,
                                                  wl_fixed_from_double(steps[i] * 15.0), (int32_t)steps[i]);
        }
        zwlr_virtual_pointer_v1_frame(p);
        wl_display_flush(d);
        usleep(delay_ms * 1000);
    }
    if (finger && nsteps) {
        zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_FINGER);
        zwlr_virtual_pointer_v1_axis_stop(p, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL);
        zwlr_virtual_pointer_v1_frame(p);
    }
    wl_display_roundtrip(d);
    return 0;
}
