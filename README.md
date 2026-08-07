# flix-proc-invaders

A **Flix creative-coding pilot using Processing Core**: an arcade game where the rules are a
pure function, the tests never open a window, and the effect system marks exactly where the
outside world begins.

It is not a Flix dialect, not a Processing Mode, and not affiliated with either project. It
exists to answer one question: *does Flix's effect system make creative coding clearer?*

There is **no Java in this repository**. Flix subclasses Processing's `PApplet` directly.

## Quickstart

You need **Java 21+** and nothing else — the Flix compiler downloads itself on first use.

```sh
git clone https://github.com/wstein/flix-proc-invaders
cd flix-proc-invaders

bin/flix check     # type-check; the fast feedback loop
bin/flix test      # 348 tests -- no window, no audio device, no filesystem
bin/flix run       # play
bin/bench          # measure the demo bot over ten seeds
```

**Controls:** `1` or `2` at the title screen picks one or two players; arrows move, space
fires, enter moves on. Two players alternate on each destroyed cannon, as the original did.
Shelter behind the bunkers — they stop bombs but wear away. Shoot the saucer for points *and*
a temporary shield. Every 2500 points buys a life. Clearing the formation starts a harder
level; there is no winning, only surviving longer.

Leave it alone at the title and it plays itself, and it is meant to look like a person doing
it: [the bot](src/Invaders/Demo.flix) misjudges a shot and lives with the misjudgement for a
beat, needs a real reason to turn the cannon round, and now and then stops watching. All of
that is still pure -- it threads a `Hand` the way the game threads its `Rng` -- and it is the
same code the balance test drives, good enough to reach about level four.

A qualifying score asks for three initials and is kept in
`~/.config/flix-invaders/scores.txt` (or `$XDG_CONFIG_HOME`). Delete it to start over; it is
a text file, and a damaged one costs you the table, not the game.

---

## For students: read it in this order

This codebase is meant to be read, not just run. Each step adds exactly one idea.

```mermaid
flowchart LR
    A["1 · Still<br>a fixed picture"] --> B["2 · Animation<br>state and time"]
    B --> C["3 · Collide, Sprites<br>small pure functions"]
    C --> D["4 · Game.step<br>the whole game, pure"]
    D --> E["5 · Sketch.flix<br>where Java begins"]
```

| # | Read | Run | The one new idea |
| --- | ------ | ----- | ------------------ |
| 1 | [Sketches/Still.flix](src/Sketches/Still.flix) | `bin/sketch static` | Drawing is a sequence of operations. A window is only one way to interpret them. |
| 2 | [Sketches/Animation.flix](src/Sketches/Animation.flix) | `bin/sketch animation` | A world, and a pure `step` that advances it. No clock, no frame counter. |
| 3 | [Invaders/Collide.flix](src/Invaders/Collide.flix), [Sprites.flix](src/Invaders/Sprites.flix) | `bin/flix test` | Ordinary functions, tested directly. Pixel art is data written as text. |
| 4 | [Invaders/Game.flix](src/Invaders/Game.flix) | `bin/flix run` | The entire game is `(World, Snapshot) -> World`. That is the whole point. |
| 5 | [Runtime/Sketch.flix](src/Runtime/Sketch.flix) | — | Where purity stops and Java starts. One file. |

**Your first change**, in under a minute: open [Still.flix](src/Sketches/Still.flix), change a
colour or move the sun in its `Canvas.ellipse` call, then `bin/sketch static` again.

**Your first real change:** in [Animation.flix](src/Sketches/Animation.flix) set `gravity()`
to `0.15f32` and watch the balls fall. You changed a pure function; nothing else moved.

---

## Architecture

Everything in the top box is pure — no `IO`, no window, no device. It can all be tested
headlessly, and it is.

```mermaid
flowchart TB
    subgraph pure["PURE - no IO, no window, no device"]
        direction LR
        cab["Invaders/<br>Session · Screens · Demo<br>the cabinet around the game"]
        model["Invaders/<br>Game · View · Bunkers<br>Collide · Types · Sprites"]
        demos["Sketches/<br>Still · Animation"]
    end

    subgraph seam["THE BOUNDARY - three effects"]
        direction LR
        canvas["Canvas<br>effect"]
        input["Input<br>effect"]
        sound["Sound<br>effect"]
    end

    subgraph java["TOUCHES THE OUTSIDE WORLD"]
        direction LR
        sketch["Runtime/Sketch.flix<br>window · frame loop · keys"]
        audio["Runtime/Audio.flix<br>synthesis · clip pool"]
        main["Main.flix<br>the high-score file"]
    end

    ext["Processing Core JAVA2D<br>javax.sound.sampled<br>~/.config"]

    cab --> model
    cab --> canvas
    model --> canvas
    model --> sound
    demos --> canvas
    input --> model
    canvas --> sketch
    sound --> audio
    sketch --> ext
    audio --> ext
    main --> ext
```

