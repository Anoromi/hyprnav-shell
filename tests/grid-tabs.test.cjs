// node --test tests/
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// shell/grid/tabs.js is a QML `.pragma library` script: plain JS once the
// pragma line is gone.
const source = fs.readFileSync(path.join(__dirname, "../shell/grid/tabs.js"), "utf8").replace(/^\.pragma library\s*$/m, "");
const T = new Function(`${source}; return { ALPHABET, hintLabels, build, resolve, searchStart, hostOf, matches, deleteWord, flatRows, keyOps };`)();

test("hint labels stay prefix-free and short labels go first", () => {
  assert.deepEqual(T.hintLabels(3), ["h", "t", "n"], "right hand first");
  assert.equal(T.hintLabels(10).join(""), T.ALPHABET);
  for (const n of [11, 19, 20, 37, 100]) {
    const labels = T.hintLabels(n);
    assert.equal(labels.length, n);
    assert.equal(new Set(labels).size, n);
    for (const a of labels) for (const b of labels) {
      if (a !== b) assert.ok(!b.startsWith(a), `${a} is a prefix of ${b}`);
    }
  }
  // Eleven items: one letter turns into a prefix, nine stay single.
  assert.deepEqual(T.hintLabels(11).slice(0, 9), "htnsdueoa".split(""));
  assert.equal(T.hintLabels(101).length, 100, "no labels beyond two letters");
});

test("build orders essentials, new tab, pinned, groups, then the rest by recency", () => {
  const snap = {
    essentials: [{ id: "e1", title: "Linear", url: "https://linear.app", icon: "", tabId: 1 }],
    pinned: [{ id: "p1", title: "Mail", url: "https://mail.test/", icon: "", tabId: null }],
    groups: [{ id: "g1", name: "Research", members: [{ id: "m1", title: "Paper", url: "https://arxiv.org/", tabId: 3 }] }, { id: "g2", name: "Empty", members: [] }],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "Linear", url: "https://linear.app/x", entry: "e1", essential: "e1", lastAccessed: 9 },
      { id: 2, windowId: 1, index: 1, title: "Old", url: "https://old.test/", lastAccessed: 1 },
      { id: 3, windowId: 1, index: 2, title: "Paper v2", url: "https://arxiv.org/2", entry: "m1", group: "g1", lastAccessed: 5 },
      { id: 4, windowId: 2, index: 0, title: "", url: "https://www.new.test/a", lastAccessed: 7 },
    ],
  };
  const m = T.build(snap);
  assert.deepEqual(m.selectables.map((s) => s.key), ["e:e1", "new", "p:p1", "g:g1", "t:4", "t:2"], "groups start collapsed");
  assert.deepEqual(m.selectables.map((s) => s.hint), ["h", "t", "n", "s", "d", "u"]);
  assert.deepEqual(m.sections.map((s) => s.key), ["pinned", "groups", "loose"]);
  assert.equal(m.sections[0].title, "Pinned");
  assert.deepEqual([m.sections[0].items[0].open, m.sections[0].items[0].title], [false, "Mail"], "a closed pinned tab shows its own title");
  const header = m.sections[1].groups[0].header;
  assert.deepEqual([header.title, header.count, header.openCount, header.expanded], ["Research", 1, 1, false]);
  assert.equal(m.sections[2].items[0].title, "new.test", "an untitled tab shows its host");
  assert.equal(m.essentials[0].open, true);
  const x = T.build(snap, null, null, { g1: true });
  assert.deepEqual(x.selectables.map((s) => s.key), ["e:e1", "new", "p:p1", "g:g1", "m:m1", "t:4", "t:2"]);
  assert.equal(x.selectables[4].title, "Paper v2", "an open member shows its tab's title");
});

