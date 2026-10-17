# Goal

Build a playable Godot game from [DESIGN.md](DESIGN.md) ("To ti neřeknu" / "I won't tell you"), working autonomously for up to **~12 hours**. After that, the user and Claude iterate together for ~10 more hours.

- Start: 2026-10-18 01:41 KST
- Autonomous phase ends: ~2026-10-18 13:45 KST
- Hard jam deadline: **~2026-10-18 23:40 KST** (just for fun, no submission rules)

## Hard constraints

- **Engine:** Godot 4.7 (installed: `/usr/bin/godot`, 4.7.2). GDScript.
- **Location:** Everything lives in this directory. Temp files go in the session scratchpad (or `/tmp`). The project is git-tracked; commit after each working slice.
- **Rights:** No third-party assets unless they're CC0/OFL and listed in `CREDITS.md`. Prefer procedural visuals (in game or pre-generated) and sound written in code. Godot's default font is fine.
- **Ethics / machine safety:** Touch only this directory, the scratchpad and `/tmp`. Don't read the user's other files, install system packages, or do anything the user wouldn't expect. **If something feels unexpected or questionable, stop and ask.**
- **Platform:** Linux desktop first; keep it web-compatible where it's cheap. Ignore exporting for now; it's fine to run from the editor or `godot --path .`.

## LLM usage

- The rescuer backend sits behind one swappable interface:
  1. **Mock rescuer** (scripted, no LLM). This is the default for automated tests and for most development.
  2. **Local proxy** (a small Python HTTP server) that runs `claude -p --model haiku`. **Only Haiku, only through this proxy.**
  3. **Real API.** The user will provide the endpoint and key later, so leave it as a config slot.
- Use the user's Claude usage reasonably: real LLM runs only to validate prompts and behaviour (a few dozen calls total), never in loops or bulk simulations.
- The LLM output is structured (JSON: what it says + its guess of where the player is). Code validates it and enforces all rules, including win and lose.

## Decisions already made

- **Language:** English (simplest for prompts, keyword matching and Haiku quality). Czech only as a stretch goal, e.g. the title and flavour text.
- **Voice:** Text only. Typewriter subtitles plus a procedurally synthesized "mumble" voice through a phone band-pass filter. No TTS.
- **Input:** Typing. Keystrokes may make faint clicks on the line.
- **Murderer:** Pure code. It keeps a belief state (a set of candidate rooms) and matches heard words by keyword against things it has seen and against directions. It doesn't speak; it only clicks and breathes.
- **Floor plan:** Visible to the player (exact presentation is open to A/B).
- **Cut for now:** CCTV, voice input, an LLM-driven murderer, the murderer learning tap codes.
- **Default exit rules** (tunable): 3 attempts; a wrong attempt makes a loud noise. If the murderer deduces the exit room, it heads there to block it, which makes a tense finale rather than an instant loss.

## Scope (decide dynamically)

Rough target: about 8 rooms, 4 sound features (e.g. clock, fan, rain, radiator) that can change over time or be switched off by the player, and 1–2 visual details per room. Claude adjusts the number of rooms, features and mechanics as playtesting suggests.

## Way of working

- **Vertical slices.** The game must be runnable after every slice. Suggested order (may change):
  1. Floor plan, movement, murderer patrol and search, lose condition
  2. Phone line, mock rescuer, the murderer listening in, win condition with exit attempts
  3. Sound features and deduction in both directions
  4. LLM rescuer through the Haiku proxy
  5. Mood: shaders, synthesized ambience, intro and outro
  6. Tuning and A/B
- **Iterate.** Write the game, test it (headless runs, scripted bot playthroughs, logs, viewport screenshots), then reevaluate and adjust. Claude can't hear the audio, so sound design is done "on paper" and kept easy to tweak.
- **Variants without branching.** A/B options for minor decisions or looks are settings toggles inside one project, not separate copies.
- **Visual style is a pickable option.** Make the look funky and distinctive. Prepare **2–3 procedural visual styles** (e.g. polygon/vector blueprint, CRT/phosphor, ink/paper) behind one switch, so the user can choose a vibe.
- **Decisions:** Decide and log non-trivial choices in `DECISIONS.md`. Ask the user only for irreversible or taste-critical decisions. It's OK to pause the goal while waiting for input.

## Done = (end of the autonomous phase)

- A complete playable loop from start to win or lose, with the mock rescuer and with the Haiku rescuer.
- A working murderer: belief state, listening, searching, and reacting to sounds, footsteps and words.
- Synthesized phone audio and room ambience.
- At least 2 selectable different visual styles.
- Docs:
  - `README.md` (how to run it, including the proxy)
  - `DECISIONS.md`
  - `CREDITS.md`
  - `PLAYTEST.md`, which lists what the user should listen for and judge, known issues, and suggested next steps for the joint session

You may also stop execution of the goal, if you detect an issue with feasability or security.
