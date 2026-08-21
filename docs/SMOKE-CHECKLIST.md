# Manual smoke checklist

Automated tests cover the pure model and run headless. They cannot cover *"a window opens
and the keyboard works"* — synthetic key injection across three window systems is more
machinery than this pilot warrants. So that half is checked by hand, once per platform, per
release.

Record the result in the table at the bottom.

## Steps

```sh
bin/sketch static
bin/sketch animation
bin/sketch invaders
```

Steps 4 to 17 apply to `invaders`; the rest apply to all three.

| # | Check | Expected |
|---|-------|----------|
| 1 | The window opens | A single window appears, titled as configured |
| 2 | Window size | Matches the configured width × height, and geometry looks the same on HiDPI and standard displays |
| 3 | It animates | Motion is smooth and runs at roughly 60 Hz |
| 4 | Left / right arrows | The player moves in the expected direction and stops at both edges without wrapping |
| 5 | Space | Fires; repeated presses behave sensibly |
| 6 | Held keys | Holding an arrow moves continuously — not once per key-repeat |
| 7 | Two keys at once | Holding left and space together both move and fire |
| 8 | Play to a loss | The game reaches its lost state rather than continuing |
| 9 | Restart | Enter from the lost state begins a fresh game |
| 10 | Attract mode | Leaving the title alone plays a visible demo behind it, in silence, and the invaders stay legible through the panel |
| 10a | The shield | Shooting the saucer raises an unbroken dome over the cannon with a highlight running along it; it flashes for its last couple of seconds, then goes. It should never appear in pieces |
| 10b | Between waves | Clearing a formation shows LEVEL n and a 3, 2, 1 counting down, each number held for a full second, both centred and *above* the demo's title box rather than behind it |
| 10c | Stats for nerds | F3 shows a telemetry panel in the top left and F3 again hides it; FPS reads about 60, SIM and DRAW are well under 16.67, and the game plays exactly the same with it up |
| 11 | The demo is competent | Over a minute or two it dodges bombs, shoots the saucer, and reaches roughly level four before losing |
| 12 | `1` starts one player | One game, one score in the HUD |
| 13 | `2` starts two players | Two scores in the HUD; losing a cannon costs a life and play continues, and only running out of lives hands over to player two |
| 12a | Game over | A finished game holds GAME OVER for about two seconds on the dimmed panel, naming the player in a two-player game, and the controls do nothing during it |
| 13a | The hand-over | Player one's GAME OVER is followed by PLAYER 2 / GET READY and a 3, 2, 1 on the same dimmed panel the title uses; the controls do nothing until it finishes |
| 14a | The initials prompt | The field behind it is the game that just ended, with that player's score in the HUD — not the attract demo's |
| 14 | Initials | A qualifying score asks for three letters; typing fills them, backspace deletes, enter accepts. In a two-player game each prompt names whose score it is |
| 15 | The table | The new entry appears in the right place in the high-score list |
| 16 | Scores persist | Quit, run again: the table is still there, and the HUD's HI reflects it |
| 17 | A damaged table is survivable | Corrupt `scores.txt` by hand, then run: the game starts and keeps whatever lines still parse |
| 18 | ESC closes | The window closes and the process exits with status 0 |
| 19 | Close button closes | Same as ESC — clean exit, no hang, no stack trace |
| 20 | No stray output | No exceptions or warnings on stdout/stderr |

Check the exit status explicitly:

```sh
./flixw run; echo "exit=$?"
```

The high-score file, for steps 16 and 17:

```sh
cat  "${XDG_CONFIG_HOME:-$HOME/.config}/flix-invaders/scores.txt"   # look
rm   "${XDG_CONFIG_HOME:-$HOME/.config}/flix-invaders/scores.txt"   # start over
```

## Why some of these are called out

- **Step 2** — the sketch draws into a back buffer of exactly the configured size, which is
  then blitted to the window, so one sketch pixel is one image pixel on every display. A
  toolkit left to scale for HiDPI would make geometry display-dependent.
- **Step 6** — key auto-repeat delivers repeated presses, and on some window systems a
  release before each one. The runtime keeps its own held-key set and reads it once per
  frame, so a repeat that arrives and is undone between two frames is invisible; what a step
  sees is the set, and the edges are the difference between two readings of it.
- **Step 16** — the table is read before the window opens and written after it closes, by
  `Main.flix` alone. Nothing else in the project can reach a filesystem, so if this fails the
  fault is in one small function rather than anywhere in the game.
- **Step 17** — `Scores.parse` drops lines it cannot read instead of failing, and `load`
  distinguishes "no file yet" from "could not read the file". Deleting the file must be silent;
  a file that cannot be read must print a message and still start.
- **Steps 18 and 19** — closing must stop the loop, not the JVM: the score table is written
  after `Sketch.start` returns. Escape is handled by `Surface`, which is why `Key.Escape`
  never reaches a step and nothing above the runtime may use it; the close button arrives as
  `windowClosing` against `DO_NOTHING_ON_CLOSE`. Both set the same flag, so both are
  idempotent and either may fire more than once. `main` then exits the JVM explicitly,
  because AWT's event thread is not a daemon and would otherwise keep the process alive.

## Results

| Date | Platform | OS version | JDK | Result | Notes |
|------|----------|------------|-----|--------|-------|
| 2026-08-06 | macOS (Apple Silicon) | darwin 25.5.0 | 21.0.12 | steps 1–3, 6, 7, 18–20 pass | Arrows and space verified by hand on the spike; cabinet steps 10–17 predate this run |
| | Windows | | | not yet run | |
| | Linux | | | not yet run | |

The `smoke` CI workflow covers launch, draw, and clean exit automatically on all three
platforms (Linux under Xvfb). The keyboard rows still need a human.

Until all three rows pass, the project must not be described as portable.
