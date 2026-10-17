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

## 3. Verified by me

- Headless simulations of the core loop (`tests/sim.gd`), thousands of bot games.
- Screenshots of all three styles, the title, the game-over notebook and the line scope.
- The Haiku rescuer through the local proxy, end to end in the game (≈5–6 s per reply). A full LLM bot game is in section 5.

## 4. Known issues / limitations

- Balance is based on bots only.
- The mock rescuer is simple: one direction per turn, and it doesn't play along with lies.
- No pause menu (Esc does nothing).
- Web export is untested. `SystemFont` falls back to Godot's default font there, and the proxy sends CORS headers.

## 5. LLM game log

(filled in below after the test run)

## 6. Suggested next steps for the joint session

1. Play 3–4 games with the scripted voice, then 2 with Haiku. Tune difficulty.
2. Audio pass (section 1).
3. Pick a style, and polish it further.
4. Plug in the real API endpoint (`rescuer_config.cfg`).
