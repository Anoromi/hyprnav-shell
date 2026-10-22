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
const M = load("tabs/model.js", ["CLASSES", "emptyModel", "normalize", "importLegacy", "relink", "claimOpened", "removeMember",
  "dropClosed", "pin", "assign", "merge", "resolveWindow", "windowForClient", "interpretInput"]);
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
    groups: [{ id: "g1", name: "Research", members: [{ browser: "island", url: "https://arxiv.org/x", tabKey: "island-9/4" }] }],
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
  assert.deepEqual(merged.tabs.map((t) => [t.id, t.essential, t.group]),
    [["island-1/7", null, null], ["island-1/8", null, "g1"], ["zen-2/3", "e1", null]]);
  assert.deepEqual(merged.groups[0].tabIds, ["island-1/8"]);
  assert.equal(merged.essentials[0].tabId, "zen-2/3");
});

test("pinning and assigning move a tab between essentials and groups", () => {
  const model = M.emptyModel();
  const t = { id: "island-1/3", browser: "island", url: "https://chatgpt.com/", title: "ChatGPT", icon: "https://chatgpt.com" };
  M.assign(model, t, "Research");
  M.assign(model, t, " research ");
  assert.equal(model.groups.length, 1, "group names match case-insensitively");
  assert.deepEqual(model.groups[0].members, [{ browser: "island", url: "https://chatgpt.com/", tabKey: "island-1/3" }]);
  M.pin(model, t);
  assert.equal(model.essentials[0].browser, "island");
  assert.equal(model.groups[0].members.length, 0, "pinning takes the tab out of its group");
  M.assign(model, t, "Other");
  assert.equal(model.essentials[0].tabKey, null, "assigning takes the tab from its essential");
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
  const opening = { essential: "e1", source: "s", known: { "s/3": true } };
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

test("a closed tab leaves its group, a closed window keeps it", () => {
  const model = M.normalize({ groups: [{ id: "g1", name: "g", members: [
    { browser: "island", url: "https://a.test/", tabKey: "s/1" },
    { browser: "island", url: "https://b.test/", tabKey: "s/2" },
  ] }] });
  const before = { windows: [{ id: 1 }, { id: 2 }], tabs: [tab(1, "https://a.test/"), tab(2, "https://b.test/", { windowId: 2 })] };
  const after = { windows: [{ id: 1 }], tabs: [] };
  assert.equal(M.dropClosed(model, "s", before, after), true);
  assert.deepEqual(model.groups[0].members.map((m) => m.tabKey), ["s/2"]);
  assert.equal(M.dropClosed(model, "s", null, after), false);
});

test("the old extension's model imports once, for the browser it came from", () => {
  const model = M.emptyModel();
  M.importLegacy(model, {
    essentials: [{ id: "e1", title: "Gmail", url: "https://mail.google.com/", icon: "x", tabId: 4 }],
    groups: [{ id: "g1", name: "Work", members: [{ tabId: 9, url: "https://a.test/" }, { tabId: 10, url: "" }] }],
  }, "island");
  assert.equal(model.legacyImported, true);
  assert.deepEqual(model.essentials.map((e) => [e.title, e.browser, e.tabKey]), [["Gmail", "island", "legacy"]]);
  assert.deepEqual(model.groups[0].members, [{ browser: "island", url: "https://a.test/", tabKey: null }]);
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
