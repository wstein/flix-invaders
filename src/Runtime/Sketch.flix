///
/// How a sketch is configured.
///
/// `seed` makes the run reproducible; `hz` is the logical simulation rate, which is
/// deliberately independent of the display's frame rate. `maxFrames` stops the sketch after
/// a fixed number of frames, which is how the smoke test terminates on a CI runner.
///
pub type alias Config = {
    title = String,
    width = Int32,
    height = Int32,
    seed = Int64,
    hz = Int32,
    maxFrames = Option[Int32]
}

///
/// The window runtime.
///
/// This is the only module in `src/` that touches Java. Everything above it -- sketches and
/// the game -- sees `Canvas`, `Input`, and pure functions, and never learns that Processing
/// exists.
///
mod Sketch {

    import processing.core.PApplet
    import java.lang.System
    import java.lang.Thread

    ///
    /// A 640x480 sketch at 60 Hz with a fixed seed and no frame limit.
    ///
    pub def defaultConfig(): Config =
        { title = "Flix sketch", width = 640, height = 480, seed = 42i64, hz = 60, maxFrames = None }

    ///
    /// Reads a frame limit from the `FLIX_SKETCH_MAX_FRAMES` environment variable.
    ///
    /// This is how the cross-platform smoke test bounds a windowed run so it terminates on
    /// its own. Anything unset, unparseable, or non-positive means "run until closed".
    ///
    pub def maxFramesFromEnv(): Option[Int32] \ IO = {
        let raw = System.getenv("FLIX_SKETCH_MAX_FRAMES");
        if (Object.isNull(raw)) None
        else match Int32.parse(10, raw) {
            case Result.Ok(n) if n > 0 => Some(n)
            case _ => None
        }
    }

    /// Never advance more than this many logical steps in one frame.
    ///
    /// Without a clamp, a stall -- dragging the window, waking from sleep -- would leave a
    /// huge accumulated delta and the simulation would try to catch up all at once, stalling
    /// further. This trades exact catch-up for staying responsive.
    def maxCatchUpSteps(): Int32 = 5

