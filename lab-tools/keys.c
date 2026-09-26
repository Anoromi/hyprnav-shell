// Key input for the lab with timestamps: one virtual keyboard with the US
// keymap, real evdev keycodes and modifier state, so compositor binds
// (Super+Tab, a release bind on Super_L) see what a physical keyboard sends.
//
//   hns-lab-keys ACTION...
//     down:NAME    press the key whose keysym is NAME (Super_L, Tab, Escape, a)
//     up:NAME      release it
//     tap:NAME     press and release
//     sleep:MS     wait
//     stamp:LABEL  print "stamp LABEL <epoch ms>" (stdout, flushed)
// Like a physical keyboard, the key goes first and the modifier state after
// it, so a Super_L release still sees Super held (Hyprland's `bindr = SUPER,
// SUPER_L` case). Every down/up also prints "key down|up NAME <epoch ms>" right after the
// event is flushed to the compositor.
#define _GNU_SOURCE
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "keyboard.h"

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *km;
static void global(void *data, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
    if (!strcmp(iface, "wl_seat")) seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
    if (!strcmp(iface, "zwp_virtual_keyboard_manager_v1")) km = wl_registry_bind(r, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
}
static void removed(void *data, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener listener = { global, removed };

static long long epoch_ms(void) { struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts); return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000; }
static uint32_t mono_ms(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000); }

static struct xkb_keymap *map;
static struct xkb_state *st;
static xkb_keycode_t find(const char *name) {
    xkb_keysym_t want = xkb_keysym_from_name(name, XKB_KEYSYM_NO_FLAGS);
    if (want == XKB_KEY_NoSymbol) want = xkb_keysym_from_name(name, XKB_KEYSYM_CASE_INSENSITIVE);
    for (xkb_keycode_t k = xkb_keymap_min_keycode(map); k <= xkb_keymap_max_keycode(map); k++) {
        const xkb_keysym_t *syms; int n = xkb_keymap_key_get_syms_by_level(map, k, 0, 0, &syms);
        for (int i = 0; i < n; i++) if (syms[i] == want) return k;
    }
    return 0;
}

int main(int argc, char **argv) {
    struct wl_display *d = wl_display_connect(NULL); if (!d) return 1;
    struct wl_registry *r = wl_display_get_registry(d); wl_registry_add_listener(r, &listener, NULL); wl_display_roundtrip(d);
    if (!seat || !km) { fprintf(stderr, "missing virtual keyboard protocol\n"); return 2; }
    struct zwp_virtual_keyboard_v1 *kb = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(km, seat);
    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = { .layout = "us" };
    map = xkb_keymap_new_from_names(ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS); if (!map) return 3;
    st = xkb_state_new(map);
    char *text = xkb_keymap_get_as_string(map, XKB_KEYMAP_FORMAT_TEXT_V1); size_t n = strlen(text) + 1;
    int fd = memfd_create("hns-lab-keys", MFD_CLOEXEC); if (fd < 0 || write(fd, text, n) != (ssize_t)n) return 4;
    zwp_virtual_keyboard_v1_keymap(kb, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, n);
    wl_display_roundtrip(d);
    usleep(150000);   // let the compositor settle the new keyboard's keymap
    for (int i = 1; i < argc; i++) {
        char *a = argv[i], *arg = strchr(a, ':'); if (!arg) { fprintf(stderr, "bad action %s\n", a); return 5; }
        *arg++ = 0;
        if (!strcmp(a, "sleep")) { usleep(atoi(arg) * 1000); continue; }
        if (!strcmp(a, "stamp")) { printf("stamp %s %lld\n", arg, epoch_ms()); fflush(stdout); continue; }
        int tap = !strcmp(a, "tap"), down = !strcmp(a, "down") || tap, up = !strcmp(a, "up") || tap;
        xkb_keycode_t k = find(arg); if (!k) { fprintf(stderr, "unknown key %s\n", arg); return 6; }
        for (int phase = 0; phase < 2; phase++) {
            int press = phase == 0;
            if ((press && !down) || (!press && !up)) continue;
            zwp_virtual_keyboard_v1_key(kb, mono_ms(), k - 8, press ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED);
            xkb_state_update_key(st, k, press ? XKB_KEY_DOWN : XKB_KEY_UP);
            zwp_virtual_keyboard_v1_modifiers(kb, xkb_state_serialize_mods(st, XKB_STATE_MODS_DEPRESSED), xkb_state_serialize_mods(st, XKB_STATE_MODS_LATCHED),
                                              xkb_state_serialize_mods(st, XKB_STATE_MODS_LOCKED), xkb_state_serialize_layout(st, XKB_STATE_LAYOUT_EFFECTIVE));
            wl_display_flush(d);
            printf("key %s %s %lld\n", press ? "down" : "up", arg, epoch_ms()); fflush(stdout);
            if (tap && press) usleep(30000);
        }
    }
    wl_display_roundtrip(d);
    usleep(50000);
    zwp_virtual_keyboard_v1_destroy(kb);
    wl_display_roundtrip(d);
    return 0;
}
