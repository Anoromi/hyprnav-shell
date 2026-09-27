# Design direction: contact sheet

Subject: choosing one workspace out of many by eye, fast. The closest physical
artefact is a photographer's contact sheet: rows of small frames on dark paper,
frame numbers along the edge, and a grease-pencil ring around the chosen shot.
hyprnav maps onto it directly. An environment is a roll. A slot is a frame
number. The live thumbnail is the frame. Selecting is drawing the ring.

## Palette

| Name | Hex | Role |
|---|---|---|
| Darkroom | #1A1917 | overlay scrim and sheet background, warm, not tinted black |
| Sheet | #262421 | card and bar surface |
| Emulsion | #3A3733 | frame border, dividers, empty frame fill |
| Paper | #EDE6DA | primary text, thumbnail frame edge |
| Pencil | #F2C14E | selection ring, focused item, the one loud colour (chinagraph yellow) |
| Fixer | #9A938A | secondary text, muted labels |

Semantic extras, used rarely: Good #8FBF7F (connected), Warn #E06C4B (error, battery low).

## Type

One family, Recursive, in three cuts.
- Recursive Sans Linear, regular and medium, 13 to 15 px: all UI text.
- Recursive Sans Casual, medium and bold, 18 to 22 px: environment titles.
  The casual cut has a hand-set feel that reads as pencil on the sheet.
- Recursive Mono Linear, medium, 12 px and 40 px: frame numbers on card
  edges (small) and the slot digit on the ring (large). Digits are the keyboard
  affordance, so they are set large and tabular.

Scale: 12, 13, 15, 18, 22, 40. Line height 1.3 for UI text, 1.1 for titles.
Sentence case everywhere. No all-caps labels, no middle-dot meta strings.

## Layout

Switcher (MRU):

```
 ┌──────────────────────────────────────────────────────────┐
 │ scrim                                                     │
 │      ┏━━━━━━━┓  ┌───────┐  ┌───────┐  ┌───────┐           │
 │      ┃ thumb ┃  │ thumb │  │ thumb │  │ thumb │           │
 │      ┃       ┃  │       │  │       │  │       │           │
 │      ┗━━━━━━━┛  └───────┘  └───────┘  └───────┘           │
 │      2 T3 Code    1 Term     4 Zen      3 Tele            │
 │                                                           │
 │      Start a New Conversation                              │
 └──────────────────────────────────────────────────────────┘
```
One row, left aligned from a fixed inset, thumbnails 16:10, frame number and
title under each card in one line. The ring (thick Pencil outline, slightly
larger than the card) is a single item that slides between cards. Below the
row, the environment title of the selected card in Casual. Nothing else.

Grid (environments):

```
 ┌──────────────────────────────────────────────────────────┐
 │  Start a New Conversation            locked               │
 │  ┌────┐ ┏━━━━┓ ┌────┐ ┌────┐                              │
 │  │ 1  │ ┃ 2  ┃ │ 3  │ │ 4  │                              │
 │  └────┘ ┗━━━━┛ └────┘ └────┘                              │
 │  Phase 6 Compiler Reuse                                   │
 │  ┌────┐ ┌────┐ ┌────┐                                     │
 │  │ 1  │ │ 2  │ │ 3  │                                     │
 │  └────┘ └────┘ └────┘                                     │
 └──────────────────────────────────────────────────────────┘
```
Rows are rolls: title on the left in Casual, then frames. Frame number sits
inside the frame's top-left corner like a film edge marking. Empty slots are
Emulsion fill with the launch command name in Fixer. A roll is a leaf
environment; frames it shares with its ancestors come first, drawn like any
other frame, with a small "shared" in Fixer after the name. The title is
followed by a Pencil lock glyph when any level of the chain is locked, then
the ancestors' names in Fixer ("in Proj › main").

Bar: a 44 px column on the left edge, the film strip's edge, in three
groups anchored on their own. Top, from the top edge: every workspace on the
screen with an id from 1 to 99 in id order, the current one in a Pencil
block, occupied ones in Paper, empty ones in Fixer; special and
hyprnav-managed workspaces (100 and up) get no number. A list too long for
the room above the middle scrolls on the wheel behind soft edges. Middle,
centred and of constant height: launcher, clipboard, bell, the network,
bluetooth, audio and battery cluster, and four reserved tray slots. Bottom,
on the bottom edge: the clock stacked HH over mm, and above it, only while
hyprnav holds a lock, the locked roll standing on a fixed baseline: its
initials in dim Pencil Casual, a small Fixer lock, its frame numbers in the
same pips as the top list, and a 2 px dim Pencil rule along its left edge,
the grease-pencil mark along a chosen strip, drawn as a quiet line rather
than a filled rail. It fades in place; frames coming and going move only its
top. The workspace on screen is marked in both groups when the roll holds
it. Locking from the bar is a right-click on a number that is a roll's
frame; clicking the initials or the lock unlocks. No title along the edge:
sideways text at bar width does not read; hovering the head names the roll.
Quick settings
open as one sheet beside the bar, bottom left.

## Motion

Spent in one place: the ring.
- Open: scrim fades in 120 ms; cards appear already in place with a 6 px rise
  over 160 ms, staggered 12 ms per card, ease out cubic. The ring draws on at
  the initial index by scaling from 0.92 to 1.
- Step: the ring moves with a spring (stiffness 320, damping 26). Cards do not
  move. The title under the row cross-fades 100 ms.
- Activate: the ring thickens 2 px and the other cards drop to 40% over
  120 ms, then the overlay hides. This shows what was chosen.
- Cancel: everything fades 90 ms. No rise, no scale.
- Reduced motion: durations 0, ring jumps.

## Principles

- The thumbnail is the content. Chrome stays thin and warm; nothing competes
  with the frames.
- Numbers are for hands, titles are for eyes. Digits are large and mono;
  titles are set once per row, not per card.
- The ring is the only thing that moves.
- Empty states say what pressing Enter will do: "Opens ghostty" not "Empty".

## Review against defaults

First draft used charcoal #111 plus an acid accent and monospace labels
everywhere. That is trait 2 and trait 5 from the calibration list. Changed to
a warm Darkroom base, Pencil yellow chosen for its grease-pencil reference
rather than for contrast, and mono restricted to digits where it encodes
the keyboard mapping. The Casual cut for titles is the risk taken; it is the
one element that makes the sheet look marked by a hand.
