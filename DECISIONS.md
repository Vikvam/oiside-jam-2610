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

**Added: Hide.** If he only passes through, there's a low chance he finds you. If he came to hunt or search your room, the chance is high. If he's sweeping or coming to use your room's phone, it's in between. There's also a small chance per 5 s while he lingers. Searching or touching the room's sounds brings you out of hiding (and if he's in the room, he gets you). *Why:* accidental patrol run-ins were unfun deaths with no counterplay, and hiding while footsteps enter the room is a great horror beat.

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

## Code review pass

A reviewer agent found 11 issues, all fixed:
- the murderer could get stuck "hunting" his own room
- the first game after launch was always the same, because the demo house had seeded the RNG
- the game-over panel could pop over the title or the next game
- input and audio stayed live while paused or on the title
- hidden-state buttons silently did nothing
- a stale "crackle" indicator and a half-armed search carried into the next game
- reference cycles leaked every finished game (fixed with `Game.dispose()`)
- hide chances didn't match this document

## Later additions (still autonomous phase)

- **Rearranged house** (title toggle, off by default): each call gets a random spanning tree of doors plus 2–3 loops, 6 random phone rooms and random room sounds. Names, positions and objects stay, so memories still make sense. *Why:* replayability once players have learned the house.
- **Endings:** a flash (warm light if you escape, red if caught) and one closing line of narration before the reveal.
- **He imitates her voice, on "sharp-eared" only.** When he's down to ≤3 candidate rooms and you're on the line, he may whisper a fake direction that leads toward him (at most once a minute). The tells are fair:
  - there's no "…line crackles" first
  - his room's sounds are on the line
  - the mumble pitch is lower
  - the text is in italics
  - she hears it and warns you ("That wasn't me!")
  - *Why:* DESIGN.md asked "Do they try to imitate the rescuer?". This answers it without making normal play unfair.
- **The offline voice plays along with lies.** If you name a room while he's on the line, she backs you up once ("Okay. Stay in the Library…"). He hears her too, which makes the lure stronger.
- **Post-game:** your route is drawn on the map next to his, and a "Look at the call" toggle lets you reread the transcript.
- **Large house** (title toggle): a fourth column with the Billiard Room, Music Room and Bathroom, with full EN/CS content and two more nicknames ("the Cyclops", "the Singing Box"). The plan scales and centres itself automatically. In simulations games last longer, and a silent player survives about 14 minutes.
- **Keyboard play:** arrows/WASD walk, Shift sneaks, H hides, Enter focuses the whisper field, and Esc leaves it. The text field is focused when a call starts, because typing is the main verb.
- **Second review pass**, all fixed:
  - large-house room words could crash the 9-room house (the parser now filters by the actual house)
  - "Look at the call" couldn't scroll
  - the first ringback was muted
  - games ending during an action leaked
  - over-broad Czech stems
  - the drone couldn't really be disabled
  - dev runs touched the settings file
  - you could pass *through* him in a doorway (now: meeting him head-on in the door you're walking through gets you caught)
- **The offline voice no longer blindly assumes you followed her.** After you pick up, she accepts her guess only if the background sounds confirm it. Otherwise she asks: "Did you make it — the room I sent you to? One tap yes, two no." *Why:* in two hand-played games her stale guesses sent me the wrong way with confidence.
- **Volume is a mechanic:** typing in ALL CAPS is shouting. He hears it through walls up to two rooms away, with no phone needed. *Why:* DESIGN.md asks "Is volume a mechanic (whispering vs. talking)?" This is the cheapest readable answer, and it rewards whispering.
