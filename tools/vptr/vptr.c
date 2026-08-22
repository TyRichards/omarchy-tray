// Minimal wlr-virtual-pointer driver for scripted drags.
// Reads commands from stdin, one per line:
//   press | release   left mouse button down / up
//   move DX DY        relative motion (logical pixels, floats ok)
//   sleep MS          pause
// Keeps one virtual pointer device alive for the whole script so a held
// button and the motion under it belong to the same device.
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

#define BTN_LEFT 0x110

static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct wl_seat *seat;

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void registry_global(void *data, struct wl_registry *registry,
    uint32_t name, const char *interface, uint32_t version) {
  (void)data;
  if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
    uint32_t v = version < 2 ? version : 2;
    manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, v);
  } else if (strcmp(interface, wl_seat_interface.name) == 0 && !seat) {
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data; (void)registry; (void)name;
}

static const struct wl_registry_listener registry_listener = {
  .global = registry_global,
  .global_remove = registry_global_remove,
};

int main(void) {
  struct wl_display *display = wl_display_connect(NULL);
  if (!display) { fprintf(stderr, "no wayland display\n"); return 1; }

  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  if (!manager) { fprintf(stderr, "compositor lacks zwlr_virtual_pointer_manager_v1\n"); return 1; }

  struct zwlr_virtual_pointer_v1 *pointer =
    zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
  wl_display_roundtrip(display);

  char line[256];
  while (fgets(line, sizeof line, stdin)) {
    double dx, dy, ex, ey;
    int ms;
    if (strncmp(line, "press", 5) == 0) {
      zwlr_virtual_pointer_v1_button(pointer, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
      zwlr_virtual_pointer_v1_frame(pointer);
    } else if (strncmp(line, "release", 7) == 0) {
      zwlr_virtual_pointer_v1_button(pointer, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
      zwlr_virtual_pointer_v1_frame(pointer);
    } else if (sscanf(line, "move %lf %lf", &dx, &dy) == 2) {
      zwlr_virtual_pointer_v1_motion(pointer, now_ms(),
        wl_fixed_from_double(dx), wl_fixed_from_double(dy));
      zwlr_virtual_pointer_v1_frame(pointer);
    } else if (sscanf(line, "abs %lf %lf %lf %lf", &dx, &dy, &ex, &ey) == 4) {
      zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(),
        (uint32_t)dx, (uint32_t)dy, (uint32_t)ex, (uint32_t)ey);
      zwlr_virtual_pointer_v1_frame(pointer);
    } else if (sscanf(line, "sleep %d", &ms) == 1) {
      wl_display_roundtrip(display);
      struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
      nanosleep(&ts, NULL);
      continue;
    } else if (line[0] == '\n' || line[0] == '#') {
      continue;
    } else {
      fprintf(stderr, "unknown command: %s", line);
      continue;
    }
    wl_display_roundtrip(display);
  }

  zwlr_virtual_pointer_v1_destroy(pointer);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  return 0;
}
