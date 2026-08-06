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

- `src/Runtime/` — the effect boundary; `Runtime/Sketch.flix` is the **only** file that touches Java
- `src/Sketches/` — teaching sketches
- `src/Invaders/` — the pure game model; no `IO`, no window
- `test/` — `@Test` functions; must stay headless (CI enforces this)
- `flix.toml` — package metadata, the Flix version, and dependencies
- `build/`, `artifact/`, `lib/`, `.flix/` — generated; do not edit and do not commit

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
- **Use `System.nanoTime()` for frame timing.** The stdlib `Time.Clock` handler uses
  `System.currentTimeMillis()`, which is wall-clock and not monotonic.

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
