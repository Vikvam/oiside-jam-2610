# UI rework: review and plan

**Status: done** (see DECISIONS.md, "UI rework"). The layout test is `tests/layout.gd`.

## Why the UI doesn't fit (measured)

The game renders at 1280×720 (stretch `canvas_items`, aspect `expand`), with 16 px margins, so there are **688 px of height** for content.

| | left column needs | fits? |
|---|---|---|
| English, classic house | 759 px | no, 71 px over |
| Czech, classic house | 775 px | no, 87 px over |
| Czech, large house | 725 px | no, 37 px over |

- **Plan:** a fixed 632×476 box, always, even though the large house only draws 351 px of it.
- **Room panel:** 195–245 px and growing.
- Both columns share one row, so the overflow also pushes the **phone's text field and Tap / Hang-up buttons off-screen**. That's what makes the game unplayable.

Your display is 4608×2880 at 387 DPI. A fixed 1280×720 window is physically small there, and its text is tiny unless you maximise it.

## How the design changed since the layout was made

The layout dates from the first build: one panel per system. Since then:

1. **Fog of war:** unknown rooms are "?" boxes, so early on the plan is mostly empty walls. It doesn't need to be the biggest thing on screen at a fixed size.
2. **Her directions are relative to the way you face** ("door on your left"). That information lives *on the plan* (your arrow, the doors), yet the left/right labels sit in a row of text buttons far below it.
3. **Two sound channels:** the house box above the line box works and should stay.
4. **Hiding is a mode** (Hide ↔ Come out) and deserves a clear, always-visible control, not a button in the door row.
5. **The room panel duplicates the plan:** the door buttons do the same as clicking the plan or the arrow keys, and the visited-room object lists on the plan repeat the Search row.
6. **The legend line** (◉ / ♥) costs a whole row for something you learn once.

## Verdict

Yes, rework it. It's mostly a re-layout, not a redesign. The two columns (left: space and what you can do; right: what you hear) still make sense. What doesn't is the fixed plan size and a room panel that repeats the plan.

## Proposed layout (1280×720 baseline; scales up)

```
┌──────────────────────────────── 1280 ───────────────────────────────┐
│ ┌── PLAN (flexible, fills the space) ─────┐ ┌ IN THE HOUSE ────────┐ │
│ │ ?    ?    [KITCHEN]  ?                  │ │ newest first, 4 ln   │ │
│ │      ←L        ↑ ahead                   │ └──────────────────────┘ │
│ │ ?   (you →)  →R      📷 ☎               │ ┌ THE LINE  ● 0:57 ────┐ │
│ │      ↓ back                              │ │ status · scope (thin)│ │
│ └─────────────────────────────────────────┘ │ transcript (expands) │ │
│ ┌ KITCHEN · tries ●●● ────────────────────┐ │                      │ │
│ │ Search: [iron stove ◉] [Uncle Otto ♥] … │ │ [whisper………………… ]  │ │
│ │ [Hide H] [sneak] · clock ⏸ · fan ⏸      │ │ [Tap][Hang up] 1=yes │ │
│ └─────────────────────────────────────────┘ └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Changes
1. **A flexible plan** (`plan_view.gd`, `main.gd`): drop the fixed `BOX`. The plan expands to whatever the column has left, and `U`/`origin` are recomputed on `resized` (they already are per house). Minimum size about 420×300.
2. **Doors live on the plan** (`plan_view.gd`):
   - The current room's doors get small turn markers (←, →, ↑ ahead, ↓ back) drawn by each door, in the "you" colour.
   - Hovering a neighbouring room shows "East · → right · ?" (or its name, once known).
   - Clicking rooms and the arrow keys stay as they are.
   - The door-button row in the room panel goes. *Saves 64–98 px.*
3. **A compact room panel, two rows** (`room_panel.gd`):
   - Row 1: the room name, the tries left, and a busy bar on the same line.
   - Row 2: Search chips (◉/♥ tags stay, the legend moves to tooltips and F1 help).
   - Row 3: Hide/Come out as a toggle button, the sneak toggle, and the sound switches as short icon-plus-word chips ("clock: stop", "fan: off", "window: close"; the radiator only as a small state).
   - Target height about 130 px.
4. **The header moves into the line box** (`main.gd`): the call timer goes into the phone status row, and the title text into the window title. *Saves about 30 px on the left.*
5. **The right column:**
   - house box about 110 px
   - scope 46 → 30 px
   - the transcript expands
   - input and buttons always pinned at the bottom
6. **The window fits the screen** (`main.gd` `_ready`): on startup, size the window to about 80% of the usable screen at 16:9 and centre it (unless it's a dev run, or fullscreen was saved). With `canvas_items` stretch everything scales up crisply. F11 stays.
7. **A safety net:** a test in `tests/run_all.sh` that loads the scene at 1280×720 and also 1024×600, starts a game in EN, CS and the large house, and fails if any panel's bottom edge is past the viewport. That's the `layout.gd` check used for the numbers above.

### Not changing
- the two-column split (space | sound)
- the three looks
- the shader
- the phone panel's internals, apart from the scope height

## Verification
- The layout test passes for EN/CS × classic/large × 1280×720 and 1024×600.
- Screenshots of each look at 1280×720 and at 16:10 (1280×800).
- Hand check: walk using only the plan's turn markers while following her "left/right".
- `bash tests/run_all.sh`.

Estimated work: about 1–1.5 h.
