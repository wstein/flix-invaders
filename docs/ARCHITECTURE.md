# Architecture

Why each boundary sits where it does, and what it buys.

The short version: **the rules are a pure function, drawing is an effect with several
interpretations, and exactly two files may touch Java.** Everything else follows from those
three commitments.

---

## Module graph

Arrows point from a module to what it depends on. Nothing in `Invaders/` or `Sketches/` can
reach `Sketch.flix` or `Audio.flix` — that direction does not exist.

```mermaid
flowchart TD
    Main[Main.flix]

    subgraph invaders["Invaders/ - pure"]
        Game[Game.flix<br>the rules]
        View[View.flix<br>what to draw]
        Types[Types.flix<br>World and Rules]
        Bunkers[Bunkers.flix]
        Collide[Collide.flix]
        Sprites[Sprites.flix<br>pixel art]
    end

    subgraph runtime["Runtime/ - the boundary"]
        Canvas[Canvas.flix<br>effect + handlers]
        Input[Input.flix<br>effect + Snapshot]
        Sound[Sound.flix<br>SoundCmd data]
        Draw["Draw.flix<br>Color, DrawCmd"]
        Palette[Palette.flix]
        Rng[Rng.flix<br>pure generator]
    end

    subgraph edge["Runtime/ - touches Java"]
        Sketch[Sketch.flix<br>window]
        Audio[Audio.flix<br>sound card]
    end

    Main --> Game
    Main --> View
    Main --> Sketch

    Game --> Types
    Game --> Bunkers
    Game --> Collide
    Game --> Rng
    Game --> Sound
    Game --> Input

    View --> Sprites
    View --> Canvas
    View --> Palette
    View --> Types

    Bunkers --> Collide
    Sprites --> Canvas
    Canvas --> Draw
    Palette --> Draw

    Sketch --> Canvas
    Sketch --> Input
    Sketch --> Audio
    Audio --> Sound
```

`Types.flix` holds both the `World` and the `Rules` module — every tunable constant in one
place, so the game can be retuned without hunting through logic.

---

## The three layers

### 1. Pure (`Invaders/`, `Sketches/`)

No `IO`, no window, no device — enforced by types, not convention. `Game.step` is:

```flix
pub def step(world: World, input: Snapshot): World
```

No effect row at all. It cannot read a clock, open a file, or draw. Everything it needs —
including the random number generator — is a field on `World`.

### 2. The boundary (`Runtime/Canvas`, `Input`, `Sound`)

Two effects and one data type:

| | Kind | Why |
|---|---|---|
| `Canvas` | effect | Drawing reads naturally as a sequence of commands, and several interpretations are genuinely useful |
| `Input` | effect | A `poll` that returns the same frozen snapshot all step |
| `SoundCmd` | **data** | Sounds are produced by `step`, which is pure — so they must be values, not operations |

The asymmetry is deliberate and is explained under *Sound* below.

### 3. Touching Java (`Runtime/Sketch`, `Runtime/Audio`)

`Sketch.flix` owns the window, the frame loop, key tracking and the Processing lifecycle.
`Audio.flix` owns waveform synthesis and a pool of `javax.sound.sampled` clips. Nothing else
in `src/` imports a Java class.

---

## Threading

```mermaid
flowchart LR
    subgraph main["main thread"]
        M[main] --> ST[Sketch.start]
        ST --> AO[Audio.open]
        ST --> RS[PApplet.runSketch]
        RS --> PK["park until closed"]
    end
    subgraph anim["Processing Animation Thread"]
        D[draw] --> ADV["advance: N steps"]
        ADV --> PL[Audio.playAll]
        PL --> RN[render under Canvas handler]
        KP["keyPressed and keyReleased"]
    end
    RS -.->|starts| D
```

Three facts make this safe:

- **`runSketch` returns immediately.** The enclosing region would exit while `draw` is still
  using its `Ref`s, so `main` parks until the sketch reports it has closed.
- **Key events are drained after `draw` returns, on the same thread.** Processing queues
  them, so the held-key set is only mutated between frames and needs no locking. This holds
  *only* while `noLoop()` is never called — under `noLoop` events dispatch on the EDT
  instead. The runtime never calls it.
- **Effect handlers are stack-scoped.** A handler installed around `runSketch` on the main
  thread is invisible inside `draw`. Both the `Canvas` handler and the audio flush are
  therefore installed *inside* the callback, every frame.

---

## Determinism

The property everything else is arranged to protect: **a world plus a list of input
snapshots completely determines every world that follows.**

```mermaid
flowchart LR
    S["seed"] --> W0["World 0"]
    I["List of Snapshot"] --> F["foldLeft Game.step"]
    W0 --> F
    F --> WN["World N"]
    WN --> D["Game.digest"]
    D --> C{"identical?"}
```

Three things had to be true for this to hold:

1. **A fixed timestep.** Each step covers exactly 1/60 s, so a slow frame runs more steps
   rather than longer ones. `System.nanoTime` — not `Time.Clock`, whose handler is
   wall-clock `currentTimeMillis` and can jump backwards on an NTP correction.
2. **Input frozen once per frame.** Every step within a frame sees the same `Snapshot`.
3. **Randomness as a value.** `Rng` is a field on `World`, threaded through `step` and
   returned with the new world.