test("a collapsed group takes one hint; expanded, its members continue it", () => {
  const members = (n, open) => Array.from({ length: n }, (_, i) => ({ id: `m${i}`, title: `m${i}`, url: `https://m${i}.test/`, tabId: i < open ? `s/${i}` : null }));
  const tabs = (n, open) => Array.from({ length: open }, (_, i) => ({ id: `s/${i}`, windowId: 1, index: i, title: `m${i}`, url: `https://m${i}.test/`, entry: `m${i}`, group: "g1", lastAccessed: n - i }))
    .concat(Array.from({ length: 12 }, (_, i) => ({ id: `l/${i}`, windowId: 1, index: i, title: `l${i}`, url: `https://l${i}.test/`, lastAccessed: 0 })));
  for (const n of [1, 9, 10, 25]) {
    const snap = { groups: [{ id: "g1", name: "G", members: members(n, 3) }], tabs: tabs(n, 3) };
    const shut = T.build(snap);
    const header = shut.selectables.find((s) => s.kind === "group");
    assert.equal(shut.selectables.filter((s) => s.kind === "entry").length, 0);
    const open = T.build(snap, null, null, { g1: true });
    const head = open.selectables.find((s) => s.kind === "group");
    assert.equal(head.base, header.hint, "expanding keeps the group's label");
    assert.equal(head.hint, header.hint + header.hint, "typing it again collapses");
    const hints = open.selectables.map((s) => s.hint);
    assert.equal(new Set(hints).size, hints.length);
    for (const a of hints) for (const b of hints) if (a !== b) assert.ok(!b.startsWith(a), `${a} is a prefix of ${b}`);
    // Everything outside the group keeps its label.
    const outside = (mm) => mm.selectables.filter((s) => s.kind !== "entry" && s.kind !== "group").map((s) => [s.key, s.hint]);
    assert.deepEqual(outside(open), outside(shut));
    const items = open.selectables.filter((s) => s.kind === "entry");
    assert.equal(items.length, n);
    for (const it of items) assert.ok(it.hint.startsWith(header.hint) && it.hint.length > header.hint.length, it.hint);
    assert.ok(items.slice(0, Math.min(3, n)).every((i) => i.open), "open members first");
    assert.equal(T.resolve(open.selectables, header.hint).partial, true, "the label alone now waits for a member");
  }
});

test("a search expands the groups it matches, by member or by group name", () => {
  const snap = {
    groups: [
      { id: "g1", name: "Research", members: [{ id: "m1", title: "Paper", url: "https://arxiv.org/", tabId: null }, { id: "m2", title: "Notes", url: "https://n.test/", tabId: null }] },
      { id: "g2", name: "Other", members: [{ id: "m3", title: "Cats", url: "https://c.test/", tabId: null }] },
    ],
    tabs: [],
  };
  assert.deepEqual(T.build(snap, "paper").selectables.map((s) => s.key), ["g:g1", "m:m1", "new"]);
  const found = T.build(snap, "paper").selectables;
  assert.equal(found[T.searchStart(found, "paper")].key, "m:m1", "a search starts on the match, not its group");
  assert.deepEqual(T.build(snap, "research").selectables.map((s) => s.key), ["g:g1", "m:m1", "m:m2", "new"]);
  assert.deepEqual(T.build(snap, "").selectables.map((s) => s.key), ["g:g1", "g:g2", "new"], "a blank query expands nothing");
});

test("a collapsed group holding the tab showing is where a search starts", () => {
  const snap = {
    groups: [{ id: "g1", name: "G", members: [{ id: "m1", title: "a", url: "https://a.test/", tabId: 1 }] }],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "a", url: "https://a.test/", entry: "m1", group: "g1", active: true, lastAccessed: 5 },
      { id: 2, windowId: 1, index: 1, title: "b", url: "https://b.test/", lastAccessed: 9 },
    ],
  };
  const m = T.build(snap, "");
  assert.equal(m.hereTab, 1);
  assert.equal(m.selectables[T.searchStart(m.selectables, "")].key, "g:g1");
  const x = T.build(snap, "", null, { g1: true });
  assert.equal(x.selectables[T.searchStart(x.selectables, "")].key, "m:m1");
});

test("icons resolve through the snapshot's icon table", () => {
  const m = T.build({
    icons: { "https://a.test": "data:image/png;base64,AA" },
    essentials: [{ id: "e1", title: "A", url: "https://a.test/", icon: "https://a.test", tabId: null }],
    groups: [],
    tabs: [{ id: 1, windowId: 1, index: 0, title: "B", url: "https://b.test/", icon: "https://b.test", essential: null, group: null }],
  });
  assert.equal(m.essentials[0].icon, "data:image/png;base64,AA");
  assert.equal(m.sections[0].items[0].icon, "", "an icon still loading shows the initial");
});

