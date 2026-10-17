# Decisions log

Non-trivial choices made during the autonomous phase. Each entry: what, why, and how to undo it.

## Scope and structure

- **One floor, 9 rooms in a 3×3 grid, 11 doors.** There are 6 phone rooms; the Nursery, Conservatory and Pantry have no phone. Dead ends (Conservatory, Pantry via Dining…) add tension. *Why:* small enough to read at a glance, big enough that 6 phones on one line make "where is he listening?" a real question.
- **Everything is built in code.** `main.tscn` is a single node, and the UI, audio buses and sounds are all built in GDScript. *Why:* faster to iterate on as an agent, with no editor needed.
- **The core logic is pure `RefCounted`** (`scripts/core/`), driven by `tick(dt)`. *Why:* it can be simulated headless (`tests/sim.gd`) for balance work.

## Information model (the heart of the design)

- **Room names and the floor plan are public knowledge,** to the player, the rescuer and the murderer alike. Saying "kitchen" is always unsafe.
- **Objects** (3 per room) are known to the player only after visiting, to the rescuer always, and to the murderer only after he has entered that room.
- **Childhood nicknames** ("Mr. Buttons", "Captain", "Old Gregor", "the ghost lift", "Pip's palace") are known to the rescuer, and to the player only after seeing the object (a memory pops up). The murderer *never* knows them. This is the "shared memories" idea from DESIGN.md and gives a permanently safe channel. Only 5 of the 27 objects have one, so it isn't always enough.
- **Sound features** (clock, fan, rain window, radiator) are shown on the plan for every room. *Why:* without it the deduction game is unreadable. The player still has to work out which room a background sound comes from.
- **Feature dynamics:**
  - Clocks can be stopped, fans switched off, windows closed. Each takes 2 s and makes a click.
  - Rain stops and starts globally. The heating cycles, so the radiator clanks only sometimes.
  - Clocks strike every 75 s.
  - *Why the radiator cycles:* simulations showed an always-on radiator was a near-unique fingerprint.
- **Directions are compass-based** (north/east/south/west doors), not left/right. *Why:* the plan is top-down, so there's no ambiguity, and the murderer can apply them to his candidate rooms.
- **Who hears whom:**
  - The rescuer hears the whole line: all backgrounds mixed and unattributed, plus every click.
  - The player hears the murderer's room through the receiver (shown as "ON THE LINE — also: …").
  - The murderer hears the player's background after `identify_time` seconds of overlap.

## The murderer (pure code, `scripts/core/murderer.gd`)

- He keeps a **set of candidate rooms**. Evidence filters it:
  - footsteps (distance only)
  - background sounds (a subset match; absence is weak evidence, because features can be switched off)
  - room or object words he knows
  - compass words, used only once he has ≤4 candidates
  - clicks and taps on the line (the player is at a phone)
  - touched clocks, fans or windows he finds ("someone was here")
  - loud crashes
