// node --test tests/
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// shell/grid/tabs.js is a QML `.pragma library` script: plain JS once the
// pragma line is gone.
const source = fs.readFileSync(path.join(__dirname, "../shell/grid/tabs.js"), "utf8").replace(/^\.pragma library\s*$/m, "");
const T = new Function(`${source}; return { ALPHABET, hintLabels, build, resolve, searchStart, hostOf, matches, deleteWord };`)();

test("hint labels stay prefix-free and short labels go first", () => {
  assert.deepEqual(T.hintLabels(3), ["a", "o", "e"]);
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
  assert.deepEqual(T.hintLabels(11).slice(0, 9), "aoeuidhtn".split(""));
  assert.equal(T.hintLabels(101).length, 100, "no labels beyond two letters");
});

test("build orders essentials, new tab, groups, then the rest by recency", () => {
  const snap = {
    essentials: [{ id: "e1", title: "Linear", url: "https://linear.app", icon: "", tabId: 1 }],
    groups: [{ id: "g1", name: "Research", tabIds: [3] }, { id: "g2", name: "Empty", tabIds: [] }],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "Linear", url: "https://linear.app/x", essential: "e1", group: null, lastAccessed: 9 },
      { id: 2, windowId: 1, index: 1, title: "Old", url: "https://old.test/", essential: null, group: null, lastAccessed: 1 },
      { id: 3, windowId: 1, index: 2, title: "Paper", url: "https://arxiv.org/", essential: null, group: "g1", lastAccessed: 5 },
      { id: 4, windowId: 2, index: 0, title: "", url: "https://www.new.test/a", essential: null, group: null, lastAccessed: 7 },
    ],
  };
  const m = T.build(snap);
  assert.deepEqual(m.selectables.map((s) => s.key), ["e:e1", "new", "t:3", "t:4", "t:2"]);
  assert.deepEqual(m.selectables.map((s) => s.hint), ["a", "o", "e", "u", "i"]);
  assert.deepEqual(m.sections.map((s) => s.title), ["Research", "Tabs"], "empty groups are hidden");
  assert.equal(m.sections[1].items[0].title, "new.test", "an untitled tab shows its host");
  assert.equal(m.essentials[0].open, true);
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

test("a group lists its tabs most recently used first", () => {
  const m = T.build({
    groups: [{ id: "g1", name: "G", tabIds: [1, 2] }],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "old", url: "https://a.test/", group: "g1", lastAccessed: 1 },
      { id: 2, windowId: 1, index: 1, title: "new", url: "https://b.test/", group: "g1", lastAccessed: 2 },
    ],
  });
  assert.deepEqual(m.sections[0].items.map((i) => i.title), ["new", "old"]);
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
    groups: [{ id: "g1", name: "G", tabIds: [2] }],
    tabs: [
      { id: 1, windowId: 1, index: 0, title: "Pull request #42", url: "https://github.com/x/pull/42", lastAccessed: 3 },
      { id: 2, windowId: 1, index: 1, title: "Issues", url: "https://github.com/x/issues", group: "g1", lastAccessed: 2 },
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
