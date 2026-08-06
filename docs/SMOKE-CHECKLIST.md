# Manual smoke checklist

Automated tests cover the pure model and run headless. They cannot cover *"a window opens
and the keyboard works"* — synthetic key injection across three window systems is more
machinery than this pilot warrants. So that half is checked by hand, once per platform, per
release.

Record the result in the table at the bottom.

## Steps

```sh
bin/flix run
```

| # | Check | Expected |
|---|-------|----------|
| 1 | The window opens | A single window appears, titled as configured |
| 2 | Window size | Matches the configured width × height, and geometry looks the same on HiDPI and standard displays (`pixelDensity(1)` is pinned) |
| 3 | It animates | Motion is smooth and runs at roughly 60 Hz |
| 4 | Left / right arrows | The player moves in the expected direction and stops at both edges without wrapping |
| 5 | Space | Fires; repeated presses behave sensibly |
| 6 | Held keys | Holding an arrow moves continuously — not once per key-repeat |
| 7 | Two keys at once | Holding left and space together both move and fire |
| 8 | Play to a loss | The game reaches its lost state rather than continuing |
| 9 | Restart | Enter from the lost state begins a fresh game |
| 10 | ESC closes | The window closes and the process exits with status 0 |
| 11 | Close button closes | Same as ESC — clean exit, no hang, no stack trace |
| 12 | No stray output | No exceptions or warnings on stdout/stderr |

Check the exit status explicitly:

```sh
bin/flix run; echo "exit=$?"
```

## Why some of these are called out

- **Step 2** — Processing defaults to `pixelDensity(2)` on HiDPI displays, which would make
  geometry display-dependent. The runtime pins `pixelDensity(1)` in `settings()`.
- **Step 6** — Processing filters key auto-repeat by default, so the runtime tracks its own
  held-key set. `PApplet.pressedKeys` is package-private and unavailable to us.
- **Steps 10 and 11** — `PApplet.exitActual` is the only `System.exit(0)` in Processing, and
  `flix run` does not fork a JVM. The runtime overrides it so control returns to `main`
  instead of the process being killed mid-frame. It can fire more than once, so the exit
  path must be idempotent.

## Results

| Date | Platform | OS version | JDK | Result | Notes |
|------|----------|------------|-----|--------|-------|
| 2026-08-06 | macOS (Apple Silicon) | darwin 25.5.0 | 21.0.12 | spike passes steps 1–3, 6, 7, 10–12 | Arrows and space verified by hand; steps 4, 5, 8, 9 need the game |
| | Windows | | | not yet run | |
| | Linux | | | not yet run | |

Until all three rows pass, the project must not be described as portable.
