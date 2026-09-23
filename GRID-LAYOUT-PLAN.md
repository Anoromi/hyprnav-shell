# Grid layout: wrapping, scrolling, temporary slots

Status: 2026-09-23. Wrapping (2ec84e7), scrolling (41dae6c) and temporary-slot placement
(daemon da9db45, switcher 437b581) are all implemented in the lab and recorded; awaiting the
user's judgement of the clips before the Nix input bumps.

## Decisions so far (user)

1. Temporary slots show at the end of their own environment's row and nowhere else: not
   inherited into child rows, not in the switcher, not in the bar. The 1000+ slot index stays
   as the internal "unnumbered" marker; physical workspaces come from the same 101+ pool as
   numbered frames.
2. Rows wrap: a row wider than the screen flows onto further lines of the same cell size.
   Judged from the clip; keep unless the user says otherwise.
3. The grid must scroll when the stack of rows exceeds the screen height. Today it clamps to
   the top and lets the rest run off the bottom; this predates wrapping.

## Scrolling design

Model: the rows form one vertical stack (`stackH` from the prefix sums `rowTops` that wrapping
introduced). A viewport of height `height − top inset − bottom inset` shows a window
`[scrollY, scrollY + viewportH)` of that stack. When `stackH <= viewportH` the stack is centred
as today and `scrollY` is fixed at 0.

Behaviour:
* **Selection-driven.** Every selection change (keys, Home/End, palette, open) calls
  `ensureVisible(selRow, selCol)`: if the selected cell's line (title included for the first
  line of a row, name label included) is outside the viewport, `scrollY` moves the minimum
  amount to bring it inside plus one `rowGap` of margin. Animated with `Behavior on scrollY`
  (`Theme.tRise`, OutCubic); `reducedMotion` disables it.
* **Open state.** On open, `scrollY` starts so the current row (the one containing the active
  workspace, which is also the initial selection) is visible; if it fits, prefer showing the
  locked/first row at the top too.
* **Wheel and touchpad.** `WheelHandler` on the grid: `scrollY -= angleDelta.y * k`, clamped to
  `[0, stackH − viewportH]`; pixel deltas honoured for touchpads. Wheel does not move the
  selection.
* **Drag.** Not needed; hover already selects under the pointer.
* **Edges.** Two soft fades (Darkroom to transparent, 48 px) at the top and bottom of the
  viewport, shown only when there is content beyond that edge. A 3 px scroll indicator on the
  right edge, Fixer colour, visible while `stackH > viewportH`, fades in on scroll and out after
  800 ms of rest. No scrollbar widget.
* **Layout stability.** Rows keep their long-lived delegates; scrolling only changes the
  `y` offset of the rows container (`Item { y: -scrollY }` wrapping the rows Repeater), so
  thumbnails and captures are untouched. Rows entirely outside the viewport ± one row height
  set `visible: false` so ScreencopyView does not capture off-screen windows (cost, not
  correctness).
* **Ring and palette.** `cellY` accounts for `scrollY`; the palette anchors to the visible
  cell.
* **Activation.** The zoom-into-frame animation uses the on-screen position; no change.

Not in scope: pinch zoom, per-row collapse, or shrinking cells at high counts (possible later
as a density toggle in the palette).

## Verification

Lab with enough environments to exceed 1080 px: 3 rows of 14, 4 and 3 frames plus two more
environments. Checks:
1. Open the grid with the active workspace in the last row: it opens scrolled so that row is
   visible.
2. Up from the first visible row scrolls the stack down smoothly; the ring never leaves the
   viewport across a full Home-to-End walk of the stack.
3. Wheel scrolls without moving the selection; the fades and the indicator appear only at edges
   with hidden content.
4. Enter on a cell in a scrolled position activates the right workspace.
5. Fewer rows than the viewport: identical to today (centred, no indicator, no fades).
6. No thumbnail blink while scrolling (60 fps frame diff over 2 s, as in the flicker test).
7. Idle cost unchanged: no snapshot requests during scrolling.

Evidence: a 30–40 s clip with captions, screenshots of each check, published under the
hyprnav-shell artifacts page. Then: bump the hyprnav-shell input in the Nix config together
with the temporary-slot change.

Done 2026-09-23, with two departures from the design above:

* The margin `ensureVisible` leaves is the fade depth (48 px), not one `rowGap`
  (32 px). At 32 px the ring's top edge sat under the top fade and was visibly
  dimmed; the margin is now `max(rowGap, fadeH)`.
* Check 1 could not be staged as written. The daemon sorts the environment
  holding the active workspace to row 0, whatever its recency or its place in
  the hierarchy, so the current row is never the last one. The equivalent
  guarantee — the grid opens already scrolled to the current frame — was
  verified instead, with the active frame on the sixth line of a 32-frame roll.

## Order

1. Temporary-slot placement (daemon + switcher): done.
2. Scrolling: done, recorded.
3. User judges wrapping + scrolling from the clips.
4. Nix input bumps for hyprnav and hyprnav-shell; testbed L2 run.
