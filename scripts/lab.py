#!/usr/bin/env python3
"""Disposable compositor for developing and recording hyprnav-shell.

Cage (headless wlroots) hosts a nested Hyprland with a headless TEST output at
1920x1080. The nested session has its own runtime dir, D-Bus, hyprnav daemon
and state, so nothing touches the live desktop. Commands:

  lab.py up        start everything and print the env file
  lab.py down      stop everything
  lab.py env       print `export` lines for the nested session
  lab.py exec CMD  run CMD inside the nested session
  lab.py audio     start a private PipeWire + WirePlumber with one null sink
                   inside the lab, so volume checks never touch the host
"""
import json, os, shlex, signal, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAB = ROOT / "lab"
LAB.mkdir(exist_ok=True)
TOOLS = ROOT / "lab-tools/result/bin"   # built by: nix-build lab-tools -o lab-tools/result
CAGE = TOOLS / "cage"
PIDS = LAB / "pids.json"
ENVF = LAB / "env.json"
OUTPUT = "TEST"

def load_env():
    return json.loads(ENVF.read_text())

def launch(name, args, env, procs):
    p = subprocess.Popen(args, env=env, stdout=(LAB / f"{name}.log").open("w"),
                         stderr=subprocess.STDOUT, start_new_session=True)
    procs[name] = p.pid
    PIDS.write_text(json.dumps(procs, indent=2))
    return p

def wait(check, p, what, tries=150):
    for _ in range(tries):
        if check():
            return
        if p.poll() is not None:
            raise RuntimeError(f"{what}: process exited, see lab/*.log")
        time.sleep(0.1)
    raise RuntimeError(f"{what}: timeout")

