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
// Position is deliberately not this program's job for a *click*. `hyprctl
// dispatch movecursor` warps the cursor in *global* coordinates and re-runs hit
// testing, which is both simpler than binding an output for `motion_absolute`
// and the one form that spans several outputs. A plain invocation sends the
// button wherever the cursor already is.
//
// A **drag** cannot be assembled that way, and that is why the second mode
// exists. The virtual pointer is created, used and destroyed inside one
// process, so a press in one invocation and a release in another cannot hold a
// button down — the device dies in between, and the compositor drops the grab
// with it. So the whole gesture happens here: press, a run of motions, release.
//
// The motions are **absolute** (`motion_absolute`, against the output's own
// extents) and not relative. Relative motion goes through pointer acceleration,
// so how far the cursor actually travelled stops being arithmetic and the
// landing coordinate becomes a property of the machine's libinput profile. A
// drag whose end point is not exactly where the caller asked is a drag that
// cannot be asserted on.
//
// Each step is its own `frame()` with a few milliseconds after it, for the same
// reason the press and release below are two flushed batches: motions sent
// together arrive as one event, and a surface that tracks a drag would see a
// teleport rather than a gesture.
//
//     usage: nested-click [left|right|middle|<linux button code>]
//            nested-click <button> --drag x1 y1 x2 y2 w h [steps] [--hold-ms N]
//
// `--hold-ms` is how long the button stays down at the destination before it is
// released — 60ms by default, which is only a beat for the surface to read the
// last motion. A caller that wants to do something *during* the drag asks for
// more: a drag is atomic from the shell's point of view, so cancelling one from
// the keyboard means sending the key while this process is still holding the
// button, and the hold is the window that makes that a wait rather than a race
// (tools/calendar-harness.sh's Escape-cancels-a-drag check).
//
// `w` and `h` are the extents the coordinates are stated against — the
// *output's* size, which the caller reads from the compositor rather than
// assuming. Single-output sessions only: `motion_absolute` is scoped to one
// output, and this binds none.
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

static void settle(long ms) {
    struct timespec gap = {.tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000 * 1000};
    nanosleep(&gap, NULL);
}

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(int argc, char **argv) {
    const char *want = argc > 1 ? argv[1] : "left";
    uint32_t button;

    // The drag arguments, or the flag left off entirely.
    int dragging = 0;
    uint32_t x1 = 0, y1 = 0, x2 = 0, y2 = 0, extent_w = 0, extent_h = 0;
    int steps = 12;
    int hold_ms = 60;

    // Scanned rather than positional, so the optional `steps` before it stays
    // optional and every existing caller keeps its own argument order.
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--hold-ms") != 0)
            continue;
        if (i + 1 >= argc) {
            fprintf(stderr, "nested-click: --hold-ms wants a count in milliseconds\n");
            return 2;
        }
        hold_ms = atoi(argv[i + 1]);
        if (hold_ms < 0)
            hold_ms = 0;
        break;
    }

    if (argc > 2 && strcmp(argv[2], "--drag") == 0) {
        if (argc < 9) {
            fprintf(stderr, "nested-click: --drag wants x1 y1 x2 y2 w h [steps]\n");
            return 2;
        }
        dragging = 1;
        x1 = (uint32_t)strtoul(argv[3], NULL, 10);
        y1 = (uint32_t)strtoul(argv[4], NULL, 10);
        x2 = (uint32_t)strtoul(argv[5], NULL, 10);
        y2 = (uint32_t)strtoul(argv[6], NULL, 10);
        extent_w = (uint32_t)strtoul(argv[7], NULL, 10);
        extent_h = (uint32_t)strtoul(argv[8], NULL, 10);
        // `--hold-ms` may sit where `steps` would: a flag read as a step count
        // is `atoi("--hold-ms")` = 0, which is one teleport instead of twelve.
        if (argc > 9 && strncmp(argv[9], "--", 2) != 0)
            steps = atoi(argv[9]);
        if (steps < 1)
            steps = 1;
        if (extent_w == 0 || extent_h == 0) {
            fprintf(stderr, "nested-click: --drag needs non-zero output extents\n");
            return 2;
        }
    }

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

    // The cursor is put on the start point before the button goes down, so the
    // press is hit-tested where the caller aimed rather than wherever the
    // pointer happened to be left by the last run.
    if (dragging) {
        zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), x1, y1,
                                                extent_w, extent_h);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        settle(40);
    }

    // Press and release as two flushed batches with a real gap between them.
    // Sent together they are one arrival at the compositor, and a surface that
    // distinguishes a click from a press-and-hold — a long-press, a drag —
    // would see the wrong thing.
    zwlr_virtual_pointer_v1_button(pointer, now_ms(), button,
                                   WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);

    settle(30);

    // The travel. The final step lands exactly on (x2, y2) by construction —
    // it is not interpolated — because the whole value of absolute motion is
    // that the end point is the one that was asked for.
    if (dragging) {
        for (int i = 1; i <= steps; i++) {
            uint32_t x = (uint32_t)((long)x1 + ((long)x2 - (long)x1) * i / steps);
            uint32_t y = (uint32_t)((long)y1 + ((long)y2 - (long)y1) * i / steps);
            zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), x, y,
                                                    extent_w, extent_h);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            settle(12);
        }
        // A beat with the button still down at the destination: a surface that
        // commits on release reads the last position it was told about, and a
        // release in the same breath as the final motion can beat it there.
        // `--hold-ms` widens that beat into a window a caller can act inside.
        settle(hold_ms);
    }

    zwlr_virtual_pointer_v1_button(pointer, now_ms(), button,
                                   WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);

    zwlr_virtual_pointer_v1_destroy(pointer);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