[TestReplay.flix](../test/TestReplay.flix) checks all of it, including that splitting 600
steps into two batches of 300 changes nothing — which would fail if any hidden state existed.

`Game.digest` is a string rendering of a whole world, used for those comparisons. It exists
because Flix records have no `Eq` instance; see *Rejected alternatives*.

---

## Sound, and why it is data

`Game.step` has no effect row, and `Sketch.start` types `step` the same way. So the rules
cannot *perform* a sound. Instead each stage appends to `World.sounds`, cleared at the top of
every step, and the runtime plays whatever the tick produced.

```mermaid
flowchart LR
    ST["step stage<br>e.g. fire"] --> SC["World.sounds<br>List of SoundCmd"]
    SC --> RT["Sketch collects<br>per step, not per frame"]
    RT --> AU["Audio.playAll"]
    AU --> CL["Clip pool<br>first idle voice wins"]
```

Consequences:

- Tests assert on sound with **no audio device** — they read `World.sounds`.
- A machine with no sound card runs the identical simulation.
- Sounds are collected **per step**, not per frame: a frame may advance the simulation five
  times, and a shot fired in the first must still be heard.
- The march bassline is spaced by *distance marched*, not by a timer, so its tempo tracks the
  formation's speed-up with no extra state.

`AudioSystem` throws an unchecked `IllegalArgumentException` when no mixer exists — not the
declared `LineUnavailableException` — so every entry point in `Audio.flix` catches `Exception`
and degrades to silence.

---

## Rendering

Sprites are text. `Sprite.of` parses rows of `#` and `.` **once**, collapsing each row into
horizontal runs, and stores them:

```mermaid
flowchart LR
    T["'..####..'<br>'.######.'"] --> P["Sprite.of<br>parse once"]
    P --> R["runs:<br>(row, startCol, length)"]
    R --> D["Sprite.draw"]
    D --> C["one Canvas.rect per run"]
```

Run-merging is not cosmetic. An intact bunker is 96 blocks but about a dozen runs, and
parsing per invader per frame instead of once cost roughly half the frame rate when measured.

**Measured cost** (bracketing the work inside `draw` with `nanoTime`, not wall-clock — see
below): simulation 0.13 ms, drawing 1.74 ms, about **1.9 ms of a 16.7 ms budget**.

> Do not measure frame cost with a stopwatch. Processing sleeps to hold the target frame
> rate, so timing a run of N frames measures the rate limiter and not the work — any sketch
> inside budget reports ~16.7 ms whether it uses 1 ms or 15 ms.

---

## Rejected alternatives

Recorded because each looks obviously right and is not.

| Alternative | Why not |
|---|---|
| `World` as a single-case enum wrapping a record | Looks free and has stdlib precedent (`Net/HttpRequest.flix`). But `pub enum W({...}) with Eq` **does not compile** — records have no `Eq` for the derivation to build on, so it would mean hand-writing a 24-field instance, against 751 field-select sites. Tested and rejected. |
| The stdlib `Random` effect instead of `Rng` data | An anonymous `PApplet` subclass compiles to a fixed JVM method, so `draw` cannot carry a polymorphic effect. `handleWithSeed` also builds a fresh generator per invocation, which would restart the sequence every frame. |
| `@DefaultHandler` on `Canvas` / `Input` | The only sensible default is a silent no-op, which would let a test that forgot to choose an interpretation compile and assert on a frame nobody drew. Leaving them undefaulted keeps that a type error. |
| Datalog in the frame loop | All 25 stdlib examples are whole-relation fixpoints over static facts, and the engine re-stratifies per solve with no incremental API. Reasonable at level-load time; malpractice at 60 Hz. |
| The Processing Sound library | Not on Maven Central; the JitPack artifact contains zero classes. Would require republishing LGPL and Apache jars from this repo. `javax.sound.sampled` gives the same arcade bleeps with no dependency. |
| `flix build-fatjar` for release | It shades `processing-core.jar`, converting dynamic linking into static and triggering LGPL-2.1 §6's relinking obligation. See [THIRD-PARTY.md](../THIRD-PARTY.md). |

---

## Toolchain

`bin/flix` downloads the compiler version pinned in `flix.toml` into `.flix/` once and reuses
it, so local runs and CI are identical. Processing Core is a single pinned jar fetched from
Maven Central — `[jar-dependencies]`, not `[mvn-dependencies]`, because core's POM drags in
JOGL umbrella artifacts and a Kotlin stdlib that the JAVA2D renderer never loads. Verified at
runtime with `-verbose:class`: no `com.jogamp` class is ever loaded.

CI runs `check`, `test`, a formatting gate, and a grep asserting no test opens a window or an
audio device. A separate smoke workflow launches every sketch on Linux (under Xvfb), macOS
and Windows and checks it starts, draws and exits cleanly.

## See also

- [spike-result.md](spike-result.md) — the integration spike, and the classloader problem
  that nearly blocked it
- [SMOKE-CHECKLIST.md](SMOKE-CHECKLIST.md) — the manual per-platform test
- [../AGENTS.md](../AGENTS.md) — the gotchas, each of which cost real debugging time
