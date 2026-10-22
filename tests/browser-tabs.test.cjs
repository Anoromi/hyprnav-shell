// node --test tests/
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// QML `.pragma library` scripts: plain JS once the pragma line is gone.
function load(file, names) {
  const source = fs.readFileSync(path.join(__dirname, "../shell", file), "utf8").replace(/^\.pragma library\s*$/m, "");
  return new Function(`${source}; return { ${names.join(", ")} };`)();
}
const M = load("tabs/model.js", ["CLASSES", "emptyModel", "normalize", "importLegacy", "relink", "claimOpened", "removeEntry",
  "dropClosed", "pin", "pinTab", "assign", "moveEntry", "merge", "resolveWindow", "windowForClient", "interpretInput"]);
const R = load("tabs/mru.js", ["recency", "order", "stamp"]);
const S = load("tabswitch/tabswitch.js", ["start", "step"]);

function source(id, browser, browserPid, tabs, windows) {
  return { id, browser, browserPid, snapshot: { windows: windows || [{ id: 1, focused: true, activeTitle: "" }], tabs, icons: {} } };
}
function tab(id, url, extra = {}) {
  return { id, windowId: 1, index: id, title: `t${id}`, url, active: false, lastAccessed: 0, ...extra };
}

test("merge keys tabs and windows by source and keeps the raw ids", () => {
  const merged = M.merge(M.emptyModel(), [
    source("island-1", "island", 1, [tab(5, "https://a.test/")]),
    source("zen-2", "zen", 2, [tab(5, "https://b.test/", { windowId: 3 })], [{ id: 3, focused: false, activeTitle: "t5" }]),
  ]);
  assert.deepEqual(merged.tabs.map((t) => [t.id, t.rawId, t.windowId, t.browser]),
    [["island-1/5", 5, "island-1/1", "island"], ["zen-2/5", 5, "zen-2/3", "zen"]]);
  assert.deepEqual(merged.windows.map((w) => w.id), ["island-1/1", "zen-2/3"]);
  assert.deepEqual(merged.browsers, ["island", "zen"]);
});

test("essentials and groups claim tabs in their own browser and relink by URL", () => {
  const model = M.normalize({
    nextId: 5,
    essentials: [{ id: "e1", title: "Linear", url: "https://linear.app/", browser: "zen", tabKey: "zen-9/1", tabUrl: "https://linear.app/team?x=1" }],
    groups: [{ id: "g1", name: "Research", members: [{ id: "m2", title: "Paper", url: "https://arxiv.org/x", browser: "island", tabKey: "island-9/4", tabUrl: "https://arxiv.org/x" }] }],
  });
  // After a restart: new sources, new ids. The Island tab on linear.app is
  // not the Zen essential's.
  const sources = [
    source("island-1", "island", 1, [tab(7, "https://linear.app/inbox"), tab(8, "https://arxiv.org/x")]),
    source("zen-2", "zen", 2, [tab(3, "https://linear.app/team")]),
  ];
  const tabs = M.merge(model, sources).tabs;
  assert.equal(M.relink(model, tabs), true);
  assert.equal(model.essentials[0].tabKey, "zen-2/3");
  assert.equal(model.groups[0].members[0].tabKey, "island-1/8");
  assert.equal(model.essentials[0].tabUrl, "https://linear.app/team");
  assert.equal(M.relink(model, tabs), false);
  const merged = M.merge(model, sources);
  assert.deepEqual(merged.tabs.map((t) => [t.id, t.entry, t.essential, t.group]),
    [["island-1/7", null, null, null], ["island-1/8", "m2", null, "g1"], ["zen-2/3", "e1", "e1", null]]);
  assert.deepEqual(merged.groups[0].members.map((m) => m.tabId), ["island-1/8"]);
  assert.equal(merged.essentials[0].tabId, "zen-2/3");
});

test("pinning and assigning move a tab between essentials, pinned tabs and groups", () => {
  const model = M.emptyModel();
  const t = { id: "island-1/3", browser: "island", url: "https://chatgpt.com/", title: "ChatGPT", icon: "https://chatgpt.com" };
  M.assign(model, t, "Research");
  M.assign(model, t, " research ");
  assert.equal(model.groups.length, 1, "group names match case-insensitively");
  assert.deepEqual(model.groups[0].members.map((m) => [m.title, m.url, m.browser, m.tabKey]), [["ChatGPT", "https://chatgpt.com/", "island", "island-1/3"]]);
  M.pinTab(model, t);
  assert.deepEqual(model.pinned.map((e) => e.tabKey), ["island-1/3"]);
  assert.equal(model.groups.length, 0, "a group goes with its last member");
  M.pin(model, t);
  assert.equal(model.essentials[0].browser, "island");
  assert.equal(model.pinned.length, 0, "pinning to Essentials takes it from the Pinned rows");
  M.assign(model, t, "Other");
  assert.equal(model.essentials[0].tabKey, null, "assigning takes the tab from its essential");
  const id = model.groups[0].members[0].id;
  assert.equal(M.moveEntry(model, id, null), true);
  assert.deepEqual([model.pinned[0].id, model.groups.length], [id, 0], "a member moves to Pinned as itself");
  assert.equal(M.moveEntry(model, model.essentials[0].id, "x"), false, "essentials do not move");
  assert.equal(M.removeEntry(model, id).id, id);
  assert.equal(model.pinned.length, 0);
});

