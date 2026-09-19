#define _GNU_SOURCE
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "keyboard.h"
#include "pointer.h"
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *km;
static struct zwlr_virtual_pointer_manager_v1 *pm;
static void global(void *data, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
 if (!strcmp(iface,"wl_seat")) seat=wl_registry_bind(r,name,&wl_seat_interface,1);
 if (!strcmp(iface,"zwp_virtual_keyboard_manager_v1")) km=wl_registry_bind(r,name,&zwp_virtual_keyboard_manager_v1_interface,1);
 if (!strcmp(iface,"zwlr_virtual_pointer_manager_v1")) pm=wl_registry_bind(r,name,&zwlr_virtual_pointer_manager_v1_interface,1);
}
static void removed(void *data,struct wl_registry *r,uint32_t name) {}
static const struct wl_registry_listener listener={global,removed};
int main(void) {
 struct wl_display *d=wl_display_connect(NULL); if(!d)return 1;
 struct wl_registry *r=wl_display_get_registry(d);wl_registry_add_listener(r,&listener,NULL);wl_display_roundtrip(d);
 if(!seat||!km||!pm){fprintf(stderr,"Missing virtual input protocols\n");return 2;}
 struct zwp_virtual_keyboard_v1 *k=zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(km,seat);
 struct xkb_context *ctx=xkb_context_new(XKB_CONTEXT_NO_FLAGS);
 struct xkb_rule_names names={.layout="us"};
 struct xkb_keymap *map=xkb_keymap_new_from_names(ctx,&names,XKB_KEYMAP_COMPILE_NO_FLAGS);
 if(!map)return 3;
 char *text=xkb_keymap_get_as_string(map,XKB_KEYMAP_FORMAT_TEXT_V1);size_t n=strlen(text)+1;
 int fd=memfd_create("hypr-use-keymap",MFD_CLOEXEC);if(fd<0||write(fd,text,n)!=(ssize_t)n)return 4;
 zwp_virtual_keyboard_v1_keymap(k,WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1,fd,n);
 zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pm,seat);
 wl_display_roundtrip(d);close(fd);free(text);xkb_keymap_unref(map);xkb_context_unref(ctx);
 // Keep devices connected. All actual input is sent by Portal, not this helper.
 while(wl_display_dispatch(d)>=0){}
 return 0;
}
