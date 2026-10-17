# I Won't Tell You (To ti neřeknu)

A party-line horror game for a jam. You're hiding in an old house with a murderer. Your sister knows a secret way out and is talking you there over the phone. But every phone in the house is on the same line, and **he's listening on another extension.**

| | |
|---|---|
| ![Title](docs/title.png) | ![Blueprint](docs/blueprint.png) |
| ![Ink & Paper, Czech](docs/ink_cs.png) | ![Phosphor CRT, post-game reveal](docs/phosphor_reveal.png) |

See [DESIGN.md](DESIGN.md) for the original concept, [DECISIONS.md](DECISIONS.md) for what was built and why, and [PLAYTEST.md](PLAYTEST.md) for what to try.

## Run

```sh
godot --path .            # Godot 4.7, the Compatibility renderer
```

On the title screen, pick:
- a **look**: Blueprint, Phosphor CRT or Ink & Paper
- **her voice**: scripted, Haiku proxy or API
- how sharp **he** is
- the **plan mode**: all sounds known, or learned by exploring
- **hints**
- the **house**: large (12 rooms), and/or rearranged (new doors, phones and sounds every call)
- the **language**: English or Čeština

### In game

| Input | What |
|---|---|
| Click a neighbouring room / door buttons / arrows or WASD | walk (shift, or the toggle, to **sneak**: slower, rarely heard). The keys work when the text field isn't focused (Esc leaves it, Enter returns) |
| H | hide |
| Type + Enter | whisper into the receiver (only while on the line, in a room with a phone) |
| Ctrl+T / Tap | tap the receiver (1 = yes, 2 = no) |
| Ctrl+H / Hang up · Pick up | the receiver |
| Search buttons | try an object as the hidden exit (click twice; a wrong try is LOUD; 3 tries) |
| Sounds buttons | stop the clock, switch off the fan, close the window |
| Hide | hide in the room (hangs up) |
| F2 | cycle the visual style |
| F3 | cheat/debug: show the murderer, his candidate rooms, the exit and his thoughts |
| F4 | show or hide her guess of where you are |
| F11 | fullscreen |
| Esc | put the call on hold (pause) |

## Her voice: Claude Haiku through the local proxy

```sh
python3 proxy/rescuer_proxy.py     # listens on 127.0.0.1:8765
```

Then choose **"Claude Haiku (local proxy)"** on the title screen.

- The proxy runs `claude -p --model haiku` with all tools disabled, no MCP servers, no settings, in an empty temp directory.
- Each call takes about 5–6 s; the game shows "…the line crackles".
- Every call is logged to `proxy/calls.log`.
- If the proxy is down, she falls back to the scripted voice for that turn.

## Her voice: API endpoint

Copy `rescuer_config.example.cfg` to `rescuer_config.cfg` (gitignored), fill in the URL and key, and choose **"API endpoint"**.

Two formats are supported:
- Anthropic Messages (`format="anthropic"`)
- The same simple `{system, prompt} → {text}` as the proxy (`format="simple"`, with a Bearer key)

## Dev tools

```sh
# Headless balance simulation: bot player + scripted rescuer vs the murderer
godot --headless --path . -s tests/sim.gd -- 300 smart q normal   # policies: random follow careful smart silent

# Screenshot harness
godot --path . -- --play --style=ink --seed=3 --at=8 --shot=/tmp/x.png [--debug] [--backend=proxy] [--say="..."]

# Export every synthesised sound to WAV (to listen to or analyse)
godot --headless --path . -s tests/export_audio.gd -- /tmp/wavs

# Play in text mode (perceive only what the player perceives); append commands to cmd.txt
godot --headless --path . -s tests/play_cli.gd -- cmd.txt <seed> normal

# Dump the rescuer prompt for a scenario
godot --headless --path . -s tests/dump_prompt.gd -- out.json "[background on the line: ticking clock]" "player line"
```

## Layout

```
scripts/core/     house.gd (rooms, doors, objects) · game.gd (fast loop, hearing, win/lose)
                  murderer.gd (belief state machine) · words.gd (keyword parser)
scripts/rescuer/  mock_rescuer.gd · llm_rescuer.gd (prompt + parsing + HTTP)
scripts/ui/       plan_view.gd · phone_panel.gd · room_panel.gd · style.gd
scripts/audio/    synth.gd (offline synthesis) · sfx.gd (buses: Room / Line / Walls)
shaders/          post.gdshader (blueprint / CRT / ink + danger vignette)
proxy/            rescuer_proxy.py
tests/            sim.gd · dump_prompt.gd
```