test("an essential outlives its tab and opens a new one, which it then keeps", () => {
  const model = M.normalize({ essentials: [{ id: "e1", title: "Mail", url: "https://mail.test/", icon: "https://mail.test", browser: "island", tabKey: "s/1", tabUrl: "https://mail.test/" }] });
  const icons = { "https://mail.test": "data:image/png;base64,AA" };
  // The tab navigates within the site: still the essential's, and its icon is kept.
  const moved = [{ ...tab(1, "https://mail.test/inbox/42"), id: "s/1", source: "s", browser: "island", icon: "https://mail.test" }];
  assert.equal(M.relink(model, moved, icons), true);
  assert.deepEqual([model.essentials[0].tabKey, model.essentials[0].tabUrl, model.essentials[0].icon], ["s/1", "https://mail.test/inbox/42", icons["https://mail.test"]]);
  // Closed on its own: the essential stays, with no tab.
  const before = { windows: [{ id: 1 }], tabs: [tab(1, "https://mail.test/inbox/42"), tab(2, "https://x.test/")] };
  const after = { windows: [{ id: 1 }], tabs: [tab(2, "https://x.test/")] };
  assert.equal(M.dropClosed(model, "s", before, after), true);
  assert.equal(model.essentials.length, 1);
  assert.equal(model.essentials[0].tabKey, null);
  const merged = M.merge(model, [{ id: "s", browser: "island", browserPid: 1, snapshot: { ...after, icons: {} } }]);
  assert.equal(merged.essentials[0].tabId, null);
  assert.equal(merged.essentials[0].icon, icons["https://mail.test"], "the saved icon shows with no tab");
  // Another tab on its site stays loose.
  const other = [{ ...tab(3, "https://mail.test/"), id: "s/3", source: "s", browser: "island" }];
  assert.equal(M.relink(model, other, {}), false);
  assert.equal(model.essentials[0].tabKey, null);
  // Opening it takes the first new tab of the source it asked.
  const opening = { entry: "e1", source: "s", known: { "s/3": true } };
  assert.equal(M.claimOpened(model, opening, other), false);
  const opened = other.concat([{ ...tab(4, ""), id: "s/4", source: "s", browser: "island" }]);
  assert.equal(M.claimOpened(model, opening, opened), true);
  assert.equal(model.essentials[0].tabKey, "s/4");
  const shown = M.merge(model, [{ id: "s", browser: "island", browserPid: 1, snapshot: { windows: [{ id: 1 }], tabs: [tab(3, "https://mail.test/"), tab(4, "https://mail.test/")], icons: {} } }]);
  assert.deepEqual(shown.tabs.map((t) => [t.id, t.essential]), [["s/3", null], ["s/4", "e1"]], "its tab leaves the loose tabs");
});

test("after a browser restart an essential finds its tab by URL, and stays when there is none", () => {
  const model = M.normalize({ essentials: [
    { id: "e1", title: "Mail", url: "https://mail.test/", browser: "island", tabKey: "old/1", tabUrl: "https://mail.test/inbox/42" },
    { id: "e2", title: "Docs", url: "https://docs.test/", browser: "island", tabKey: "old/2", tabUrl: "https://docs.test/a" },
  ] });
  const tabs = [
    { ...tab(7, "https://mail.test/inbox/42#top"), id: "new/7", source: "new", browser: "island" },
    { ...tab(8, "https://docs.test/b"), id: "new/8", source: "new", browser: "island" },
  ];
  assert.equal(M.relink(model, tabs, {}), true);
  assert.equal(model.essentials[0].tabKey, "new/7");
  assert.equal(model.essentials[1].tabKey, "old/2", "a tab elsewhere on the site is not adopted");
  assert.equal(M.merge(model, []).essentials[1].tabId, null);
});

