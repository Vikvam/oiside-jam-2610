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
- **Defaults chosen by the user (04:35):** Phosphor CRT look (Blueprint and Ink stay one F2 away; to be decided after playing), gentle difficulty, the classic 9-room house. The autonomous phase is paused here, at the user's request, to wait for the joint session.

## Joint session, round 1 (after the user's first 4 playtests: 0 escapes)

The logs showed four problems: he moved during her 35 s intro, hiding was a hidden dice roll, he wandered blindly ("Nothing on the line. I'll go look…"), and Haiku played 20 questions instead of guiding. The user's answers set these changes:

- **He waits for her intro.** It's two lines now. He wakes when it ends or when you first act (speak, tap, move, hide).
- **She gives the way out straight away, as a riddle.** Every room now has one childhood-nicknamed object (5 new: Doctor Skull, the Other Room, the Jellyfish, Granny's museum, the Dragon's Throat). Her first line is "the way out is in the room with Old Gregor; search the china cabinet there." You only learn which room has which nickname by going there, so the game becomes finding it while he hunts you. She no longer needs to know where you are. *Why:* the user asked "why wouldn't she just tell me it's in the Řehoř room?"
- **Uncertain childhood objects** (user's idea). Small things may have been carried off: the bear, the globe, the birdcage and the gramophone each have a 50% chance of sitting in their other room. Captain the horse never moves, but she isn't sure which room he hung in. She hedges ("if nobody moved it"). When you see a moved one, your memory adds "(Wasn't it always in the nursery?)". The exit itself is never movable or obvious.
- **Obvious furniture is understood everywhere:** the bathtub, stove, piano, bookcase, desk, billiard table and so on, marked ◉ in the room panel. *Why:* "he ignores 'vana'? That seems stupid." Nicknamed objects are marked ♥.
- **Hiding has one visible rule, no dice.** If he only passes through, he doesn't see you while you keep still. If he came FOR your room, he searches it: a loud warning, then you're found after 5/4/3 s (gentle/normal/hard) unless you slip out another door. Running footsteps now say "Straight for this room!" H toggles hiding (Hide ↔ Come out).
- **He's a listener.** An empty listen sends him to another, preferably distant, phone. He only sweeps rooms after two empty listens in a row. On gentle he walks about 35% slower (5.5 s per room).
- **Two channels, two boxes.** The phone box shows only the line. Footsteps, creaks, your own movements and memories go to an "IN THE HOUSE" box above it, newest on top.
- **Marks for what he heard.** Live: a `──── click — someone picked up ────` rule, then a red bar and shaking text until a hang-up click. This is your own perception, so a fake hang-up fools it. After the call, ◉ marks every line he really heard, and the game log tags them `[HEARD]`.
- **Haiku prompt:** riddle first. Never ask "is he in the room with you". At most one yes/no question in a row. Czech is required up front when playing in Czech.
- Sims (careful bot that has to explore to find nicknames): about 50% escapes on gentle and normal, versus about 5% before.

## Joint session, round 2: CCTV (replaces the riddle)

The riddle-first rescuer overcorrected. The user's next two games were won in 31 s and 1:26: the nicknames described their objects ("the Singing Box" is obviously in the Music Room), and her first, always-safe line gave everything away. The user proposed DESIGN.md's open "CCTV" idea, and we chose these variants together:

- **She watches grainy cameras in about half the rooms** (camera icon on the plan). She sees a *figure move*, never who. Standing still, nobody shows up. *Why:* she needs her own information all game long, or the call stops mattering. Blind rooms and motion-only mean your ears still matter.
- **She works out which figure is you.** A figure moving while your receiver is up must be him. Otherwise she asks one tap question ("did you just come through a door?"), or uses your words, nicknames and background sounds as before.
- **She guides one door at a time, around him** (her route avoids his last sighting and the rooms next to it). She warns you when he's next to you ("he's right behind the door on your left"). She doesn't say the exit until you're in its room. A room with no phone gets two steps at once.
- **Directions in three registers** (user's call: "a mix of all 3"):
  - compass when the line seems quiet
  - turns relative to the way you face (an arrow on your dot; doors labelled "← left · West → …") when he may be listening
  - a nickname of a room she thinks you've seen
  - *Why:* compass words tell a listener you're not in an edge room. Turns are useless without your heading.
- **Opaque nicknames:** the ghost lift → Uncle Otto, the Singing Box → Aunt Vera, Granny's museum → Fort Knox.
- **The scripted voice is her brain; Haiku is an optional voice.** In Haiku mode the script still decides. Haiku only rephrases the draft and suggests a room from your free text. `safe_rephrase` rejects any new room, object or compass word. Warnings skip Haiku entirely. *Why:* about 7 s of latency is fatal for "he's behind your door", and code reasons about two anonymous figures reliably.
- **New cue: "Footsteps go out through the north door… He's gone — for now."** It plays when he has actually left your room (not when he starts walking), so you know when to come out of hiding.
- **He gets bored of guarding a found exit** after 40 s and goes hunting for 45 s. *Why:* the soak found a stalemate.
- Tests always use the scripted voice (`run_all.sh` passes `--backend=mock`), so they never spend the user's Haiku usage.
- Sims: careful bot 44% escapes on gentle (median 52 s), 36% on normal. The smart bot gets 53% on gentle with a median of 3 minutes.

## Joint session, round 3: fog of war, her guess out loud, backing out

After 5 more games (0 escapes) the user asked for:
- **Fog of war:** you don't know room names (or their sounds and contents) until you've been inside. The plan shows walls, doors, phones and cameras, with "?" for unknown rooms, and door buttons say "→ ?". The title's "plan" toggle is gone. *Why:* you can't say "kitchen" if you don't know it's the kitchen, so describing what you see becomes the game.
- **She says where she thinks you are**, by something only you can check: "You're where the Jellyfish is, right?" She uses the nickname if that room has one she's sure of; otherwise an unremarkable object, but never while he may be listening. The dashed "her guess" box is off (F4 still shows it, as a debug aid).
- **Walking into him isn't instant death on Gentle and Normal:** you see him in the doorway and stumble back, and he knows exactly where you are and comes for you. Run or hide. Hard keeps instant death.
- She warns when he's off the cameras ("listen at the door before you open it"). She no longer says "west, then west". The Czech yes/no questions are fixed ("Máš v té místnosti hodiny?").
- Sims: about 50–60% escapes on gentle, 35–50% on normal.

## UI rework (after round 3)

The user couldn't play: at 1280×720 the left column needed 725–775 px of 688, which pushed the phone's text field and buttons off-screen. Review and plan: UI_REWORK.md. Done:
- **The plan is flexible** (`PlanView._fit` on resize) and fills the space the room panel leaves. No more fixed 624×468 box.
- **Doors live on the plan:** turn markers (← left, ↑ ahead, → right, ↓ back) inside each door of your room, and the hover label says "→ right · East". The door-button row is gone; clicking and the arrow keys are unchanged. Your own room's object list isn't drawn on the plan (it's in the room panel).
- **Compact room panel, two rows:** Search chips; then Hide/Come out, sneak (Shift) and the sound switches. The ◉/♥ legend moved to tooltips and help.
- **The title and call timer moved to the right column**; the house box is 112 px and the line scope 30 px.
- **The window opens at about 80% of the usable screen (16:9)** when that's bigger than 1280×720, for the user's 4608×2880 display.
- **`tests/layout.gd`** (part of run_all) fails if the plan, the room panel rows, the house box, the phone, the text field or the Tap/Hang-up buttons leave the 1280×720 view, in EN/CS × classic/large. With aspect "expand" the virtual screen is never smaller than 1280×720, so that's the worst case.