test("groups and their members go most recently used first", () => {
  const m = T.build({
    groups: [
      { id: "g0", name: "Idle", members: [{ id: "m0", title: "closed", url: "https://z.test/", tabId: null }] },
      { id: "g1", name: "G", members: [{ id: "m1", title: "old", url: "https://a.test/", tabId: 1 }, { id: "m2", title: "new", url: "https://b.test/", tabId: 2 }] },
    ],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "old", url: "https://a.test/", entry: "m1", group: "g1", lastAccessed: 1 },
      { id: 2, windowId: 1, index: 1, title: "new", url: "https://b.test/", entry: "m2", group: "g1", lastAccessed: 2 },
    ],
  }, null, null, { g1: true });
  assert.deepEqual(m.sections[0].groups.map((g) => g.header.title), ["G", "Idle"]);
  assert.deepEqual(m.sections[0].groups[0].items.map((i) => i.title), ["new", "old"]);
});

test("here is the active tab looked at last, in an essential too", () => {
  const m = T.build({
    essentials: [{ id: "e1", title: "A", url: "https://a.test/", icon: "", tabId: 2 }],
    groups: [],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "w1", url: "https://x.test/", active: true, lastAccessed: 5 },
      { id: 2, windowId: 2, index: 0, title: "w2", url: "https://a.test/", active: true, lastAccessed: 9, essential: "e1" },
      { id: 3, windowId: 2, index: 1, title: "bg", url: "https://y.test/", active: false, lastAccessed: 20 },
    ],
  });
  assert.equal(m.essentials[0].here, true);
  assert.deepEqual(m.sections[0].items.map((i) => [i.title, i.here]), [["bg", false], ["w1", false]]);
});

test("a query keeps entries matching every word and opens the rest as a new tab", () => {
  const snap = {
    essentials: [{ id: "e1", title: "Linear", url: "https://linear.app/", icon: "", tabId: null }],
    groups: [{ id: "g1", name: "G", members: [{ id: "m1", title: "Issues", url: "https://github.com/x/issues", tabId: 2 }] }],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "Pull request #42", url: "https://github.com/x/pull/42", lastAccessed: 3 },
      { id: 2, windowId: 1, index: 1, title: "Issues", url: "https://github.com/x/issues", entry: "m1", group: "g1", lastAccessed: 2 },
      { id: 3, windowId: 1, index: 2, title: "Docs", url: "https://docs.test/", lastAccessed: 1 },
    ],
  };
  const m = T.build(snap, "github PULL");
  assert.deepEqual(m.selectables.map((s) => s.key), ["t:1", "new"]);
  assert.equal(m.newTab.text, "github PULL");
  assert.equal(T.build(snap, "lin").selectables[0].key, "e:e1");
  assert.equal(T.build(snap, "  ").selectables.length, 5, "a blank query filters nothing");
  assert.equal(T.matches("", "a", "b"), true);
});

test("frozen last-used times keep the order while tabs are previewed", () => {
  const snap = {
    groups: [],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "a", url: "https://a.test/", active: false, lastAccessed: 100 },
      { id: 2, windowId: 1, index: 1, title: "b", url: "https://b.test/", active: true, lastAccessed: 10 },
    ],
  };
  assert.deepEqual(T.build(snap).sections[0].items.map((i) => i.title), ["a", "b"]);
  const frozen = { 1: 5, 2: 10 };
  assert.deepEqual(T.build(snap, null, frozen).sections[0].items.map((i) => i.title), ["b", "a"]);
  assert.equal(snap.tabs[0].lastAccessed, 100, "the snapshot itself is untouched");
});

test("a search lists New tab last and starts on the tab showing", () => {
  const snap = {
    essentials: [{ id: "e1", title: "Linear", url: "https://linear.app/", icon: "", tabId: null }],
    groups: [],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "a", url: "https://a.test/", active: false, lastAccessed: 3 },
      { id: 2, windowId: 1, index: 1, title: "b", url: "https://b.test/", active: true, lastAccessed: 2 },
    ],
  };
  assert.deepEqual(T.build(snap).selectables.map((s) => s.key), ["e:e1", "new", "t:1", "t:2"]);
  const empty = T.build(snap, "").selectables;
  assert.deepEqual(empty.map((s) => s.key), ["e:e1", "t:1", "t:2", "new"]);
  assert.equal(empty[T.searchStart(empty, "")].key, "t:2", "the tab showing");
  const noHere = empty.map((s) => Object.assign({}, s, { here: false }));
  assert.equal(noHere[T.searchStart(noHere, "")].key, "t:1", "else the first tab");
  const typed = T.build(snap, "a").selectables;
  assert.equal(T.searchStart(typed, "a"), 0, "the first match once typed");
  assert.equal(typed[typed.length - 1].key, "new");
});