test("pinned tabs and group members outlive their tabs and a restart", () => {
  const model = M.normalize({ pinned: [{ id: "p1", title: "Mail", url: "https://mail.test/", browser: "island", tabKey: "s/1", tabUrl: "https://mail.test/" }],
    groups: [{ id: "g1", name: "g", members: [
      { id: "m1", title: "A", url: "https://a.test/", browser: "island", tabKey: "s/2", tabUrl: "https://a.test/" },
      { id: "m2", title: "B", url: "https://b.test/", browser: "island", tabKey: "s/3", tabUrl: "https://b.test/x" },
    ] }] });
  // Tab 2 closes alone, tab 3 with its window: both stay in the group.
  const before = { windows: [{ id: 1 }, { id: 2 }], tabs: [tab(1, "https://mail.test/"), tab(2, "https://a.test/"), tab(3, "https://b.test/x", { windowId: 2 })] };
  const after = { windows: [{ id: 1 }], tabs: [tab(1, "https://mail.test/")] };
  assert.equal(M.dropClosed(model, "s", before, after), true);
  assert.deepEqual(model.groups[0].members.map((m) => [m.id, m.tabKey]), [["m1", null], ["m2", "s/3"]]);
  assert.equal(M.dropClosed(model, "s", null, after), false);
  // Saved and loaded again, then the browser restarts with new ids.
  const loaded = M.normalize(JSON.parse(JSON.stringify(model)));
  assert.deepEqual(loaded, model, "survives a save");
  const tabs = [
    { ...tab(7, "https://mail.test/"), id: "n/7", source: "n", browser: "island" },
    { ...tab(8, "https://a.test/"), id: "n/8", source: "n", browser: "island" },
    { ...tab(9, "https://b.test/x"), id: "n/9", source: "n", browser: "island" },
  ];
  assert.equal(M.relink(loaded, tabs, {}), true);
  assert.deepEqual([loaded.pinned[0].tabKey, ...loaded.groups[0].members.map((m) => m.tabKey)], ["n/7", null, "n/9"],
    "a member closed on its own does not take a tab on its page");
  const merged = M.merge(loaded, [{ id: "n", browser: "island", browserPid: 1, snapshot: { windows: [{ id: 1 }], tabs: tabs.map((t) => ({ ...t, id: t.rawId ?? Number(t.id.slice(2)) })), icons: {} } }]);
  assert.deepEqual(merged.groups[0].members.map((m) => [m.id, m.tabId, m.title]), [["m1", null, "A"], ["m2", "n/9", "B"]]);
  assert.deepEqual(merged.pinned.map((p) => p.tabId), ["n/7"]);
  assert.deepEqual(merged.tabs.filter((t) => !t.entry).map((t) => t.id), ["n/8"], "its tab is a loose tab, not the member");
  // Opening the closed member claims the new tab.
  assert.equal(M.claimOpened(loaded, { entry: "m1", source: "n", known: { "n/7": true, "n/8": true, "n/9": true } },
    tabs.concat([{ ...tab(10, ""), id: "n/10", source: "n", browser: "island" }])), true);
  assert.equal(loaded.groups[0].members[0].tabKey, "n/10");
});

test("groups saved before members kept their tabs migrate", () => {
  const model = M.normalize({ nextId: 4, groups: [
    { id: "g1", name: "Old", members: [{ browser: "island", url: "https://a.test/", tabKey: "s/1" }, { browser: "island", url: "https://b.test/", tabKey: null }] },
    { id: "g2", name: "Empty", members: [] },
  ] });
  assert.deepEqual(model.groups.map((g) => g.name), ["Old"], "an empty group is dropped");
  assert.deepEqual(model.groups[0].members, [
    { id: "m4", title: "https://a.test/", url: "https://a.test/", icon: "", browser: "island", tabKey: "s/1", tabUrl: "https://a.test/" },
    { id: "m5", title: "https://b.test/", url: "https://b.test/", icon: "", browser: "island", tabKey: "legacy", tabUrl: "https://b.test/" },
  ]);
  assert.equal(model.nextId, 6);
  assert.deepEqual(model.pinned, []);
  // The one with no tab still finds one on its URL, and both take its title.
  const tabs = [{ ...tab(2, "https://b.test/"), id: "s/2", browser: "island", title: "Bee" }, { ...tab(1, "https://a.test/"), id: "s/1", browser: "island", title: "Ay" }];
  assert.equal(M.relink(model, tabs, {}), true);
  assert.deepEqual(model.groups[0].members.map((m) => [m.tabKey, m.title]), [["s/1", "Ay"], ["s/2", "Bee"]]);
  assert.deepEqual(M.normalize(JSON.parse(JSON.stringify(model))), model);
});

