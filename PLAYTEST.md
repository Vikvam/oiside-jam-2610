# Playtest notes for the joint session

I (Claude) can't hear audio and can't really *feel* tension. This file lists what only you can judge, what I verified, and what I'd do next.

## 1. Please listen for

All sound is synthesised in `scripts/audio/synth.gd` and mixed in `scripts/audio/sfx.gd`.

| Sound | Where | What to judge | Knob |
|---|---|---|---|
| **Line hiss** (receiver up) | Line bus (300–3400 Hz + lo-fi) | Is it phone-like, and is it too loud? | `sfx.gd` `_process` hiss `-20` dB; `Synth.hiss_loop` |
| **Her "voice"** (formant mumble per ~3 letters) | Line bus | Cute? Creepy? Annoying? Female-ish? | `sfx.gd` `on_voice_char` (every 3rd letter, pitch); vowel table in `_generate` |
| **His voice** (taunts) | Line bus, pitch ×0.53 | Does it read as a low male voice? | same, `kind == "him"` |
| **His imitation of her** (hard only) | Line bus, pitch ×0.82 | Is it subtly "off" but not obvious? | same, `kind == "fake"` |
| **Your room**: clock / fan / rain / radiator | Room bus, per-feature dB | Recognisable? Balanced? | `Synth.clock_loop` etc.; `Sfx.FEATURE_DB` |
| **His room through the line** | Line bus, `FEATURE_DB` −12 dB | Can you tell "a second clock, out of step" by ear? | `line_amb` target in `_process` |
| **His footsteps** | Walls bus (low-pass 500 Hz + reverb) | Scary? Is the distance readable (0 / −12 / −22 dB)? Running vs walking (0.32 s vs 0.55 s gap)? | `sfx.gd` `"footsteps"` |
| **Clicks** (his pickup/hang-up, yours) | Line / Room | Distinct enough to make you jump? | `Synth.receiver_click` |
| **Breathing** | Line bus | Creepy or silly? | `Synth.breath` |
| **Heartbeat** | Master, by *perceived* danger | Too much? | `_process` heart volume |
| **Wrong exit crash** | Room | Loud enough to feel like a mistake? | `Synth.crash` |
| **Clock strike** (every 75 s) | Room or Walls | Nice bell or annoying? | `Synth.bell` |
| **Mood drone** (55 Hz, slowly beating, louder with danger) | Master | Adds dread, or just mud? | `Sfx.DRONE_DB_CALM/DANGER` (−80 turns it off), `Synth.drone` |
| **Ringback** at the start (425 Hz) | Line | Does it set the scene? | `Synth.ringback`, `Sfx.ring_in` |

## 2. Please judge (taste calls)