test("resolve finds an exact hint or reports a live prefix", () => {
  const items = [{ hint: "a" }, { hint: "sa" }, { hint: "so" }];
  assert.equal(T.resolve(items, "a").exact, items[0]);
  assert.deepEqual(T.resolve(items, "s"), { exact: null, partial: true });
  assert.equal(T.resolve(items, "so").exact, items[2]);
  assert.deepEqual(T.resolve(items, "x"), { exact: null, partial: false });
});

test("deleteWord drops trailing spaces and the word before them", () => {
  assert.equal(T.deleteWord("hacker news"), "hacker ");
  assert.equal(T.deleteWord("hacker news  "), "hacker ");
  assert.equal(T.deleteWord("hacker "), "");
  assert.equal(T.deleteWord("rust"), "");
  assert.equal(T.deleteWord("   "), "");
  assert.equal(T.deleteWord(""), "");
  assert.equal(T.deleteWord("a.b/c d"), "a.b/c ");
});

test("entries name their browser only while several run", () => {
  const tabs = [{ id: "zen-1/1", windowId: "zen-1/1", index: 0, title: "a", url: "https://a.test/", browser: "zen" }];
  assert.equal(T.build({ groups: [], tabs, browsers: ["zen"] }).sections[0].items[0].badge, "");
  assert.equal(T.build({ groups: [], tabs, browsers: ["zen", "island"] }).sections[0].items[0].badge, "zen");
});

test("keyOps edits a key list in place into the new one", () => {
  const apply = (from, ops) => {
    const a = from.slice();
    for (const o of ops) {
      if (o.op === "remove") a.splice(o.at, 1);
      else if (o.op === "move") a.splice(o.to, 0, a.splice(o.from, 1)[0]);
      else a.splice(o.at, 0, o.key);
    }
    return a;
  };
  assert.deepEqual(T.keyOps(["a", "b", "c"], ["a", "b", "c"]), [], "same keys: nothing to do");
  const cases = [
    [[], ["a", "b"]], [["a", "b"], []], [["a", "b", "c"], ["c", "a", "b"]],
    [["a", "b", "c", "d"], ["d", "x", "b", "a"]], [["a", "b", "c"], ["b", "c", "y", "a"]],
  ];
  for (const [from, to] of cases) assert.deepEqual(apply(from, T.keyOps(from, to)), to, `${from} -> ${to}`);
  // Removes come first, so the maps can change in between.
  const ops = T.keyOps(["a", "b", "c"], ["c", "z"]);
  assert.deepEqual(ops.map(o => o.op), ["remove", "remove", "insert"]);
  // A recent tab moving to the top is one move, not a rebuild.
  assert.deepEqual(T.keyOps(["a", "b", "c", "d"], ["d", "a", "b", "c"]), [{ op: "move", from: 3, to: 0 }]);
});

test("flatRows lists titles, rows and group members with unique keys", () => {
  const model = { sections: [
    { key: "pinned", title: "Pinned", items: [{ key: "p:1" }], groups: [] },
    { key: "groups", title: "", items: [], groups: [{ header: { key: "g:1" }, items: [{ key: "m:1" }, { key: "m:2" }] }, { header: { key: "g:2" }, items: [] }] },
    { key: "loose", title: "Tabs", items: [{ key: "t:a" }, { key: "t:a" }], groups: [] },
  ] };
  const rows = T.flatRows(model);
  assert.deepEqual(rows.map(r => r.key), ["s:pinned", "p:1", "g:1", "m:1", "m:2", "g:2", "s:loose", "t:a"]);
  assert.deepEqual(rows.map(r => r.kind), ["title", "tab", "group", "tab", "tab", "group", "title", "tab"]);
  assert.deepEqual(rows.filter(r => r.gap).map(r => r.key), ["g:1", "s:loose"], "a gap opens every section after the first");
  assert.deepEqual(rows.filter(r => r.indent).map(r => r.key), ["m:1", "m:2"]);
  assert.deepEqual(T.flatRows(T.build(null)), []);
});
