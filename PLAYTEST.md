# Playtest notes for the joint session

I (Claude) can't hear audio and can't really *feel* tension. This file lists what only you can judge, what I verified, and what I'd do next.

## 1. Please listen for

All sound is synthesised in `scripts/audio/synth.gd` and mixed in `scripts/audio/sfx.gd`.

| Sound | Where | What to judge | Knob |
|---|---|---|---|
| **Line hiss** (receiver up) | Line bus (300–3400 Hz + lo-fi) | Is it phone-like, and is it too loud? | `sfx.gd` `_process` hiss `-20` dB; `Synth.hiss_loop` |
| **Her "voice"** (formant mumble per ~3 letters) | Line bus | Cute? Creepy? Annoying? Female-ish? | `sfx.gd` `on_voice_char` (every 3rd letter, pitch); vowel table in `_generate` |
| **His voice** (taunts) | Line bus, pitch ×0.53 | Does it read as a low male voice? | same, `kind == "him"` |
| **Your room**: clock / fan / rain / radiator | Room bus, −9 dB | Recognisable? Balanced? | `Synth.clock_loop` etc.; `_process` target dB |
| **His room through the line** | Line bus, −20 dB | Can you tell "a second clock, out of step" by ear? | `line_amb` target in `_process` |
| **His footsteps** | Walls bus (low-pass 500 Hz + reverb) | Scary? Is the distance readable (0 / −12 / −22 dB)? Running vs walking (0.32 s vs 0.55 s gap)? | `sfx.gd` `"footsteps"` |
| **Clicks** (his pickup/hang-up, yours) | Line / Room | Distinct enough to make you jump? | `Synth.receiver_click` |
| **Breathing** | Line bus | Creepy or silly? | `Synth.breath` |
| **Heartbeat** | Master, by *perceived* danger | Too much? | `_process` heart volume |
| **Wrong exit crash** | Room | Loud enough to feel like a mistake? | `Synth.crash` |
| **Clock strike** (every 75 s) | Room or Walls | Nice bell or annoying? | `Synth.bell` |

## 2. Please judge (taste calls)

- **Visual style:** Blueprint, Phosphor CRT or Ink & Paper (F2 cycles). Which one, or a mix?
- **Difficulty:** is "patient" (normal) fair? Bots lose most games, but bots are dumb. Values are in `Game.DIFFICULTY`.
- **Her guess box** (F4): helpful, or does it break immersion?
- **Hints** (blue "»" lines): too many, or too few?
- **Taunts:** "Tick. Tock." when he's sure. Fun or too much of a giveaway?
- **The plan shows all sound icons.** Too easy? The alternative is that only visited rooms show them.
- **Game length.** I estimate 3–6 minutes per game.

- **Czech texts** (title → Čeština): I'm not a native speaker. Please proofread `scripts/core/loc.gd`, `House.CS_*` in `house.gd`, `MockRescuer.L` and the intro in `main.gd`. Nicknames: Pan Knoflík, Kapitán, Starý Řehoř, Duchovka, Pípův palác.

## 3. Verified by me

- Headless simulations of the core loop (`tests/sim.gd`), thousands of bot games.
- Screenshots of all three styles, the title, the game-over notebook and the line scope.
- The Haiku rescuer through the local proxy, end to end in the game (≈5–6 s per reply). A full LLM bot game is in section 5.

## 4. Known issues / limitations

- Balance is based on bots only.
- The mock rescuer is simple: one direction per turn, and it doesn't play along with lies.
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

**Haiku rescuer:**
- Full bot game: in character and cautious, using yes/no tap questions.
- Spotted a lie: *"Was that for his ears? One tap for yes."*
- After a prompt tweak she's direct when the line is clear: *"Go through the east door… Search the shelf of jam jars, and only that."*
- Czech full game: *"Hýbej se. Hned, potichu, a nemluv."* in reply to his taunt.
- About 15 calls used in total, all logged in `proxy/calls.log`.

**Open question:** a good game lasts 1.5–3 minutes. That's short and replayable. Is that right for the jam, or do we want a bigger house?

## 6. Suggested next steps for the joint session

1. Play 3–4 games with the scripted voice, then 2 with Haiku. Tune difficulty.
2. Audio pass (section 1).
3. Pick a style, and polish it further.
4. Plug in the real API endpoint (`rescuer_config.cfg`).