test("the old extension's model imports once, for the browser it came from", () => {
  const model = M.emptyModel();
  M.importLegacy(model, {
    essentials: [{ id: "e1", title: "Gmail", url: "https://mail.google.com/", icon: "x", tabId: 4 }],
    groups: [{ id: "g1", name: "Work", members: [{ tabId: 9, url: "https://a.test/" }, { tabId: 10, url: "" }] }],
  }, "island");
  assert.equal(model.legacyImported, true);
  assert.deepEqual(model.essentials.map((e) => [e.title, e.browser, e.tabKey]), [["Gmail", "island", "legacy"]]);
  assert.deepEqual(model.groups[0].members.map((m) => [m.browser, m.url, m.tabKey]), [["island", "https://a.test/", "legacy"]]);
  assert.deepEqual(M.normalize(JSON.parse(JSON.stringify(model))), model, "survives a save");
});

test("a browser window resolves to its Hyprland window by pid and title", () => {
  const clients = [
    { address: "0xa", pid: 10, class: "island-browser", title: "Inbox - Island", focusHistoryID: 3 },
    { address: "0xb", pid: 10, class: "island-browser", title: "Docs - Island", focusHistoryID: 1 },
    { address: "0xc", pid: 20, class: "zen-beta", title: "Inbox — Zen Browser", focusHistoryID: 0 },
  ];
  const island = { id: "island-10", browser: "island", browserPid: 10 };
  assert.equal(M.resolveWindow(clients, island, { activeTitle: "Inbox" }).address, "0xa");
  assert.equal(M.resolveWindow(clients, island, { activeTitle: "Docs - Island" }).address, "0xb", "an exact title");
  assert.equal(M.resolveWindow(clients, island, { activeTitle: "Gone" }).address, "0xb", "else the one focused last");
  assert.equal(M.resolveWindow(clients, { browser: "zen", browserPid: 99 }, { activeTitle: "Inbox" }).address, "0xc", "class when the pid is unknown");
  assert.equal(M.resolveWindow(clients, { browser: "chromium", browserPid: 99 }, { activeTitle: "" }), null);
});

test("a Hyprland window maps back to its browser window", () => {
  const sources = [{ id: "island-10", browser: "island", browserPid: 10 }, { id: "zen-20", browser: "zen", browserPid: 20 }];
  const windows = [
    { id: "island-10/1", source: "island-10", focused: false, activeTitle: "Pull request" },
    { id: "island-10/2", source: "island-10", focused: true, activeTitle: "Pull request #42" },
    { id: "zen-20/1", source: "zen-20", focused: true, activeTitle: "Pull request #42" },
  ];
  const client = (pid, title) => ({ pid, class: pid === 10 ? "island-browser" : "zen-beta", title });
  assert.equal(M.windowForClient(client(10, "Pull request #42 - Island"), sources, windows).id, "island-10/2", "the longest title");
  assert.equal(M.windowForClient(client(10, "Pull request - Island"), sources, windows).id, "island-10/1");
  assert.equal(M.windowForClient(client(10, "Something else"), sources, windows).id, "island-10/2", "else the focused one");
  assert.equal(M.windowForClient(client(20, "Pull request #42 — Zen"), sources, windows).id, "zen-20/1");
  assert.equal(M.windowForClient({ pid: 5, class: "foot", title: "x" }, sources, windows), null);
});

test("MRU puts the tab in front first, then by the later of browser and shell times", () => {
  const tabs = [
    { id: "a/1", lastAccessed: 100 },
    { id: "b/1", lastAccessed: 300 },
    { id: "a/2", lastAccessed: 200 },
  ];
  assert.deepEqual(R.order(tabs, {}, null).map((t) => t.id), ["b/1", "a/2", "a/1"]);
  // Focusing browser a's window stamped its tab after b's.
  assert.deepEqual(R.order(tabs, { "a/1": 400 }, null).map((t) => t.id), ["a/1", "b/1", "a/2"]);
  assert.deepEqual(R.order(tabs, {}, "a/1").map((t) => t.id), ["a/1", "b/1", "a/2"], "the current tab leads");
  const stamps = R.stamp({ "gone/1": 5, "a/2": 7 }, "b/1", 900, tabs);
  assert.deepEqual(stamps, { "a/2": 7, "b/1": 900 }, "closed tabs drop out");
});

test("a cycle starts before the current tab, or on the oldest backwards, and wraps", () => {
  assert.equal(S.start(5, false), 1);
  assert.equal(S.start(5, true), 4);
  assert.equal(S.start(1, false), 0);
  assert.equal(S.step(4, 1, 5), 0);
  assert.equal(S.step(0, -1, 5), 4);
});

test("interpretInput tells URLs, domains and searches apart", () => {
  assert.deepEqual(M.interpretInput("linear.app/inbox"), { kind: "url", url: "https://linear.app/inbox" });
  assert.deepEqual(M.interpretInput("localhost:3000"), { kind: "url", url: "http://localhost:3000" });
  assert.deepEqual(M.interpretInput("how to nix"), { kind: "search", text: "how to nix" });
  assert.deepEqual(M.interpretInput("  "), { kind: "blank" });
});
