#!/usr/bin/env python3
"""Demo "agent worker" for the hard-sticking video.

A large window that pretends to be a background agent. It works for N
seconds with a visible countdown, then opens an approval dialog, exactly the
kind of window that lands on the user's workspace without sticking. After
the dialog is answered it goes back to work and asks again.

    agent-demo-app.py [--delay 10] [--name planner] [--transient]

--transient sets the dialog's parent (the well-behaved case). Without it the
dialog is a plain new toplevel, which is what portals and many apps do.
"""
import argparse, sys, gi
gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gdk

ap = argparse.ArgumentParser()
ap.add_argument("--delay", type=int, default=10)
ap.add_argument("--name", default="planner")
ap.add_argument("--transient", action="store_true")
ap.add_argument("--repeat", action="store_true")
args = ap.parse_args()

CSS = b"""
window { background: #1A1917; color: #EDE6DA; }
.title { font-size: 34px; font-weight: 700; }
.big { font-size: 96px; font-weight: 700; font-family: monospace; color: #F2C14E; }
.muted { font-size: 18px; color: #9A938A; }
.log { font-family: monospace; font-size: 15px; color: #C9C2B6; }
.dialog { background: #262421; }
.dialog .title { font-size: 26px; }
button { font-size: 18px; padding: 10px 26px; }
button.suggested-action { background: #F2C14E; color: #1A1917; }
progressbar trough { min-height: 10px; } progressbar progress { min-height: 10px; background: #F2C14E; }
"""

class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=f"dev.hyprnav.demo.agent.{args.name}")
        self.remaining = args.delay
        self.round = 0

    def do_activate(self):
        prov = Gtk.CssProvider(); prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), prov, 800)
        self.win = Gtk.ApplicationWindow(application=self, title=f"Agent: {args.name}")
        self.win.set_default_size(900, 620)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_top=40, margin_bottom=40, margin_start=48, margin_end=48)
        self.win.set_child(box)
        t = Gtk.Label(label=f"Background agent “{args.name}”", xalign=0); t.add_css_class("title"); box.append(t)
        s = Gtk.Label(label="Working in its own workspace. It will need your approval soon.", xalign=0); s.add_css_class("muted"); box.append(s)
        self.count = Gtk.Label(label=str(self.remaining)); self.count.add_css_class("big"); box.append(self.count)
        self.sub = Gtk.Label(label="seconds until the agent opens an approval dialog", xalign=0.5); self.sub.add_css_class("muted"); box.append(self.sub)
        self.bar = Gtk.ProgressBar(); box.append(self.bar)
        self.log = Gtk.Label(label="", xalign=0, wrap=True); self.log.add_css_class("log"); box.append(self.log)
        self.win.present()
        self.say("reading repository")
        GLib.timeout_add(1000, self.tick)

    def say(self, msg):
        lines = (self.log.get_label().split("\n") + [f"› {msg}"])[-6:]
        self.log.set_label("\n".join(l for l in lines if l))

    def tick(self):
        self.remaining -= 1
        self.count.set_label(str(max(0, self.remaining)))
        self.bar.set_fraction(1 - self.remaining / args.delay)
        if self.remaining in (7, 4, 2):
            self.say({7: "editing src/server.rs", 4: "running tests: 12 passed", 2: "change touches 3 files, needs review"}[self.remaining])
        if self.remaining <= 0:
            self.ask()
            return False
        return True

    def ask(self):
        self.round += 1
        self.count.set_label("?"); self.sub.set_label("waiting for your approval")
        self.say("opened approval dialog")
        d = Gtk.Window(title="Approval needed"); d.add_css_class("dialog")
        d.set_default_size(560, 300)
        if args.transient:
            d.set_transient_for(self.win); d.set_modal(True)
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin_top=32, margin_bottom=32, margin_start=36, margin_end=36)
        d.set_child(b)
        h = Gtk.Label(label="Apply 3 file changes?", xalign=0); h.add_css_class("title"); b.append(h)
        m = Gtk.Label(label=f"Agent “{args.name}” wants to write src/server.rs, src/protocol.rs and tests/inherit.rs.", xalign=0, wrap=True); m.add_css_class("muted"); b.append(m)
        row = Gtk.Box(spacing=12, halign=Gtk.Align.END, valign=Gtk.Align.END, vexpand=True); b.append(row)
        deny = Gtk.Button(label="Deny", can_focus=False); ok = Gtk.Button(label="Approve", can_focus=False); ok.add_css_class("suggested-action")
        row.append(deny); row.append(ok)
        def done(_b, what):
            d.close(); self.say(f"{what}, continuing")
            self.count.set_label(str(args.delay)); self.sub.set_label("seconds until the agent opens an approval dialog")
            self.remaining = args.delay; self.bar.set_fraction(0)
            if args.repeat: GLib.timeout_add(1000, self.tick)
        deny.connect("clicked", done, "denied"); ok.connect("clicked", done, "approved")
        # Enter approves, Escape denies. No button holds focus, so stray typing
        # that lands in this dialog (the whole point of the demo) does nothing.
        ctl = Gtk.ShortcutController(); ctl.set_scope(Gtk.ShortcutScope.GLOBAL)
        ctl.add_shortcut(Gtk.Shortcut(trigger=Gtk.ShortcutTrigger.parse_string("Return|KP_Enter"), action=Gtk.CallbackAction.new(lambda *_: (done(None, "approved"), True)[1])))
        ctl.add_shortcut(Gtk.Shortcut(trigger=Gtk.ShortcutTrigger.parse_string("Escape"), action=Gtk.CallbackAction.new(lambda *_: (done(None, "denied"), True)[1])))
        d.add_controller(ctl)
        d.present()

App().run([])