def up():
    if not CAGE.exists():
        raise SystemExit("lab tools missing: run  nix-build lab-tools -o lab-tools/result")
    if PIDS.exists():
        down()
    runtime = Path(tempfile.mkdtemp(prefix="hns-lab-"))
    env = {k: os.environ[k] for k in ("PATH", "XDG_DATA_DIRS", "LD_LIBRARY_PATH", "HOME", "USER", "LANG", "SHELL", "TERM") if k in os.environ}
    env.update(
        XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(LAB / "config"),
        XDG_STATE_HOME=str(LAB / "state"), XDG_CACHE_HOME=str(LAB / "cache"),
        HYPRLAND_NO_SD_VARS="1", LIBSEAT_BACKEND="hns-disabled",
        AQ_DRM_DEVICES="/nonexistent-hns-device",
        WLR_BACKENDS="headless", WLR_RENDERER="gles2", WLR_HEADLESS_OUTPUTS="1",
        GDK_BACKEND="wayland", QT_QPA_PLATFORM="wayland", MOZ_ENABLE_WAYLAND="1",
        XCURSOR_THEME="Adwaita", XCURSOR_SIZE="24", HNS_SCREEN=OUTPUT,
        PIPEWIRE_RUNTIME_DIR=os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000"),
        PULSE_RUNTIME_PATH=os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000") + "/pulse",
    )
    for d in ("config", "state", "cache"):
        (LAB / d).mkdir(exist_ok=True)
    procs = {}
    cage = launch("cage", [str(CAGE), "-s", "--", "sleep", "7200"], env, procs)
    wait(lambda: bool(list(runtime.glob("wayland-*.lock"))), cage, "cage")
    parent = next(runtime.glob("wayland-*.lock")).name.removesuffix(".lock")
    bus = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"], env=env,
                           stdout=subprocess.PIPE, stderr=(LAB / "dbus.log").open("w"), text=True, start_new_session=True)
    procs["dbus"] = bus.pid
    env["DBUS_SESSION_BUS_ADDRESS"] = bus.stdout.readline().strip()
    env["WAYLAND_DISPLAY"] = parent
    (LAB / "config/hypr").mkdir(parents=True, exist_ok=True)
    # Lua config, like the user's live session: hyprnav's daemon dispatches
    # Lua-style calls (hl.dsp.focus), which a hyprlang config rejects.
    conf = LAB / "config/hypr/hyprland.lua"
    conf.write_text(f"""
hl.monitor({{ output = "", mode = "1280x720@60", position = "0x0", scale = 1 }})
hl.monitor({{ output = "{OUTPUT}", mode = "1920x1080@60", position = "0x0", scale = 1 }})
hl.monitor({{ output = "WAYLAND-1", disabled = true }})
hl.config({{
    general = {{
        gaps_in = 4, gaps_out = 8, border_size = 1,
        col = {{ active_border = "rgba(EDE6DAcc)", inactive_border = "rgba(3A3733aa)" }},
        layout = "dwindle",
    }},
    decoration = {{ rounding = 4, blur = {{ enabled = false }}, shadow = {{ enabled = false }} }},
    animations = {{ enabled = true }},
    misc = {{ disable_hyprland_logo = true, disable_splash_rendering = true, background_color = 0x1A1917, enable_anr_dialog = false }},
    cursor = {{ inactive_timeout = 1 }},
    xwayland = {{ enabled = false }},
    debug = {{ suppress_errors = true }},
}})
-- The live session's fade speed, so layer surfaces that map and unmap get
-- the same compositor fade here as there.
hl.animation({{ leaf = "fade", enabled = true, speed = 7, bezier = "default" }})
-- The shell's keys, as in the live session (see scripts/bindings.example.lua).
hl.bind("SUPER + Tab", hl.dsp.global("hyprnav-shell:switcher-open"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("hyprnav-shell:switcher-back"))
hl.bind("SUPER + A", hl.dsp.global("hyprnav-shell:grid-toggle"))
for _, key in ipairs({{ "Super_L", "Super_R" }}) do
    hl.bind(key, hl.dsp.global("hyprnav-shell:switcher-commit"), {{ release = true, non_consuming = true, transparent = true }})
    hl.bind("SUPER + " .. key, hl.dsp.global("hyprnav-shell:switcher-commit"), {{ release = true, non_consuming = true, transparent = true }})
end
hl.layer_rule({{
    name = "hyprnav-shell-no-animation",
    match = {{ namespace = "^hyprnav-shell-.*$" }},
    no_anim = true,
}})
hl.window_rule({{
    name = "approval-floats",
    match = {{ title = "^Approval needed$" }},
    float = true,
    center = true,
    size = "620 320",
}})
""")
    old = {x.name for x in (runtime / "hypr").glob("*")} if (runtime / "hypr").exists() else set()
    hl = launch("hyprland", ["Hyprland", "--config", str(conf)], env, procs)
    def new_socket():
        return [x for x in (runtime / "hypr").glob("*/.socket.sock") if x.parent.name not in old] if (runtime / "hypr").exists() else []
    wait(lambda: bool(new_socket()), hl, "hyprland")
    env["HYPRLAND_INSTANCE_SIGNATURE"] = new_socket()[0].parent.name
    time.sleep(0.5)
    socks = [x for x in runtime.glob("wayland-*") if not x.name.endswith(".lock") and x.name != parent]
    assert len(socks) == 1, socks
    env["WAYLAND_DISPLAY"] = socks[0].name
    def hc(*a, tries=30):
        for i in range(tries):
            r = subprocess.run(["hyprctl", *a], env=env, capture_output=True, text=True)
            if r.returncode == 0 and "Couldn't connect" not in r.stdout:
                return r.stdout
            time.sleep(0.3)
        raise RuntimeError(f"hyprctl {a}: {r.stdout} {r.stderr}")
    hc("version")
    hc("output", "create", "headless", OUTPUT)
    time.sleep(0.6)
    hc("dispatch", f'hl.dsp.focus({{ monitor = "{OUTPUT}" }})')
    hyprnav_bin = os.environ.get("HNS_HYPRNAV_BIN", "hyprnav")
    if hyprnav_bin != "hyprnav":
        env["PATH"] = str(Path(hyprnav_bin).resolve().parent) + ":" + env["PATH"]
    ENVF.write_text(json.dumps(env, indent=2)); os.chmod(ENVF, 0o600)
    # Virtual keyboard and pointer so layer surfaces can receive keyboard focus
    # and wtype can inject keys.
    launch("seat", [str(TOOLS / "hns-lab-seat")], env, procs)
    # Optional dev builds: HNS_HYPRNAV_BIN points at a hyprnav binary,
    # HNS_PLUGIN_SO at a hyprnav-plugin .so to load into the nested compositor.
    plugin_so = os.environ.get("HNS_PLUGIN_SO")
    if plugin_so:
        print(hc("plugin", "load", plugin_so).strip())
    for extra in filter(None, os.environ.get("HNS_EXTRA_PLUGIN_SO", "").split(":")):
        print(hc("plugin", "load", extra).strip())
    # Portals inside the lab session: xdg-desktop-portal with the Hyprland
    # backend, and hyprnav's picker so screen shares never show a dialog.
    if os.environ.get("HNS_PORTALS", "1") == "1":
        xdp = os.environ.get("HNS_XDP_DIR", "/nix/store/hwfl4n2p049q0pa2gzsrjfiqlgf6cbny-xdg-desktop-portal-1.22.1")
        xdph = os.environ.get("HNS_XDPH_DIR", "/nix/store/0w9vhwzwdbs65drq15v826a8bv77qxr2-xdg-desktop-portal-hyprland-1.4.1")
        picker = os.environ.get("HNS_SHARE_PICKER", str(Path.home() / "code/stolen/hyprland-plugins/scripts/hyprnav-share-picker"))
        cfg = LAB / "config"
        (cfg / "xdg-desktop-portal").mkdir(parents=True, exist_ok=True)
        (cfg / "xdg-desktop-portal/portals.conf").write_text("[preferred]\ndefault=hyprland\n")
        (cfg / "hypr").mkdir(parents=True, exist_ok=True)
        (cfg / "hypr/xdph.conf").write_text(f"screencopy {{\n    custom_picker_binary = {picker}\n    allow_token_by_default = 1\n}}\n")
        penv = dict(env, XDG_CURRENT_DESKTOP="Hyprland", XDG_SESSION_TYPE="wayland",
                    XDG_DESKTOP_PORTAL_DIR=f"{xdph}/share/xdg-desktop-portal/portals",
                    PATH=f"{xdph}/bin:" + env["PATH"])
        launch("xdph", [f"{xdph}/libexec/xdg-desktop-portal-hyprland"], penv, procs)
        time.sleep(0.5)
        launch("xdp", [f"{xdp}/libexec/xdg-desktop-portal", "--verbose"], penv, procs)
        env["XDG_CURRENT_DESKTOP"] = "Hyprland"
        env["PATH"] = f"{xdph}/bin:" + env["PATH"]
    nav = launch("hyprnav", [hyprnav_bin, "daemon"], env, procs)
    time.sleep(0.8)
    print(json.dumps({"runtime": str(runtime), "instance": env["HYPRLAND_INSTANCE_SIGNATURE"], "pids": procs}, indent=2))
    print(hc("monitors"))