Exactly **two** files in `src/` mention Java: one for the window, one for the sound card. A
third, [`Main.flix`](src/Main.flix), can reach a filesystem — for one text file, on the way in
and the way out. Everything else cannot open a device or a file even by accident, because the
types forbid it.

## The frame loop

Processing calls `draw()` on its own thread. The runtime turns that into a whole number of
simulation steps, so behaviour never depends on frame rate.

```mermaid
sequenceDiagram
    autonumber
    participant P as Processing<br/>Animation Thread
    participant S as Sketch.start
    participant G as Game.step<br/>(pure)
    participant A as Audio
    participant V as View.render<br/>(pure)

    P->>S: draw()
    S->>S: nanoTime into accumulator<br/>(clamped to 5 steps)
    S->>S: freeze one Input.Snapshot
    loop while accumulator >= 1/60 s
        S->>G: step(world, snapshot)
        G-->>S: next world plus sounds
    end
    S->>A: playAll(sounds)
    Note over A: Clip.start() returns at once,<br/>so the frame never stalls
    S->>V: render(world)
    V-->>P: fill · rect · text
```

Two properties fall out of this shape:

- **Frame-rate independence.** A slow frame runs *more* steps, not bigger ones. Every step
  covers exactly 1/60 s.
- **Input is frozen once per frame.** Every step in a frame sees the same snapshot, which is
  what lets a recorded run replay exactly.

## The rules, as a pipeline

`Game.step` is one pure function built from small named stages, each readable and tested on
its own.

```mermaid
flowchart TB
    subgraph intent["intent"]
        a1[movePlayer] --> a2[fire]
    end
    subgraph motion["motion"]
        b1[moveBullets] --> b2[moveBombs] --> b3[marchInvaders] --> b4[moveMystery] --> b5[invaderFire]
    end
    subgraph contact["contact"]
        c1[ageShield] --> c2[resolveBunkers] --> c3[resolveBullets] --> c4[resolveMystery] --> c5[resolveBombs]
    end
    subgraph books["bookkeeping"]
        d1[awardBonusLife] --> d2[ageBlasts] --> d3[trackHiScore] --> d4[checkEnd]
    end
    intent --> motion --> contact --> books
```

Order carries meaning. Bunkers resolve *before* invaders, so a bunker genuinely stops a shot.
The saucer resolves *after* the formation, so a bullet must pass everything below it first.
The shield ages *before* anything can grant one, so a new shield lasts its full duration.

## Phases

There is no winning. Clearing the formation starts a harder level; the only ending is losing.

```mermaid
stateDiagram-v2
    [*] --> Playing
    Playing --> Cleared: last invader destroyed
    Cleared --> Playing: after a beat - next level,<br/>faster, more bombs, fresh bunkers
    Playing --> Lost: lives exhausted or<br/>invaders reach the line
    Lost --> Playing: Enter (hi-score survives)
```

## One effect, three interpretations

This is the idea the whole project exists to demonstrate. `View.render` says *what* to draw
and never learns *where*. `Sound` works the same way: `runWithClips`, `runWithCollector`,
`runWithNoOp`.

```mermaid
flowchart LR
    R["View.render(w)<br/>uses only the Canvas effect"]
    R --> H1["runWithSurface"]
    R --> H2["runWithCollector"]
    R --> H3["runWithNoOp"]
    H1 --> O1["a Processing window"]
    H2 --> O2["List of DrawCmd<br/>headless tests"]
    H3 --> O3["nothing<br/>benchmarks"]
```

Adding a fourth — a draw-call counter, an SVG exporter — means adding a function to
[Canvas.flix](src/Runtime/Canvas.flix), not touching the runtime.

---

## Design notes

- **Sound is an effect, like drawing.** `Game.step` says *what* should be heard;
  the runtime plays it onto a clip pool, the tests collect it into a list, and a machine with
  no sound card discards it — all three running the identical simulation.
