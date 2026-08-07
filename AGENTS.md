# Working on this project

A Flix project driving a Processing Core window. The Flix version it targets is pinned in
`flix.toml`.

## Commands

Always use the `bin/flix` wrapper, not a `flix` on `PATH`: it downloads and caches the
pinned compiler into `.flix/`, so local runs match CI exactly.

- `bin/flix check` — type-check without generating code; the fast feedback loop, and the linter
- `bin/flix format` — the formatter; run it before every commit
- `bin/flix test` — run every `@Test` function under `test/`
- `bin/flix run` — run `main`
- `bin/flix build` — compile to `build/class`
- `bin/flix doc` — write API documentation to `build/doc/`, matching this compiler exactly

## Layout

- `src/Runtime/` — the effect boundary. `Runtime/Sketch.flix` (window) and
  `Runtime/Audio.flix` (sound card) are the **only** files that touch Java
- `src/Sketches/` — teaching sketches
- `src/Invaders/` — the pure game model; no `IO`, no window
- `test/` — `@Test` functions; must stay headless (CI enforces this)
- `flix.toml` — package metadata, the Flix version, and dependencies
- `build/`, `artifact/`, `lib/`, `.flix/` — generated; do not edit and do not commit

## Orientation

`docs/ARCHITECTURE.md` explains why each boundary sits where it does, with diagrams of the
module graph, the frame loop, the threading model, and the determinism story. It also lists
the alternatives that were tried and rejected, which is the fastest way to avoid re-proposing
one.

## Project-specific gotchas

These cost real debugging time. See `docs/spike-result.md` for the full record.

- **Processing cannot find its own classes under Flix.** `PApplet` resolves its renderer and
  its macOS helper via `Thread.currentThread().getContextClassLoader()`, but Flix loads jar
  dependencies through an isolated `ExternalJarLoader`. Before `runSketch`, you must call
  `Thread.currentThread().setContextClassLoader(sketch.getClass().getClassLoader())`.
  Without it: *"The processing.awt.PGraphicsJava2D renderer is not in the class path."*
- **`import` must be inside the `mod` block.** A top-level `import` does not reach into
  `mod Foo { ... }`; you get `Undefined type`, which looks like a classpath problem and is not.
- **Never name a receiver `_this`.** The leading underscore makes it a *hidden* variable
  (`E6956`) that the body cannot use. This project names it `app`.
- **A *concrete* effect on the frame callback is fine; a polymorphic one is not.**
  `Sketch.start` cannot be generic over effect variables (`E6469`) because the anonymous
  `PApplet` subclass compiles `draw` to a fixed JVM method. But `step: ((s, i) -> s \ Sound)`
  with the handler installed inside `draw` compiles and runs — verified. Do not cite the
  polymorphism limit as a reason a given effect is impossible; check which case you are in.
- **Wrapping a record in a single-case enum does NOT give you `Eq`/`ToString`.**
  `pub enum W({a = Int32}) with Eq` fails: records have no `Eq` instance for the derivation
  to build on. You must hand-write `instance Eq[W]`. This is worth knowing because the
  refactor looks free and has apparent stdlib backing (`Net/HttpRequest.flix:29`), and it
  is not -- it was proposed, tested, and rejected on that basis.
- **Reserved words that bite as ordinary names:** `run`, `spawn`, `from`, and `Static`. The
  errors point at the *next* token, so they read as unrelated syntax errors.
- **`size`, `pixelDensity`, `fullScreen`, `smooth` are legal only inside `settings()`.**
  Anywhere else they throw `IllegalStateException`.
- **`exitActual` is Processing's only `System.exit(0)`**, and `flix run` does not fork a JVM.
  Override it so closing the window returns control to `main`. It can fire more than once,
  so keep the exit path idempotent.
- **Handlers must be installed inside the `draw` callback.** They are stack-scoped, and
  `draw` runs on Processing's Animation Thread — a handler installed around `runSketch` on
  the main thread is invisible there.
- **`runSketch` returns immediately.** The enclosing `region` must be kept alive by hand, or
  the sketch will touch `Ref`s whose region has exited.
- **Do not measure frame cost with a stopwatch.** Processing sleeps to hold the target
  frame rate, so timing a run of N frames measures the rate limiter, not the work: any
  sketch comfortably inside budget reports ~16.7ms per frame at 60Hz whether it uses 1ms or
  15ms. To find the real cost, bracket the work inside `draw` with `System.nanoTime()` and
  average over a hundred frames. Measured this way the whole game costs about 1.9ms per
  frame, roughly a ninth of the budget.
- **Use `System.nanoTime()` for frame timing.** The stdlib `Time.Clock` handler uses
  `System.currentTimeMillis()`, which is wall-clock and not monotonic.
- **A machine with no sound card throws `IllegalArgumentException`, not
  `LineUnavailableException`.** `AudioSystem` only throws the declared checked exception when
  a mixer exists but refuses; with no mixer at all it throws unchecked from `getLine`. Catch
  `Exception` at the audio boundary or CI dies with a bare exit code.
- **`getResourceAsStream` returns null for project files.** Flix's class loaders parent to
  the *platform* loader and never consult project resources. Read assets from a file path —
  and note it would start working under `flix build-jar`, so a resource-based path fails
  inconsistently, which is worse.

## Writing Flix

Your training data is probably older than this compiler. Read
<https://doc.flix.dev/for-llms.html> before writing Flix: it lists what changed. For the
standard library use <https://api.flix.dev>, or run `flix doc` and read `build/doc/`, which
matches this project's compiler exactly.

The mistakes that show up most often:

- `def main(): Unit \ IO = ...` — arguments come from `Env.getArgs()`, not from parameters
- effects are written with `\`, not `&`
- effect operations are called like ordinary functions; there is no `do` keyword
- handlers are `run { ... } with handler E { ... }`; chain them rather than nesting `run`
- annotations are uppercase: `@Test`, `@Lazy`, `@Parallel`, `@MustUse`
- Java types need an `import` in the *enclosing module*, and Java interop carries `IO` unless
  the compiler's purity table says otherwise

Prefer effects and handlers to callbacks or hand-written CPS, and standard library effects
to Java interop.