def audio():
    """Private PipeWire for the lab: no ALSA, Bluetooth or camera monitors, one
    null sink named "Lab speakers". Rewrites env.json so later lab commands and
    the shell talk to it instead of the host's PipeWire."""
    env = load_env()
    runtime = env["XDG_RUNTIME_DIR"]
    procs = json.loads(PIDS.read_text())
    if "pipewire" in procs:
        try:
            os.kill(procs["pipewire"], 0); print("lab audio already running"); return
        except ProcessLookupError:
            pass
    cfg = LAB / "config"
    (cfg / "pipewire/pipewire.conf.d").mkdir(parents=True, exist_ok=True)
    (cfg / "pipewire/pipewire.conf.d/lab-sink.conf").write_text("""context.objects = [
  { factory = adapter
    args = {
      factory.name = support.null-audio-sink
      node.name = "lab-speakers"
      node.description = "Lab speakers"
      media.class = Audio/Sink
      audio.position = [ FL FR ]
      monitor.channel-volumes = true
    }
  }
]
""")
    (cfg / "wireplumber/wireplumber.conf.d").mkdir(parents=True, exist_ok=True)
    (cfg / "wireplumber/wireplumber.conf.d/lab.conf").write_text("""wireplumber.profiles = {
  main = {
    monitor.alsa = disabled
    monitor.alsa-midi = disabled
    monitor.bluez = disabled
    monitor.bluez.midi = disabled
    monitor.v4l2 = disabled
    monitor.libcamera = disabled
  }
}
""")
    env["PIPEWIRE_RUNTIME_DIR"] = runtime
    env["PULSE_RUNTIME_PATH"] = runtime + "/pulse"
    pw = launch("pipewire", ["pipewire"], env, procs)
    wait(lambda: Path(runtime, "pipewire-0").exists(), pw, "pipewire")
    launch("wireplumber", ["wireplumber"], env, procs)
    ENVF.write_text(json.dumps(env, indent=2)); os.chmod(ENVF, 0o600)
    time.sleep(1.5)
    print(subprocess.run(["wpctl", "status"], env=env, capture_output=True, text=True).stdout)

def down():
    if not PIDS.exists():
        print("not running"); return
    procs = json.loads(PIDS.read_text())
    for name, pid in reversed(list(procs.items())):
        try:
            os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for name, pid in procs.items():
        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    PIDS.unlink()
    print("stopped")

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "up"
    if cmd == "up": up()
    elif cmd == "down": down()
    elif cmd == "env":
        for k, v in load_env().items(): print(f"export {k}={shlex.quote(v)}")
    elif cmd == "audio": audio()
    elif cmd == "exec":
        os.execvpe(sys.argv[2], sys.argv[2:], load_env())
    else:
        print(__doc__)

if __name__ == "__main__":
    main()
