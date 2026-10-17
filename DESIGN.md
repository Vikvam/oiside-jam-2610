# Design: "To ti neřeknu" (working title)

Game jam entry. Theme: **"To ti neřeknu"** ("I won't tell you").
Engine: Godot. AI-friendly jam, so an LLM is part of the game.

Status: concept / ideation. The core mechanism is fairly settled; many things are deliberately left open (see [Open questions](#open-questions)).

---

## Pitch

You are hiding in a large old house with a murderer. You've found a wired phone and called someone who knows the house, including **a secret exit the murderer doesn't know about**. They have to guide you to it.

But every room has a phone on the same line, and **the murderer is listening on another extension.**

> *"To ti neřeknu, protože nás odposlouchává."*
> ("I won't tell you, because they're listening to us.")

## Constraints we're embracing

- **Low / minimal / no assets.** Sounds synthesised in code, voices from TTS, very simple visuals.
- **Latency is a given.** An LLM responds in 1–3 s. The phone call and the horror mood turn this into a feature: pauses on the line are creepy, and the rescuer "is thinking".

## Roles

| Who | What | Knows | Wants |
|---|---|---|---|
| **Player** | Moves around the house, talks on the phone | What they see and hear in their room, what they hear on the line | Get to the secret exit |
| **Rescuer** (LLM) | On the phone, guides the player | The whole house, including the secret exit | Get the player to the exit without the murderer finding out |
| **Murderer** (code) | Moves around the house, listens on the extensions | The house layout, but *only the contents of rooms they have already searched* | Find the player, or find out where the exit is |

## The core mechanism

**Every piece of information you share leaks to the person you're sharing it with... and to someone else.** Communication is necessary, and it's also what puts you in danger.

### The murderer's dilemma: listen or search

All the phones in the house are on one line. Whoever picks up hears everything.

- **Listen:** the murderer stands by a phone and hears the conversation, but isn't moving.
- **Search:** they hang up and go where they think you are, but they've gone deaf.

So they cycle: **listen → think → move → pick up another phone → listen.**
The house is too big to search blindly, so the murderer needs information.

### The secret is locked by the player's position

The rescuer gives directions **relative to the player's position**: "go through the left door, then down the stairs."
That's useless to the murderer *as long as they don't know where the player is.*

- The more the murderer knows about where you are, the more each instruction gives away.
- Every step, every sound from your room and every word adds to what the murderer knows.

### Eavesdropping goes both ways

When the murderer is on the line, **the player hears their side too:**
- the **click** of the receiver being picked up or put down (or only *pretending* to be put down),
- **breathing,**
- the **background of their room** through the receiver.

And the murderer hears the player's background just the same. Silence alone isn't enough; the room can give you away.

### Room sounds are features, not fingerprints

Sounds are **not unique** to a room. For example, 4 of 12 rooms have a clock, some have a fan, some have a window with rain, and so on. A room is identified only by a **combination** of features, and even then not always uniquely.

Example (illustrative):

| Room | Clock | Fan | Window (rain) | Radiator |
|---|---|---|---|---|
| Hall | ✓ | | ✓ | |
| Study | ✓ | ✓ | | |
| Kitchen | | ✓ | ✓ | ✓ |
| Bedroom | ✓ | | ✓ | ✓ |
| … | | | | |

- On the line, the murderer hears "clock + rain", which leaves 2 candidate rooms, not 1.
- The player does the same thing back: "fan + radiator" behind the murderer means they're roughly *there*.
- **The sounds change over time:**
  - The player can turn off the fan, stop the clock and so on. That removes a feature, but takes time and makes a sound.
  - The clock strikes on the hour, so the clock rooms suddenly stand out.
  - When the rain stops, the window feature disappears.

### The murderer only knows what they've seen

The rescuer knows every room ("the room with the stuffed bear", "grandma's piano"). The murderer knows **only the rooms they've already searched.**

- Early in the game, visual descriptions are a safe channel.
- **As the murderer explores, the safe vocabulary shrinks.**
- That gives natural escalation: at the start you can talk in sentences; by the end it's taps and silence.

This works both ways: the player can describe their room to the rescuer ("I'm by a painting of a horse"), and it's safe only if the murderer hasn't seen that painting yet.

### The exit

- **One spot in one room** (e.g. behind a particular painting, under the floorboards by the stove).
- The player has **3 attempts** to declare "Here it is!" (or similar).
- A wrong attempt costs something. *What exactly, and whether it makes noise, is open.*

### Win / lose

- **Win:** the player finds the exit spot and gets out.
- **Lose:** the murderer reaches the player's room.
- **Lose / complication:** the murderer works out where the exit is. Whether they **block it** (a tense finale) or the player **loses instantly** is open.
- **Lose:** the player uses up all 3 attempts? (open)

## Player verbs

| Verb | Effect | Risk |
|---|---|---|
| **Talk** | Tell or ask the rescuer something | The murderer may be on the line |
| **Go silent** | Nothing leaks | The rescuer learns nothing; time is running out |
| **Lie** | E.g. "I'm in the attic" while the murderer is on the line, to lure them away | The rescuer may believe it too |
| **Tap** on the receiver | A quiet, non-verbal channel (yes/no, agreed codes) | Needs an agreed meaning; the murderer can learn it |
| **Move** to another room | Changes position and the acoustic background | Footsteps through the house |
| **Change room sounds** | Turn off the fan, stop the clock… | Takes time, makes a click |
| **Listen** | Work out from the line where the murderer is | Costs time |
| **Hang up** | Line is safe | Lose contact with the rescuer |
| **"Here it is!"** | Attempt at the exit (3×) | A wrong attempt (consequence open) |

**Lying is the key verb.** The eavesdropper isn't just a threat; the player can exploit them.

## The murderer: a belief state (code)

The murderer is **not an LLM**, but a transparent state machine with a **set of candidate rooms** where the player might be. They update it from:

- the sounds from the player's room heard on the line,
- footsteps through the house (direction, distance),
- words heard (descriptions of rooms *they know*, relative directions),
- rooms they've already searched.

Decisions:
- **Big set:** go to the nearest phone and listen.
- **Small set:** hang up and go search.

Why code: fair, predictable, debuggable, readable for the player ("I said *clock*, and he came"), and without the risk of an LLM that's "too smart".

*Optionally* an LLM could only interpret the heard words into a structured update of the belief state. Open.

## The rescuer: LLM

- **Input:** the full house plan, the location of the exit, the transcript of what it heard on the line, sound events (`[cvak]` = click, `[dýchání]` = breathing, `[hodiny utichly]` = the clock stopped…).
- **Output:** speech (TTS, phone-filtered), plus a **structured guess** at where the player is.
- **An imperfect partner, not an oracle:** it can get the player's position wrong, panic, talk too much, or be too cautious. That's drama, not a bug.

## Architecture principles

### Two speeds
- **The fast loop (code):** sound, the murderer's movement, noise, timing, all in real time.
- **The slow loop (LLM):** the rescuer's intentions and dialogue, every few seconds.

The LLM never sits on the critical path of real-time action. Its latency reads as "thinking" or "line delay".

### LLM guardrails
- The LLM gets **only filtered input**. Code decides what it heard.
- The LLM outputs **structured choices** (where it thinks the player is) alongside its speech.
- **Code enforces the physics** (movement, noise, who hears what) and **decides win and lose**, not the LLM.

## Assets and technology (minimal)

- **Synthesis in Godot** (`AudioStreamGenerator`): dial tone, busy signal, clicks, static, breathing, a clock, a fan, rain (filtered noise)…
- **Spatial audio** (`AudioStreamPlayer2D/3D`): footsteps through the house.
- **Bus effects:** band-pass filter (~300–3400 Hz) for the "phone" sound of the TTS (it also hides lower TTS quality), `LowPassFilter` for sounds through walls.
- **Voices:** TTS.
- **Visuals:** a phone, typewriter text, a CRT or grain shader. Possibly a floor plan (open).
- **LLM:** via `HTTPRequest`. Distribution needs a proxy (the API key can't go in the build).

---

## Open questions

### CCTV for the rescuer?
The rescuer could have access to the security cameras. Does that break the game (they'd see everything)?
- Variant: **the player has to tell the rescuer something first** before CCTV is any use, so "I won't tell you" goes both ways.
  - e.g. which figure on the cameras is the player, which camera to look at, or where the player is.
- Variant: cameras only in some rooms, or with poor image quality.
- Variant: the rescuer sees the murderer but not the player (or the other way round).

### The floor plan
- Does the player see the floor plan of the house? With a plan, sound deduction is a "map game". Without it, the player builds their mental map by ear (pure audio, but very hard).
- Do they see the room features (clock, fan…), or only hear them?
- Does the plan reveal itself gradually as the player explores?

### Secret leaks and win/lose
- Murderer learns the exit: do they **block it**, or does the player **lose instantly**?
- What does a wrong "Here it is!" attempt cost? Noise? Time? Is the third miss a loss?

### How does the rescuer know where the player is?
- Only from what the player says and what it hears behind them, so the same information as the murderer, plus knowledge of the house. Is that enough of an advantage?
- (Connected to the CCTV question.)

### Player input
- Typing (simple, reliable; each keystroke could be a click on the line) vs. voice over the mic (immersive, more work, STT latency on top of LLM latency) vs. typing by default with the mic as a bonus mode.
- Is volume a mechanic (whispering vs. talking), or only content and timing?

### The murderer
- Pure code, or an LLM for interpreting words, or for talking ("Vím, že tam jsi." = "I know you're there.")?
- Does the murderer speak on the line at all? Do they try to imitate the rescuer?
- Do they learn the agreed tap codes?

### How does the rescuer tell the truth from a lie?
- They hear what the murderer hears. Options: they also notice the `[cvak]` (click), a pre-agreed signal, shared memories (*"where we hid from grandpa"*), or a rescuer who's only sometimes on the line.

### Who is the rescuer and why do they know the exit?
- A sibling who grew up here? The former owner? Grandpa from the hospital? (also affects the shared memories)

### Language
- Czech, English, or both? Czech TTS quality varies.

### Scope
- How many rooms (8–12?), how many sound features, how many endings or chapters?

---

## Discarded / parked ideas (for context)

- **Decrypto over the phone:** you and an allied LLM vs. an eavesdropping LLM, a pure word game. Turn-based, static, a copy of an existing game.
- **"You're the eavesdropper":** two LLMs make up codes against you, you decode, and you can impersonate one of them. Funny, but there's a risk the LLMs are too smart (switching language, etc.) and the game stops being fun.
- **Real-time audio redaction:** masking words with noise as they're spoken. A strong sound mechanic; could come back as one element.
- **Switchboard operator:** routing calls between LLM characters.
- **Séance / a ghost that knocks:** a limited sound vocabulary for the LLM. Could inspire the tap channel.
- **Each room has a unique sound:** rejected in favour of non-unique combinations of features.
