// One mouse button, pressed and released inside whatever Wayland session
// WAYLAND_DISPLAY names, through `zwlr_virtual_pointer_v1` (#187).
//
// Why this exists. Seam 2 could drive keys — `wtype`, and `hyprctl dispatch
// sendshortcut` for the layer surfaces `wtype` cannot aim at — but it could
// not drive the pointer, and so could assert nothing about *delivery*.
// `sendshortcut` looks like it should: it carries mouse buttons, and it
// answers `ok`. It delivers nothing to a layer surface, because its target is
// resolved as a toplevel window and the bar, the drawers and the lock are all
// layer shells. Measured on Hyprland 0.56.1: `sendshortcut , mouse:272, ` and
// every spelling of it left the shell's log silent, with a drawer open and
// with none.
//
// A virtual pointer goes in at the input-device end instead, above libinput
// and below everything the shell can see, so the button is hit-tested,
// focus-grabbed and delivered exactly as a real one is. That is the whole
// point when the thing under test is delivery: #187 is a click that reaches
// neither the bar button under it nor the drawer's dismiss catcher, and an
// instrument that bypasses the compositor's own routing cannot see it.
//
// Position is deliberately not this program's job. `hyprctl dispatch
// movecursor` warps the cursor in *global* coordinates and re-runs hit
// testing, which is both simpler than binding an output for
// `motion_absolute` and the one form that spans several outputs. This sends
// the button wherever the cursor already is.
//
//     usage: nested-click [left|right|middle|<linux button code>]
//
// Built on demand by `nested_click` in tools/nested-session.sh, from the
// protocol vendored at tools/protocols/. Not part of the shell.
#include <linux/input-event-codes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct zwlr_virtual_pointer_manager_v1 *manager = NULL;
static struct wl_seat *seat = NULL;

static void handle_global(void *data, struct wl_registry *registry, uint32_t name,
                          const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name,
                                   &zwlr_virtual_pointer_manager_v1_interface, 1);
    else if (seat == NULL && strcmp(interface, wl_seat_interface.name) == 0)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
}

static void handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = handle_global,
    .global_remove = handle_global_remove,
};

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(int argc, char **argv) {
    const char *want = argc > 1 ? argv[1] : "left";
    uint32_t button;

    if (strcmp(want, "left") == 0)
        button = BTN_LEFT;
    else if (strcmp(want, "right") == 0)
        button = BTN_RIGHT;
    else if (strcmp(want, "middle") == 0)
        button = BTN_MIDDLE;
    else
        button = (uint32_t)strtoul(want, NULL, 0);

    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL) {
        fprintf(stderr, "nested-click: no wayland display (WAYLAND_DISPLAY unset?)\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (manager == NULL) {
        fprintf(stderr, "nested-click: compositor offers no "
                        "zwlr_virtual_pointer_manager_v1\n");
        return 1;
    }

    // A null seat is allowed by the protocol and is what we want: the harness
    // has exactly one, and naming it would mean binding wl_seat only to hand
    // it straight back.
    struct zwlr_virtual_pointer_v1 *pointer =
        zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);

    // Press and release as two flushed batches with a real gap between them.
    // Sent together they are one arrival at the compositor, and a surface that
    // distinguishes a click from a press-and-hold — a long-press, a drag —
    // would see the wrong thing.
    zwlr_virtual_pointer_v1_button(pointer, now_ms(), button,
                                   WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);

    struct timespec gap = {.tv_sec = 0, .tv_nsec = 30 * 1000 * 1000};
    nanosleep(&gap, NULL);

    zwlr_virtual_pointer_v1_button(pointer, now_ms(), button,
                                   WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);

    zwlr_virtual_pointer_v1_destroy(pointer);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