    ///
    /// Opens one window and runs the simulation until it closes.
    ///
    /// `init` builds the starting world from `cfg`'s seed, `step` advances it by exactly one
    /// logical tick, and `view` describes what to draw. `init` and `step` are completely
    /// pure; `view` may use only `Canvas`. None of them can reach `IO` -- that is the whole
    /// point of the boundary, and it is enforced by these types rather than by convention.
    ///
    /// The simulation advances on a fixed timestep, so behaviour does not depend on frame
    /// rate or machine speed. That is what makes a recorded input script replay exactly.
    ///
    pub def start(cfg: Config,
                  init: (Int64 -> s),
                  step: (s -> Snapshot -> s),
                  view: (s -> Unit \ Canvas)
    ): Unit \ IO = region rc {

        let stepNs = 1000000000i64 / Int32.toInt64(cfg#hz);
        let budgetNs = stepNs * Int32.toInt64(maxCatchUpSteps());

        let world = Ref.fresh(rc, init(cfg#seed));
        let heldNow = Ref.fresh(rc, (Set.empty(): Set[Key]));
        let heldPrev = Ref.fresh(rc, (Set.empty(): Set[Key]));
        let accNs = Ref.fresh(rc, 0i64);
        let prevNs = Ref.fresh(rc, 0i64);
        let frames = Ref.fresh(rc, 0);
        let done = Ref.fresh(rc, false);

        let sketch = new PApplet {

            def settings(app: PApplet): Unit \ IO = {
                app.size(cfg#width, cfg#height);
                // Outside the PDE, size/pixelDensity/fullScreen/smooth are legal ONLY here.
                // Pinning the density keeps geometry identical on HiDPI and standard displays.
                app.pixelDensity(1)
            }

            def setup(app: PApplet): Unit \ IO + rc = {
                app.getSurface().setTitle(cfg#title);
                app.frameRate(Int32.toFloat32(cfg#hz));
                app.textSize(14.0f32);
                Ref.put(System.nanoTime(), prevNs)
            }

            def draw(app: PApplet): Unit \ IO + rc = {
                // Monotonic; NOT Time.Clock, whose handler is wall-clock currentTimeMillis
                // and can jump backwards on an NTP correction.
                let now = System.nanoTime();
                let elapsed = now - Ref.get(prevNs);
                let capped = if (elapsed < 0i64) 0i64 else if (elapsed > budgetNs) budgetNs else elapsed;
                Ref.put(now, prevNs);
                Ref.put(Ref.get(accNs) + capped, accNs);

                // Captured once and frozen, so every step this frame sees the same input.
                let current = Ref.get(heldNow);
                let snapshot = Input.diff(Ref.get(heldPrev), current, app.mouseX, app.mouseY);
                Ref.put(current, heldPrev);

                advance(step, world, accNs, stepNs, snapshot, maxCatchUpSteps());

                // The handler is installed here, inside the callback, on purpose: handlers
                // are stack-scoped and `draw` runs on Processing's Animation Thread, so a
                // handler installed around `runSketch` on the main thread would be invisible.
                run {
                    view(Ref.get(world))
                } with handler Canvas {
                    def clear(c, k) = { app.background(Color.toInt32(c)); k() }
                    def fill(c, k) = { app.fill(Color.toInt32(c)); k() }
                    def rect(x, y, w, h, k) = { app.rect(x, y, w, h); k() }
                    def ellipse(x, y, w, h, k) = { app.ellipse(x, y, w, h); k() }
                    def text(s, x, y, k) = { app.text(s, x, y); k() }
                    def textSize(px, k) = { app.textSize(px); k() }
                    def dimensions(k) = k((app.width, app.height))
                };

                Ref.put(Ref.get(frames) + 1, frames);
                match cfg#maxFrames {
                    case Some(limit) => if (Ref.get(frames) >= limit) app.exit() else ()
                    case None => ()
                }
            }

            def keyPressed(app: PApplet): Unit \ IO + rc =
                Ref.put(Set.insert(Key.fromCode(app.keyCode), Ref.get(heldNow)), heldNow)

            def keyReleased(app: PApplet): Unit \ IO + rc =
                Ref.put(Set.remove(Key.fromCode(app.keyCode), Ref.get(heldNow)), heldNow)

            // The only System.exit(0) in PApplet, and the documented embedding hook.
            // Overriding it hands control back to `main` instead of killing the JVM
            // mid-frame -- `flix run` does not fork. It can fire more than once, so setting
            // an already-set flag must be harmless.
            def exitActual(_app: PApplet): Unit \ rc =
                Ref.put(true, done)
        };

        // Processing resolves its renderer (processing.awt.PGraphicsJava2D) and its macOS
        // helper (processing.core.ThinkDifferent) through
        //     Thread.currentThread().getContextClassLoader().loadClass(...)
        // but Flix loads jar dependencies through its own ExternalJarLoader, whose parent is
        // the *platform* loader. Without this line Processing cannot find its own classes and
        // dies with "The processing.awt.PGraphicsJava2D renderer is not in the class path."
        Thread.currentThread().setContextClassLoader(sketch.getClass().getClassLoader());

        PApplet.runSketch(Array#{cfg#title} @ rc, sketch);

        // runSketch returns immediately. The region has to be kept alive by hand, because
        // `draw` is still reading and writing these Refs on the Animation Thread.
        park(done)
    }

    ///
    /// Advances the world by whole logical steps while the accumulator allows it.
    ///
    /// `step` always receives the same snapshot, and each step covers exactly the same
    /// amount of simulated time, so the result depends only on the inputs -- never on how
    /// long the frame took.
    ///
    def advance(step: (s -> Snapshot -> s),
                world: Ref[s, r],
                accNs: Ref[Int64, r],
                stepNs: Int64,
                snapshot: Snapshot,
                budget: Int32): Unit \ r =
        if (budget <= 0 or Ref.get(accNs) < stepNs) ()
        else {
            Ref.put(step(Ref.get(world), snapshot), world);
            Ref.put(Ref.get(accNs) - stepNs, accNs);
            advance(step, world, accNs, stepNs, snapshot, budget - 1)
        }

    ///
    /// Parks the main thread until the sketch reports that it has exited.
    ///
    def park(done: Ref[Bool, r]): Unit \ IO + r =
        if (Ref.get(done)) ()
        else { Thread.sleep(20i64); park(done) }

}