- **Visual style:** Blueprint, Phosphor CRT or Ink & Paper (F2 cycles). Which one, or a mix?
- **Difficulty:** the default is "slow-witted" (gentle). Is "patient" (normal) fair? Bots lose most games, but bots are dumb. Values are in `Game.DIFFICULTY`.
- **The coiled phone cord** (drawn while you're on the line): charming, or clutter?
- **Large house / rearranged house:** should either be the default?
- **Her guess box** (F4): helpful, or does it break immersion?
- **Hints** (blue "»" lines): too many, or too few?
- **Taunts:** "Tick. Tock." when he's sure. Fun or too much of a giveaway?
- **The plan shows all sound icons.** Too easy? The alternative is the "learn sounds by exploring" toggle.
- **Game length.** My hand-played games lasted 1–2 minutes (small house). The large house is longer.

- **Czech texts** (title → Čeština): I'm not a native speaker. Please proofread `scripts/core/loc.gd`, `House.CS_*` in `house.gd`, `MockRescuer.L` and the intro in `main.gd`. Nicknames: Pan Knoflík, Kapitán, Starý Řehoř, Duchovka, Pípův palác, Kyklop, Zpívající skříňka.

## 3. Verified by me

- Headless simulations of the core loop (`tests/sim.gd`), thousands of bot games, including large and rearranged houses.
- A GUI soak test (`--soak=N`) that autoplays random combinations of language, style, difficulty and house, with no script errors.
- 9 hand-played text-mode games (section 5).
- The API code path (Anthropic Messages format), against a local fake endpoint: headers, model, parsing.
- Keyboard input, with synthetic key events.
- Screenshots of all three styles, the title, the game-over notebook and the line scope.
- The Haiku rescuer through the local proxy, end to end in the game (≈5–6 s per reply). A full LLM bot game is in section 5.

## 4. Known issues / limitations

- Balance is based on bots and my hand-play only.
- If you talk during her intro, her replies interleave with the remaining intro lines.
- The mock rescuer is simple. It gives one direction per turn, and its guess can go stale (it believes you followed its directions). It plays along with a lie once per eavesdrop.
- Web export is untested. `SystemFont` falls back to Godot's default font there, and the proxy sends CORS headers.

## 5. What I learned from testing

**Hand-played text-mode games** (`tests/play_cli.gd`, normal difficulty):
1. **Won in 55 s**, but it was too easy. The exit was only 2 rooms away, and brute-forcing objects was free. Fixed: the exit is 3 away, and a wrong try freezes you.
2. **Walked into him with no warning.** He was standing still next door. Fixed: presence cues.
3. **Caught by a sweep** after a 4 s footsteps warning that I wasted. Fair.
4. **Caught with no warning.** He set off from the room next door. Fixed: footsteps when he sets off.
5. **Won.** I worked out the exit from where he set off, silenced rooms, and read a real hang-up (his sounds vanished from the line). My "the room east of me" plus her "east door" sent him running the wrong way, and he was behind the Pantry door when I got out. *This is the game working as designed.*

6. **Won on gentle (default) in 1:44.** I lied ("I'm in the pantry"), but it was too late: he'd hung up mid-sentence. I waited silently while he listened next door, slipped past him by one second, and the mock named the object. His notebook shows a funny misdirection: her word "rocking **horse**" matched the *painting of a horse* he'd seen, so he went to inspect the Study.
7. **Czech, normal: caught.** "jsem ve spizi" fooled him ("Kořist to zmínila → možná: Spíž"), but his route to the Pantry ran through the Kitchen I'd just entered. Leaving as he entered counted as caught. Fixed: you slip out if you're past the halfway point of the doorway.

8. **Hard: won in 1:28.** He was standing next door in the Kitchen at the start. Since he never starts in the exit room, I deduced the Pantry. I sneaked the long way round, hid, and then asked her for the object from the Dining Room while he listened. Object names from rooms he hasn't searched are safe, and she named the meat hook.

9. **Large house, normal: caught.** A lie ("im in the library") sent him running across the house, and the fake hang-up tell showed. But the mock's stale guess pointed me to the wrong room, and two brute-force crashes brought him running back. Fixed: the mock now rejects impossible positions (no phone there, or the sounds don't fit). *Brute force with him 2–3 rooms away is death. That's good.*

**Haiku rescuer:**
- Full bot game: in character and cautious, using yes/no tap questions.
- Spotted a lie: *"Was that for his ears? One tap for yes."*
- After a prompt tweak she's direct when the line is clear: *"Go through the east door… Search the shelf of jam jars, and only that."*
- Imposter test: *"That was not me. Do not move on that voice. Tap once if you can hear me."*
- Czech full game: *"Hýbej se. Hned, potichu, a nemluv."* in reply to his taunt.
- About 15 calls used in total, all logged in `proxy/calls.log`.

**Open question:** a good game lasts 1.5–3 minutes. That's short and replayable. Is that right for the jam, or do we want a bigger house?

## 6. Suggested next steps for the joint session

1. Play 3–4 games with the scripted voice, then 2 with Haiku. Tune difficulty.
2. Audio pass (section 1).
3. Pick a style, and polish it further.
4. Plug in the real API endpoint (`rescuer_config.cfg`).
