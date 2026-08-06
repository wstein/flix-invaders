# flix-proc-invaders

A **Flix creative-coding pilot using Processing Core**: a desktop window driven entirely
from [Flix](https://flix.dev), where the game logic is pure and testable without a display,
and effects mark the boundary where the outside world begins.

This is not a Flix dialect, not a Processing Mode, and not affiliated with or endorsed by
either project. It is a small pilot answering one question: *does Flix's effect system make
creative coding clearer?*

There is **no Java in this repository**. Flix subclasses Processing's `PApplet` directly.

## Quickstart

You need **Java 21+** and nothing else — the Flix compiler downloads itself on first use.

```sh
git clone https://github.com/wstein/flix-proc-invaders
cd flix-proc-invaders

bin/flix check     # type-check; the fast feedback loop
bin/flix test      # 150 tests -- no window is ever opened
bin/flix run       # play Space Invaders
```

`bin/flix` fetches the compiler version pinned in `flix.toml` into `.flix/` once and reuses
it, so local runs and CI behave identically.

**Controls:** left and right arrows move, space fires, enter restarts after the game ends,
escape quits. Shelter behind the bunkers — they stop bombs, but they wear away.

## Start with the sketches, not the game

```sh
bin/sketch static      # a fixed composition: no state, no time, no input
bin/sketch animation   # four balls bouncing: state and a fixed timestep
bin/sketch invaders    # the game
```

Read them in that order. [Still.flix](src/Sketches/Still.flix) is the smallest thing this
runtime can draw. [Animation.flix](src/Sketches/Animation.flix) adds a world and a pure
`step`, which is the idea the whole game is built on.

**Make your first change:** open [Still.flix](src/Sketches/Still.flix) and change a colour,
or move the sun by editing the two numbers in its `Canvas.ellipse` call. Re-run
`bin/sketch static`. That round trip should take under a minute.

## Where the line is

```text
Pure game model + deterministic tests     src/Invaders/   -- no IO, no window
        |
Canvas / Input effects                    src/Runtime/Canvas.flix, Input.flix
        |
One runtime adapter                       src/Runtime/Sketch.flix  <-- the only file
        |                                                              that touches Java
Processing Core, one desktop 2D window    JAVA2D renderer
```

Exactly one file in `src/` mentions Java. Everything under `src/Invaders/` is pure:
`Game.step` takes a world and an input snapshot and returns a new world, and `View.render`
describes what to draw without knowing a window exists. That is what lets the whole test
suite run headless, and what makes identical input replay to an identical world.

## Design notes

- **Fixed timestep.** The simulation advances in constant 1/60 s steps from a
  `System.nanoTime()` accumulator, so behaviour does not depend on frame rate or machine
  speed. This is what makes replay exact.
- **Randomness is data, not an effect.** An `Rng` is threaded through `step` like any other
  part of the world, so a game that uses randomness is still a pure function of its inputs.
- **Drawing is an effect with two interpretations.** `Canvas.runCollecting` records draw
  calls as a `List[DrawCmd]` with no window, so rendering is tested as data.
- **Arcade font.** The HUD is set in [Press Start 2P](assets/), loaded from a file at
  startup. No font is installed on macOS, Linux *and* Windows alike, so relying on a system
  font would mean different metrics on each; vendoring one makes the layout identical
  everywhere. A missing or unreadable file falls back to Processing's default rather than
  crashing.
- **Pixel art, no image files.** Sprites are written as rows of `#` and `.` in
  [Sprites.flix](src/Invaders/Sprites.flix) and drawn as rectangles. Each row is collapsed
  into horizontal runs first, which is what keeps 55 invaders and four bunkers inside a
  60 Hz frame budget.
- **The bunkers are real.** Each is a grid of blocks; a hit destroys the blocks around the
  one it struck, and the shot stops there. [TestBunkers.flix](test/TestBunkers.flix) checks
  they actually protect the player rather than merely being drawn in the way.
- **Colours are checked, not eyeballed.** [TestContrast.flix](test/TestContrast.flix)
  asserts WCAG 2.1 contrast ratios for the whole [palette](src/Runtime/Palette.flix) — 4.5:1
  for text, 3:1 for shapes. A less legible colour fails the build.
- **JAVA2D only.** No JOGL, no native libraries; the Processing dependency is a single
  ~1 MB jar, verified at runtime to load no `com.jogamp` classes.

## Non-goals

Deliberately out of scope: image assets, networking, persistence, a game engine, a browser
playground, and a Processing Mode. The sprites are pixel art written as text in the source,
not files -- the only binary asset is the arcade font.

## Remix it

The game is one possible outcome, not the point. Things to try, roughly in order of effort:
change the [palette](src/Runtime/Palette.flix) (the contrast tests will keep you honest);
retune the [rules](src/Invaders/Types.flix) — march speed, fire rate, formation shape; give
the invaders a different movement grammar in `marchInvaders`; or change the win condition in
`checkEnd`. Every one of those is a pure function with tests around it.

## Documentation

- [docs/spike-result.md](docs/spike-result.md) — what the integration spike proved, and the
  one non-obvious thing that nearly blocked it
- [docs/SMOKE-CHECKLIST.md](docs/SMOKE-CHECKLIST.md) — the manual per-platform test
- [AGENTS.md](AGENTS.md) — working notes, including the gotchas that cost real time

## License

[MIT](LICENSE.md). This project links, unmodified and at runtime, against Processing Core,
which is LGPL-2.1 — see [THIRD-PARTY.md](THIRD-PARTY.md).
