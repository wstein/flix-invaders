# M0 spike result — Gate 1

**Date:** 2026-08-06
**Outcome:** **PASS, with no Java in the repository.**
**Environment:** macOS (darwin 25.5.0, Apple Silicon), OpenJDK 21.0.12 (Homebrew),
Flix 0.75.1 (upstream release), `org.processing:core:4.5.6`.

Gate 1 asked: *Java 21 + pinned Processing Core launches one window and calls one Flix frame
callback.* It does. Flix 0.75.1 can subclass `PApplet` directly, so the "small unrestricted
Java adapter" the design debate assumed is **not needed**.

## What was proven

| # | Question | Result |
|---|---|---|
| S1 | Does the pinned jar work at all, from plain Java? | Yes — window opened, renderer `processing.awt.PGraphicsJava2D` |
| S2 | Can Flix create `new PApplet { ... }`? | Yes — no explicit `def new()` needed |
| S2 | Do overrides actually dispatch? | Yes — `settings`/`setup`/`draw` all ran (320×240 window, not the 100×100 default) |
| S2 | Public instance field reads (`width`, `height`, `keyCode`)? | Yes |
| S2 | Drawing method overloads (`size`, `background`, `fill`, `rect`, `text`)? | Yes |
| S2 | Does `Array#{"..."} @ rc` marshal to Java `String[]`? | Yes |
| S3 | Closed-over `Ref` mutated from the Animation Thread? | Yes — counter read back 60 |
| S3 | Can the enclosing `region` outlive `runSketch`? | Yes, if `main` parks — `runSketch` returns immediately |
| S4 | Effect handler installed **inside** the `draw` callback? | Yes — a `Canvas` effect drove all drawing |
| h | Can `exitActual` be overridden to keep the JVM alive? | Yes — `main` regained control after window exit |

Final run output:

```text
runSketch returned immediately
setup: 320x240
frameRate field reads as 60.0
draw dispatched; first call
draw ran 60 times; calling exit()
exitActual override ran; JVM NOT killed
main done, frames=60
```

## The one real blocker, and its fix

**Processing resolves its own classes reflectively through the thread-context class loader,
which cannot see Flix's jar dependencies.**

`PApplet.makeGraphics` (renderer) and `PApplet.runSketch` (the macOS `ThinkDifferent`
helper) both call:

```java
Thread.currentThread().getContextClassLoader().loadClass(name)
```

Flix loads `[jar-dependencies]` through its own `ExternalJarLoader`, a `URLClassLoader`
whose parent is the **platform** loader — deliberately not the system loader, so Flix code
cannot see compiler internals. The thread-context loader therefore has no idea Processing
exists, and the sketch dies with:

```text
java.lang.ClassNotFoundException: processing.core.ThinkDifferent
java.lang.RuntimeException: The processing.awt.PGraphicsJava2D renderer is not in the class path.
```

Fix — one line before `runSketch`, handing Processing the sketch's own loader:

```flix
Thread.currentThread().setContextClassLoader(sketch.getClass().getClassLoader());
```

This is the single most load-bearing line in the runtime. It was **not** on the predicted
risk list, and it would be very hard to diagnose from the error message alone. It must be
carried into `Runtime/Sketch.flix` with the comment explaining why.

Generalisation worth remembering: *any* Java library that does reflective class loading will
need this treatment under Flix.

## Other findings to carry into M1

- **`pixelDensity` defaults to 2 on HiDPI displays.** Processing warns about it. Pin
  `pixelDensity(1)` so geometry and any cross-platform render checksum are
  display-independent -- and pin it in `settings()`, not `setup()`: outside the PDE,
  `size`, `pixelDensity`, `fullScreen`, and `smooth` throw `IllegalStateException`
  anywhere else.
- **`exitActual` can fire more than once** (observed twice in the plain-Java probe). The
  finished flag must be idempotent.
- **`import` must be inside the `mod` block.** A top-level `import` does not reach into
  `mod Spike { ... }` — it fails with `Undefined type 'PApplet'`, which reads like a
  classpath problem but is not.
- **Do not name the receiver `_this`.** The leading underscore makes it a *hidden* variable
  (`E6956`), so the body cannot use it. The compiler test suite uses `_this` only where the
  receiver is unused. This project uses `app`.
- **No name collisions.** `keyPressed` (public field *and* public method) and `frameRate`
  (public field *and* public method) both work — Flix selects on the argument list, so
  `app.keyPressed` reads the field and `app.keyPressed()` calls the method. Predicted risks
  (c) and (f) are non-issues.
- **`Bool.toString` does not exist**; use string interpolation `"${b}"`.
- **`exit()` → `exitActual()` → `System.exit(0)`** kills the whole process, and `flix run`
  does not fork a JVM. Without the override, closing the window terminates `flix run`
  mid-sentence.

## Dependency verification

- `org.processing:core:4.5.6` resolves from Maven Central as a single
  `[jar-dependencies]` entry: 1 040 800 bytes, sha1
  `e51ed348c657dd24acfe77106563b472d0db04a8`, 246 entries, Java 17 bytecode.
- **Zero Kotlin entries** in the jar, despite the POM's compile-scope `kotlin-stdlib`
  (an artifact of `kotlin("jvm")` being applied to a subproject with no `.kt` sources).
  The predicted "may need kotlin-stdlib" risk is closed.
- **Zero `com.jogamp` classes loaded at runtime**, verified with `-verbose:class`. Only
  `processing.awt.{PGraphicsJava2D, PSurfaceAWT, PImageAWT, PShapeJava2D, ShimAWT}` load.
  JAVA2D genuinely needs no JOGL, so pulling the single jar rather than the full Maven
  dependency (~10 jars of all-platform natives) costs nothing.

Note for the record: an earlier analysis claimed Maven Central publishes no
`org.processing:core:4.x` and that a third-party fork was required. That is wrong — 4.5.6
was downloaded and its sha1 verified against Central's own checksum.

## Keyboard, verified by hand

Manually tested on macOS on 2026-08-06: arrow keys and space behave as expected. Held
arrows move the box continuously (so the runtime's own held-key set works, and Processing's
auto-repeat filtering does not interfere), space toggles brightness on discrete presses, and
ESC and the window close button both exit cleanly.

One bug was found and fixed during that test: `pixelDensity(1)` was being called from
`setup()`, which throws `IllegalStateException`. Processing permits `size`, `pixelDensity`,
`fullScreen`, and `smooth` **only** inside `settings()` when running outside the PDE.

## Not yet proven

- **Windows and Linux.** Everything above is macOS only. Gate 5 still stands.
- The **held-key set**, fixed-timestep accumulator, and input snapshot are M1 work.

## Decision

Proceed to M1 with **no Java in the repository**. The fallback adapter design in the plan is
not needed; keep it recorded only as the contingency if a later platform breaks direct
subclassing.

`src/Spike.flix` stays until `Runtime/Sketch.flix` supersedes it — it is the working
reference for the classloader fix and the handler-inside-callback shape.
