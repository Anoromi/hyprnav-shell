#!/usr/bin/env python3
"""Stand-in for a browser's tab host, for the grid's tab column and the
Ctrl+Tab switcher in the lab.

Announces itself in $HNS_TABS_DIR (default $XDG_RUNTIME_DIR/browser-tabs)
with a descriptor and a socket the way mynix's browser-tabs-host.py does,
serves a made-up snapshot there, prints every command it receives, and
applies the ones that change the tabs so the shell updates as it would. Run
several with different --browser/--pid for several browsers.

    scripts/fake-browser-tabs.py [--browser island] [--pid N] [--tabs N] [--legacy] [--no-navigate] [--firefox]

--pid names the browser process the shell looks for among Hyprland's
windows (default: this script's own pid, which has none, so window lookup
falls back to the browser's window class). --legacy also sends the old
extension's Essentials and groups until the shell acknowledges them.
--no-navigate plays an extension from before the navigate command.
--firefox reports each window's selected tab as accessed at the moment of
the snapshot, as Firefox and Zen do. A
{"type": "goto", "tabId", "url"} sent to the socket moves a tab as browsing
would.
"""

import argparse
import atexit
import base64
import json
import os
import signal
import socket
import threading
import time

SITES = [
    ("GitHub · Where software is built", "https://github.com/"),
    ("Hacker News", "https://news.ycombinator.com/"),
    ("NixOS Search - Packages", "https://search.nixos.org/packages"),
    ("Quickshell docs", "https://quickshell.org/docs/"),
    ("Rust std docs", "https://doc.rust-lang.org/std/"),
    ("MDN Web Docs", "https://developer.mozilla.org/"),
    ("Hyprland Wiki", "https://wiki.hypr.land/"),
    ("YouTube", "https://www.youtube.com/"),
    ("Wikipedia", "https://en.wikipedia.org/"),
    ("Stack Overflow", "https://stackoverflow.com/"),
]

COLORS = ["#5E6AD2", "#10A37F", "#EA4335", "#4285F4", "#F48024", "#24292F", "#FF6600", "#B7410E"]


def origin(url):
    return "/".join(url.split("/")[:3])


def fake_icon(site):
    """A coloured disc with the site's initial, as the data URL a real host sends."""
    name = site.split("//")[-1].removeprefix("www.")
    color = COLORS[sum(map(ord, name)) % len(COLORS)]
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="15" fill="{color}"/>'
           f'<text x="16" y="21.5" font-family="sans-serif" font-size="15" font-weight="bold" fill="white" text-anchor="middle">{name[0].upper()}</text></svg>')
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