- **Cycle:** go to a phone (not one used recently) → listen 12–20 s → hunt if ≤2 candidates. After a *fruitless* listen he **sweeps**: he walks to a nearby candidate room to look, then goes back to listening. *Why:* the first full LLM game showed him hogging the line for 2+ minutes by hopping between phones. That was boring, and it isn't the listen-or-search dilemma from DESIGN.md. Sweeps free the line and put him on the prowl. A player who stays silent and hidden is now found after ~6 minutes on average, which works as a soft time limit.
- **You always get a cue before he can reach you:**
  - footsteps when he sets off from within 2 rooms
  - footsteps when he enters a room within 2 (within 3 if he's running to hunt)
  - a direction with every cue
  - **presence cues** (creaks, breathing behind a specific door) when he stands still next door
  - *Why:* two of my hand-played games ended with walking into him with zero warning.
- **Deaf while walking:** his own boots mask your footsteps. *Why:* without this he simply chased by ear and won ~95% of simulated games.
- **The rescuer's words make rooms "suspects".** He thoroughly searches suspects (5 s), and if the exit is there he finds it, then **guards it**, listening on that room's phone if it has one. A fresh, exact lead lures him away for a moment, so lying is your weapon in the finale.
- **Fake hang-up** (25% on normal): a click, but he keeps listening for 5–8 s. The tell is that his room's background stays on the line, and half the time a text hint appears.
- **His notebook** (`murderer.log`) is shown after the game, so every death is explainable.

## Player verbs

All of the verbs from DESIGN.md are implemented:
- talk (type)
- go silent
- lie (it's just text)
- tap (1 = yes, 2 = no)
- move, plus **sneak** (slower, rarely heard)
- change room sounds
- listen (the status bar shows foreign sounds)
- hang up
- "Here it is!" (search an object, with a confirm click)

**Added: Hide.** If he only passes through, there's a low chance he finds you; if he came for your room specifically, the chance is high; a small chance per 5 s while he lingers. *Why:* accidental patrol run-ins were unfun deaths with no counterplay, and hiding while footsteps enter the room is a great horror beat.

- **Exit rules:** 3 tries in total. A wrong try is a loud crash: he learns your exact room, and you **freeze for 3 s** while it echoes. The third wrong try is a loss ("too much noise"). *Why the freeze:* with 3 objects per room, brute force was free. Now it's a real gamble if he isn't far away.
- **The exit is 3 rooms from the start when possible** (otherwise 2). He never starts in the exit room, and an attentive player can use that.

## Rescuer

- **Mock rescuer:** scripted. It uses only the line log and never the player's true position. It's deliberately a bit leaky, which makes it a good sparring partner for the murderer.
- **LLM rescuer:** Haiku via the local proxy (`claude -p --model haiku`, no tools, no MCP, no settings, in an empty temp dir), or an API endpoint from `rescuer_config.cfg`.
  - Output is JSON `{thinking, say, guess_room}`.
  - `say` is trimmed to 240 chars and stage directions are stripped.
  - Any failure falls back to the mock *for that turn only*.
  - Measured latency is 5–6 s per call, framed as "…the line crackles".
- **Her guess** is drawn as a dashed rectangle on the plan (F4 toggles it). *Why:* it makes the imperfect partner legible ("she thinks I'm in the Library").
- **She is "Mara", the player's older sister.** The player has no name or gender.

## Presentation

- **Text-only voice:** typewriter lines plus a procedural formant "mumble" through the phone band-pass bus.
- **Three visual styles,** switched with F2 or on the title screen. All are procedural, with one post-process shader:
  - Blueprint: navy, white lines, grain
  - Phosphor CRT: green, barrel distortion, scanlines, glow, jitter while on the line
  - Ink & Paper: wobbly "boiling" lines, paper fibres, red ink
- **The danger vignette and heartbeat react only to *perceived* cues** (footsteps, clicks, breathing), never to hidden state.
- **Fonts:** a system font (DejaVu Sans Mono or Serif, falling back to whatever is installed). No font files are shipped.

## Difficulty

Three presets (`Game.DIFFICULTY`): gentle "slow-witted", normal "patient", and hard "sharp-eared". They change:
- how long he must listen to identify a background
- the hunt threshold
- the chance he hears footsteps two rooms away
- the fake hang-up rate
- the chances he finds you hidden

Bot simulations are only a rough guide. The bots are much dumber than a human (`tests/sim.gd`).

## Testing method

- `tests/sim.gd`: thousands of headless bot games. The bots are poor players, so only trends matter.
- `tests/play_cli.gd`: **I played games by hand** in text mode, perceiving only what the player perceives. I won 2 of 5 games. The 2 unfair deaths (no warning) led to the cue fixes above. Wins came from deduction, silencing rooms, reading the fake hang-up tell, and lucky misdirection from overheard words.
- `tests/llm_game.gd`: a full real-time game with the Haiku rescuer (4 calls), plus scripted prompt checks via `tests/dump_prompt.gd` and curl.

## Language: English plus Czech (stretch goal reached)

- **`Loc` (`scripts/core/loc.gd`):** a simple key → [en, cs] table. The language is toggled on the title screen and saved.
- **Czech house data** (`House.CS_ROOMS`, `CS_OBJECTS`, `CS_EXIT_FLAVOR`) includes case forms: nominative, "v knihovně", "do knihovny". This avoids broken declension like "v místnosti Knihovna".
- **The parser is bilingual and stem-based.** Words are folded (lower case, no diacritics), and keys ending in `*` are prefixes. So "kuchyň / kuchyni / kuchyně" all match `kuchyn*`. The murderer understands both languages at once.
  - *Kept on purpose:* Czech "východ" means both "east" and "exit", so asking "kde je východ?" makes him think you're heading east. The LLM is warned about it.
- **Shared memories in Czech use "you two" plural** ("Oba jste přísahali…"), so the player's gender is never fixed.
- **The LLM** gets the English system prompt plus a Czech section: whisper in informal Czech, using the Czech names and nicknames. Tested: *"Jdi jižními dveřmi do spíže. Prohledej police se zavařeninami, máš tři pokusy."*
- **Bug found on the way:** the English dumbwaiter had the keyword "lift", which made its nickname "the ghost lift" unsafe. Removed.