- **Randomness is data, not an effect.** An `Rng` threads through `step` like any other part
  of the world, so determinism is structural rather than depending on which handler someone
  installed. See [ARCHITECTURE.md](docs/ARCHITECTURE.md#sound-data-or-effect) for why sound
  went the other way.
- **Pixel art, no image files.** Sprites are rows of `#` and `.` in
  [Sprites.flix](src/Invaders/Sprites.flix), collapsed into horizontal runs so that 55
  invaders and four bunkers cost about 1.1 ms a frame.
- **Colours are checked, not eyeballed.** [TestContrast.flix](test/TestContrast.flix) asserts
  WCAG 2.1 ratios for the whole palette — 4.5:1 for text, 3:1 for shapes.
- **Balance is a test.** [TestDifficulty.flix](test/TestDifficulty.flix) drives the real game
  with [the same bot that plays the attract screen](src/Invaders/Demo.flix), asserting it
  clears level one on every seed, reaches about level four, and still eventually loses. It
  caught a regression a human had reported.
- **No `@DefaultHandler` on `Canvas` or `Input`, deliberately.** A silent default would let a
  test that forgot to choose an interpretation compile and assert on a frame nobody drew.

## Testing

348 tests, none of which open a window, an audio device, or the real filesystem — CI enforces
all three with greps.

| Area | Tests | What it pins down |
| --- | --- | --- |
| [TestGame](test/TestGame.flix) | 106 | every rule, hit boxes, levels, shield, bonus lives |
| [TestSession](test/TestSession.flix) | 37 | screens, alternating turns, typed initials |
| [TestAnimation](test/TestAnimation.flix) | 27 | elastic collisions; conservation of momentum and energy |
| [TestBunkers](test/TestBunkers.flix) | 25 | damage, absorption, erosion, camping behind a drilled slit |
| [TestSprites](test/TestSprites.flix) | 19 | run-length decomposition of the pixel art |
| [TestDemo](test/TestDemo.flix) | 29 | the computer player: aim, dodge, when to fire, and not shaking |
| [TestScores](test/TestScores.flix) | 16 | the table's format and ordering, with no handlers at all |
| [TestCanvas](test/TestCanvas.flix) | 14 | the effect and its interpretations |
| [TestContrast](test/TestContrast.flix) | 10 | WCAG contrast of every palette colour |
| [TestRng](test/TestRng.flix) | 10 | determinism, range, distribution |
| [TestReplay](test/TestReplay.flix) | 11 | identical input replays to an identical world *and* an identical soundtrack |
| [TestCollide](test/TestCollide.flix) + [TestInput](test/TestInput.flix) | 18 | overlap convention, input edges |
| [TestScoresFile](test/TestScoresFile.flix) | 8 | saving and loading, on a filesystem that does not exist |
| [TestScreenGraph](test/TestScreenGraph.flix) | 4 | no screen traps the player — reachability, in Datalog |
| [TestBench](test/TestBench.flix) | 12 | the benchmark's own arithmetic — rates, worst cases, cut-short runs |
| [TestDifficulty](test/TestDifficulty.flix) | 5 | the game is winnable, not trivial, and the demo reaches about level four |

## Non-goals

Deliberately out of scope: image and audio assets, networking, a game engine, a browser
playground, and a Processing Mode. Sprites are text in the source and sounds are arithmetic —
the only binary asset is the arcade font.

Persistence *was* on this list. It came off for the high-score table, and stayed as small as
it could: one text file, written by [`main`](src/Main.flix) alone, on the way out. Nothing
else in the project can reach a filesystem, and [`Scores`](src/Runtime/Scores.flix) decides
what the table contains with pure functions that need no handler to test.

## Remix it

The game is one possible outcome, not the point. Roughly in order of effort: change the
[palette](src/Runtime/Palette.flix) (the contrast tests keep you honest); retune the
[rules](src/Invaders/Types.flix) — march speed, fire rate, formation shape; give the invaders
a different movement grammar in `marchInvaders`; change the win condition in `checkEnd`. Each
is a pure function with tests around it.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — module graph, threading, determinism, and
  why each boundary sits where it does
- [docs/spike-result.md](docs/spike-result.md) — what the integration spike proved, and the
  non-obvious thing that nearly blocked it
- [docs/SMOKE-CHECKLIST.md](docs/SMOKE-CHECKLIST.md) — the manual per-platform test
- [AGENTS.md](AGENTS.md) — working notes and the gotchas that cost real time

## License

[MIT](LICENSE.md). Links at runtime against Processing Core (LGPL-2.1) and bundles the
Press Start 2P font (SIL OFL 1.1) — see [THIRD-PARTY.md](THIRD-PARTY.md).