class State:
    def __init__(self, extra, legacy, now, navigate=True, firefox=False):
        self.tabs = []
        self.navigate = navigate
        self.firefox = firefox
        self.next_id = 100
        self.legacy = legacy
        self.add("Inbox · Linear", "https://linear.app/inbox", accessed=now - 50)
        self.add("ChatGPT", "https://chatgpt.com/", accessed=now - 40)
        self.add("Attention Is All You Need", "https://arxiv.org/abs/1706.03762", accessed=now - 30)
        self.add("arXiv: Mixture of Experts", "https://arxiv.org/abs/2401.04088", accessed=now - 20)
        for i in range(extra):
            title, url = SITES[i % len(SITES)]
            self.add(title if i < len(SITES) else f"{title} ({i})", url, window=1 + (i % 2), accessed=now - 60 - i)
        # One active tab per window, the most recent one.
        for window in (1, 2):
            mine = [t for t in self.tabs if t["windowId"] == window]
            if mine:
                max(mine, key=lambda t: t["lastAccessed"])["active"] = True

    def add(self, title, url, window=1, accessed=0, active=False):
        tab = {"id": self.next_id, "windowId": window, "index": len(self.tabs), "title": title, "url": url,
               "icon": origin(url), "active": active, "audible": False, "pinned": False, "hidden": False,
               "lastAccessed": accessed}
        self.next_id += 1
        self.tabs.append(tab)
        return tab

    def activate(self, tab_id):
        tab = next((t for t in self.tabs if t["id"] == tab_id), None)
        if tab is None:
            return False
        for t in self.tabs:
            if t["windowId"] == tab["windowId"]:
                t["active"] = t is tab
        tab["lastAccessed"] = int(time.time() * 1000)
        return True

    def snapshot(self):
        windows = []
        for window in (1, 2):
            active = next((t for t in self.tabs if t["windowId"] == window and t["active"]), None)
            windows.append({"id": window, "focused": window == 1, "activeTitle": active["title"] if active else ""})
        icons = {t["icon"]: fake_icon(t["icon"]) for t in self.tabs}
        tabs = self.tabs
        if self.firefox:
            now = int(time.time() * 1000)
            tabs = [dict(t, lastAccessed=now) if t["active"] else t for t in tabs]
        snap = {"type": "snapshot", "windows": windows, "tabs": tabs, "icons": icons}
        if self.navigate:
            snap["caps"] = ["navigate"]
        if self.legacy:
            snap["legacy"] = {
                "nextId": 3,
                "essentials": [{"id": "e1", "title": "Linear", "url": "https://linear.app/", "icon": "", "tabId": 1},
                               {"id": "e2", "title": "Gmail", "url": "https://mail.google.com/", "icon": "", "tabId": None}],
                "groups": [{"id": "g1", "name": "Research", "members": [{"tabId": 7, "url": "https://arxiv.org/abs/1706.03762"},
                                                                       {"tabId": 8, "url": "https://arxiv.org/abs/2401.04088"}]}],
            }
        return snap

    def apply(self, cmd):
        kind = cmd.get("type")
        if kind == "activate":
            return self.activate(cmd.get("tabId"))
        if kind == "close":
            before = len(self.tabs)
            self.tabs = [t for t in self.tabs if t["id"] != cmd.get("tabId")]
            return len(self.tabs) != before
        if kind == "create":
            url = cmd.get("url") or ("https://duckduckgo.com/?q=" + cmd["search"] if cmd.get("search") else "about:blank")
            tab = self.add(cmd.get("search") or url, url, accessed=int(time.time() * 1000))
            return self.activate(tab["id"])
        # "goto" is the lab's own: the user browsing away, whatever the caps.
        if (kind == "navigate" and self.navigate) or kind == "goto":
            tab = next((t for t in self.tabs if t["id"] == cmd.get("tabId")), None)
            if tab is None:
                return False
            tab.update(url=cmd["url"], title=cmd["url"], icon=origin(cmd["url"]))
            return True
        if kind == "legacy-ack":
            self.legacy = False
            return True
        return kind == "refresh"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--browser", default="island")
    parser.add_argument("--pid", type=int, default=os.getpid(), help="browser pid to announce")
    parser.add_argument("--tabs", type=int, default=8, help="extra tabs")
    parser.add_argument("--legacy", action="store_true", help="also send an old-extension model")
    parser.add_argument("--no-navigate", action="store_true", help="no navigate command, as an old extension")
    parser.add_argument("--firefox", action="store_true", help="selected tabs read as accessed now, as in Firefox")
    args = parser.parse_args()
    directory = os.environ.get("HNS_TABS_DIR") or os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "browser-tabs")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    source = f"{args.browser}-{args.pid}"
    path = os.path.join(directory, source + ".sock")
    descriptor = os.path.join(directory, source + ".json")

    def cleanup():
        for p in (descriptor, path):
            try:
                os.unlink(p)
            except FileNotFoundError:
                pass

    atexit.register(cleanup)
    signal.signal(signal.SIGTERM, lambda *_: exit(0))
    if os.path.exists(path):
        os.unlink(path)
    # Distinct clocks per browser, so merged MRU interleaves them.
    state = State(args.tabs, args.legacy, int(time.time() * 1000) - (sum(map(ord, args.browser)) % 7) * 1000,
                  navigate=not args.no_navigate, firefox=args.firefox)
    clients = []
    lock = threading.Lock()

    def line():
        return (json.dumps(state.snapshot()) + "\n").encode()

    def serve(conn):
        with lock:
            conn.sendall(line())
        buf = b""
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                cmd = json.loads(raw)
                print(f"{source} command:", json.dumps(cmd), flush=True)
                with lock:
                    if state.apply(cmd):
                        for c in list(clients):
                            try:
                                c.sendall(line())
                            except OSError:
                                clients.remove(c)
        with lock:
            if conn in clients:
                clients.remove(conn)

    server = socket.socket(socket.AF_UNIX)
    server.bind(path)
    server.listen(4)
    tmp = descriptor + ".tmp"
    with open(tmp, "w") as out:
        json.dump({"id": source, "browser": args.browser, "browserPid": args.pid, "hostPid": os.getpid(), "socket": path}, out)
    os.replace(tmp, descriptor)
    print("serving", path, flush=True)
    while True:
        conn, _ = server.accept()
        with lock:
            clients.append(conn)
        threading.Thread(target=serve, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
