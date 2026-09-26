#!/usr/bin/env python3
"""A StatusNotifierItem with a dbusmenu, for checking the bar's tray.

Run inside the lab with the lab-tools Python (it has GObject introspection):
  scripts/lab.py exec lab-tools/result/bin/python3 scripts/tray-test.py

It draws its own icon (a pencil-yellow ring), registers with the watcher the
shell provides, and prints every call it receives, one line each:
  activate x y | secondary x y | scroll delta orientation | menu <id> <label>
Menu: "Say hello" (sends a notification), a check item, a separator, "Quit".
Scrolling toggles the NeedsAttention status, so the bar's dot can be seen.
"""
import os, sys, subprocess
from gi.repository import Gio, GLib

SNI_XML = """<node><interface name="org.kde.StatusNotifierItem">
<property name="Category" type="s" access="read"/><property name="Id" type="s" access="read"/>
<property name="Title" type="s" access="read"/><property name="Status" type="s" access="read"/>
<property name="IconName" type="s" access="read"/><property name="IconPixmap" type="a(iiay)" access="read"/>
<property name="ToolTip" type="(sa(iiay)ss)" access="read"/><property name="ItemIsMenu" type="b" access="read"/>
<property name="Menu" type="o" access="read"/>
<method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
<method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
<signal name="NewStatus"><arg type="s"/></signal><signal name="NewIcon"/><signal name="NewTitle"/>
</interface></node>"""

MENU_XML = """<node><interface name="com.canonical.dbusmenu">
<property name="Version" type="u" access="read"/><property name="TextDirection" type="s" access="read"/>
<property name="Status" type="s" access="read"/><property name="IconThemePath" type="as" access="read"/>
<method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/>
  <arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
<method name="GetGroupProperties"><arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/></method>
<method name="GetProperty"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
<method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/></method>
<method name="EventGroup"><arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/></method>
<method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
<method name="AboutToShowGroup"><arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/></method>
<signal name="ItemsPropertiesUpdated"><arg type="a(ia{sv})"/><arg type="a(ias)"/></signal>
<signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
</interface></node>"""

state = {"status": "Active", "checked": False, "rev": 1}
loop = GLib.MainLoop()


def say(*a):
    print(*a, flush=True)


def pixmap(size):
    """A ring in Pencil (#F2C14E) on transparent, ARGB32 big-endian."""
    out = bytearray()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            on = size * 0.26 <= d <= size * 0.46
            out += bytes([255, 0xF2, 0xC1, 0x4E]) if on else bytes(4)
    return (size, size, bytes(out))


ICON = [pixmap(22), pixmap(44)]


def items():
    return [
        (1, {"label": GLib.Variant("s", "Say hello")}),
        (2, {"label": GLib.Variant("s", "Keep it checked"), "toggle-type": GLib.Variant("s", "checkmark"),
             "toggle-state": GLib.Variant("i", 1 if state["checked"] else 0)}),
        (3, {"type": GLib.Variant("s", "separator")}),
        (4, {"label": GLib.Variant("s", "Quit")}),
    ]


def sni_prop(conn, sender, path, iface, name):
    return {
        "Category": GLib.Variant("s", "ApplicationStatus"),
        "Id": GLib.Variant("s", "hns-tray-test"),
        "Title": GLib.Variant("s", "Tray test"),
        "Status": GLib.Variant("s", state["status"]),
        "IconName": GLib.Variant("s", ""),
        "IconPixmap": GLib.Variant("a(iiay)", ICON),
        "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], "Tray test", "A test StatusNotifierItem")),
        "ItemIsMenu": GLib.Variant("b", False),
        "Menu": GLib.Variant("o", "/Menu"),
    }[name]


def sni_call(conn, sender, path, iface, method, params, inv):
    if method == "Activate":
        say("activate", *params.unpack())
    elif method == "SecondaryActivate":
        say("secondary", *params.unpack())
    elif method == "ContextMenu":
        say("contextmenu", *params.unpack())
    elif method == "Scroll":
        say("scroll", *params.unpack())
        state["status"] = "NeedsAttention" if state["status"] == "Active" else "Active"
        conn.emit_signal(None, "/StatusNotifierItem", "org.kde.StatusNotifierItem", "NewStatus",
                         GLib.Variant("(s)", (state["status"],)))
    inv.return_value(None)


def menu_prop(conn, sender, path, iface, name):
    return {
        "Version": GLib.Variant("u", 3), "TextDirection": GLib.Variant("s", "ltr"),
        "Status": GLib.Variant("s", "normal"), "IconThemePath": GLib.Variant("as", []),
    }[name]


def menu_call(conn, sender, path, iface, method, params, inv):
    if method == "GetLayout":
        children = [GLib.Variant("(ia{sv}av)", (i, p, [])) for i, p in items()]
        root = (0, {"children-display": GLib.Variant("s", "submenu")}, children)
        inv.return_value(GLib.Variant("(u(ia{sv}av))", (state["rev"], root)))
    elif method == "GetGroupProperties":
        ids = params.unpack()[0]
        inv.return_value(GLib.Variant("(a(ia{sv}))", ([(i, p) for i, p in items() if not ids or i in ids],)))
    elif method == "GetProperty":
        i, name = params.unpack()
        p = dict(items()).get(i, {})
        inv.return_value(GLib.Variant("(v)", (p.get(name, GLib.Variant("s", "")),)))
    elif method == "Event":
        i, ev, _data, _ts = params.unpack()
        if ev == "clicked":
            label = dict(items())[i].get("label")
            say("menu", i, label.unpack() if label else "")
            if i == 1:
                subprocess.Popen(["notify-send", "-a", "Tray test", "Hello from the tray", "Menu item clicked"])
            elif i == 2:
                state["checked"] = not state["checked"]; state["rev"] += 1
                conn.emit_signal(None, "/Menu", "com.canonical.dbusmenu", "LayoutUpdated",
                                 GLib.Variant("(ui)", (state["rev"], 0)))
            elif i == 4:
                GLib.idle_add(loop.quit)
        inv.return_value(None)
    elif method == "EventGroup":
        inv.return_value(GLib.Variant("(ai)", ([],)))
    elif method == "AboutToShow":
        inv.return_value(GLib.Variant("(b)", (False,)))
    elif method == "AboutToShowGroup":
        inv.return_value(GLib.Variant("(aiai)", ([], [])))


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
    sni = Gio.DBusNodeInfo.new_for_xml(SNI_XML).interfaces[0]
    menu = Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0]
    bus.register_object("/StatusNotifierItem", sni, sni_call, sni_prop, None)
    bus.register_object("/Menu", menu, menu_call, menu_prop, None)
    Gio.bus_own_name_on_connection(bus, name, Gio.BusNameOwnerFlags.NONE, None, None)

    # Register with every watcher that appears, so a shell restart finds us again.
    def appeared(conn, _name, _owner):
        conn.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                       "RegisterStatusNotifierItem", GLib.Variant("(s)", (name,)), None, Gio.DBusCallFlags.NONE, 2000, None)
        say("registered", name)
    Gio.bus_watch_name_on_connection(bus, "org.kde.StatusNotifierWatcher", Gio.BusNameWatcherFlags.NONE, appeared, None)
    loop.run()


if __name__ == "__main__":
    sys.exit(main())
