# Contributing

Issues, documentation fixes, teaching-sketch ideas, and small game improvements
are welcome. Please open an issue before starting a substantial redesign so the
work fits the project's purpose: a small, readable Flix and Processing example.

## Development setup

You need Java 21 or newer. The repository's wrapper downloads the pinned Flix
compiler on first use; do not substitute a `flix` executable from your `PATH`.

```sh
git clone https://github.com/wstein/flix-invaders
cd flix-invaders
./flixw check
./flixw test
```

Before opening a pull request, run:

```sh
./flixw format
./flixw check
./flixw test
```

Changes to `src/Invaders/Demo.flix` or a tuning constant in `Rules` also need
`bin/bench` before and after the change. Do not compare its raw totals: use the
rates per 10,000 ticks it reports.

## Design boundaries

- Keep `src/Invaders/` pure: no `IO`, window, or filesystem access.
- Keep Java interop in `src/Runtime/Sketch.flix` and `src/Runtime/Audio.flix`.
- Keep tests headless and off the real filesystem. Tests using `Fs.` must use
  `Fs.FileSystem.withInMemoryFS`.
- Read [AGENTS.md](AGENTS.md) and [the architecture guide](docs/ARCHITECTURE.md)
  before moving a boundary; both record constraints that are easy to rediscover
  the hard way.

## Pull requests

Use a focused branch and explain both the user-visible change and the design
reason. Include tests for changed pure behaviour, update docs when the teaching
path changes, and keep generated directories (`build/`, `artifact/`, `lib/`,
and `.flix-cache/`) out of commits. The wrapper files `flixw`, `flixw.cmd` and
`.flixw/` are the exception: they are generated and committed, so that a
clone needs nothing but Java 21.
