# flix-proc-invaders

A **Flix creative-coding pilot using Processing Core**: a desktop window driven entirely
from [Flix](https://flix.dev), where the game logic is pure and testable without a display,
and effects mark the boundary where the outside world begins.

This is not a Flix dialect, not a Processing Mode, and not affiliated with or endorsed by
either project. It is a small pilot that tries to answer one question: *does Flix's effect
system make creative coding clearer?*

## Status

The runtime is complete: Flix drives a Processing window directly, with **no Java in this
repository**. Drawing goes through a `Canvas` effect, input through an `Input` effect, and
the simulation runs on a fixed timestep. See
[docs/spike-result.md](docs/spike-result.md). The game itself is being built on top.

## Quickstart

You need **Java 21+** and nothing else — the Flix compiler downloads itself on first use.

```sh
git clone https://github.com/wstein/flix-proc-invaders
cd flix-proc-invaders

bin/flix check     # type-check (fast feedback loop)
bin/flix test      # run the test suite -- no window is ever opened
bin/sketch static  # open a window
```

`bin/flix` fetches the compiler version pinned in `flix.toml` into `.flix/` once, then
reuses it, so local runs and CI behave identically.

## Make your first change

Open [src/Sketches/Still.flix](src/Sketches/Still.flix) and change a colour, or move the sun
by editing the two numbers in its `Canvas.ellipse` call. Then `bin/sketch static` again.
That round trip should take under a minute.

## Where the line is

```text
Pure game model + deterministic tests     Invaders/  -- no IO, no window
        |
Canvas / Input effects                    Runtime/Canvas.flix, Runtime/Input.flix
        |
One runtime adapter                       Runtime/Sketch.flix  <-- the only file that touches Java
        |
Processing Core, one desktop 2D window    JAVA2D renderer
```

Exactly one file in `src/` mentions Java. Everything under `Invaders/` is pure: `step` takes
a world and an input snapshot and returns a new world, and `view` describes what to draw
without knowing that a window exists. That is what lets the whole test suite run headless,
and what makes identical input replay to an identical world.

## Design notes

- **Fixed timestep.** The simulation advances in constant 1/60 s steps from a
  `System.nanoTime()` accumulator, so behaviour does not depend on frame rate or machine
  speed. This is what makes replay exact.
- **Seeded randomness.** The run is seeded, and Flix's seeded random handler is *pure* — so
  tests replay a recorded input script and assert the resulting world is identical.
- **JAVA2D only.** No JOGL, no native libraries; the Processing dependency is a single
  ~1 MB jar.

## Non-goals

Deliberately out of scope: audio, sprites, image assets, networking, multiple levels,
persistence, a game engine, a browser playground, and a Processing Mode.

## Documentation

- [docs/spike-result.md](docs/spike-result.md) — what the integration spike proved, and the
  one non-obvious thing that nearly blocked it
- [docs/SMOKE-CHECKLIST.md](docs/SMOKE-CHECKLIST.md) — the manual per-platform test
- [AGENTS.md](AGENTS.md) — working notes for this codebase

## License

[MIT](LICENSE.md). This project links, unmodified and at runtime, against Processing Core,
which is LGPL-2.1 — see [THIRD-PARTY.md](THIRD-PARTY.md).
