///
/// How a sketch is configured.
///
/// `seed` makes the run reproducible; `hz` is the logical simulation rate, which is
/// deliberately independent of the display's frame rate. `maxFrames` stops the sketch after
/// a fixed number of frames, which is how the smoke test terminates on a CI runner.
///
/// `fontPath` is an optional path to a TrueType file. If it is missing or unreadable the
/// sketch simply keeps Processing's default font, so a broken path costs you looks, not a
/// crash.
///
pub type alias Config = {
    title = String,
    width = Int32,
    height = Int32,
    seed = Int64,
    hz = Int32,
    maxFrames = Option[Int32],
    fontPath = Option[String]
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
    import processing.core.PFont
    import java.awt.Font
    import java.io.FileInputStream
    import java.lang.Exception
    import java.lang.System
    import java.lang.Thread

    ///
    /// A 640x480 sketch at 60 Hz with a fixed seed and no frame limit.
    ///
    pub def defaultConfig(): Config =
        { title = "Flix sketch", width = 640, height = 480, seed = 42i64, hz = 60,
          maxFrames = None, fontPath = None }

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

    ///
    /// The seed a run starts from: random unless `FLIX_INVADERS_SEED` names one.
    ///
    /// The game was seeded with a constant, so every launch played the identical game and
    /// the attract screen replayed the identical demo. Reproducibility is worth keeping, but
    /// it belongs to the tests -- which call `Game.initial(seed)` directly and are unaffected
    /// by this -- rather than to the thing a person sits down in front of.
    ///
    /// `System.nanoTime` rather than the wall clock: two launches in the same millisecond
    /// would collide on `currentTimeMillis`, and nothing here needs the value to mean a date.
    /// The note elsewhere about `nanoTime` not being wall-clock is about *measuring* time; an
    /// arbitrary origin is exactly what a seed wants.
    ///
    /// The `F3` overlay shows the seed of whichever world is on screen, so a game worth
    /// keeping can be read off and played again by setting the variable. That is the whole
    /// reason the override exists: without it, a bug found once could not be shown to anyone.
    /// Note the attract screen's `SEED` is the demo's, which `Session.demoSeed` offsets by
    /// 977 so it never mirrors a real game -- feeding that one back gives a different game,
    /// not the demo you were watching.
    ///
    pub def seedFromEnv(): Option[Int64] \ IO = {
        let raw = System.getenv("FLIX_INVADERS_SEED");
        if (Object.isNull(raw)) None else parseSeed(raw)
    }

    /// The parsing half, split out so it can be tested without an environment.
    pub def parseSeed(raw: String): Option[Int64] = match Int64.parse(10, String.trim(raw)) {
        case Result.Ok(n) => Some(n)
        case _ => None
    }

    pub def freshSeed(): Int64 \ IO = match seedFromEnv() {
        case Some(n) => n
        case None => System.nanoTime()
    }

    ///
    /// The size a loaded font is first derived to.
    ///
    /// Anything works -- `Canvas.textSize` re-derives the native font on every size change --
    /// but it must not be left at the size of 1 that `Font.createFont` returns, or `PFont`
    /// builds a three-pixel rasteriser and the text is unreadable.
    ///
    def baseFontSize(): Float32 = 16.0f32

    ///
    /// Loads a TrueType font from a file path, or `None` if anything goes wrong.
    ///
    /// A file path rather than the classpath, deliberately: Flix loads code through class
    /// loaders that parent to the *platform* loader and never consult the project's own
    /// resources, so `getResourceAsStream` returns null here -- and would start working
    /// under `flix build-jar`, which is worse than failing consistently.
    ///
    /// A file path rather than the classpath, deliberately -- see above.
    ///
    /// The stream is closed on both paths. Closing it only after `createFont` returns leaks
    /// the descriptor whenever the file is present but unreadable as a font, which is the one
    /// case this function exists to survive.
    def loadFont(path: String): Option[PFont] \ IO =
        try {
            let stream = new FileInputStream(path);
            let font = try {
                let base = Font.createFont(Font.TRUETYPE_FONT, stream);
                Some(new PFont(base.deriveFont(baseFontSize()), false))
            } catch {
                case _: Exception => None
            };
            stream.close();
            font
        } catch {
            case _: Exception => None
        }

    def setupApplet(app: PApplet, cfg: Config, hz: Int32): Unit \ IO = {
        app.getSurface().setTitle(cfg#title);
        app.frameRate(Int32.toFloat32(hz));
        match cfg#fontPath {
            case None => ()
            case Some(path) => match loadFont(path) {
                case None => println("could not load font ${path}; using the default")
                case Some(font) => app.textFont(font)
            }
        };
        app.textSize(14.0f32);
        app.noStroke()
    }

    ///
    /// Splits a colour into the three float channels Processing wants.
    ///
    /// Deliberately not a packed `0xRRGGBB` integer: Processing reads a bare int as ARGB,
    /// so a value with no alpha byte is fully transparent and nothing is drawn.
    ///
    def channels(c: Color): (Float32, Float32, Float32) =
        (Int32.toFloat32(Color.redOf(c)),
         Int32.toFloat32(Color.greenOf(c)),
         Int32.toFloat32(Color.blueOf(c)))

    ///
    /// The range of simulation rates the runtime will accept.
    ///
    /// One tick a second is already unplayable and a thousand is far past any display; the
    /// bounds exist to keep the arithmetic sound rather than to express a preference.
    ///
    def minimumHz(): Int32 = 1
    def maximumHz(): Int32 = 1000

    /// Never advance more than this many logical steps in one frame.
    ///
    /// Without a clamp, a stall -- dragging the window, waking from sleep -- would leave a
    /// huge accumulated delta and the simulation would try to catch up all at once, stalling
    /// further. This trades exact catch-up for staying responsive.
    def maxCatchUpSteps(): Int32 = 5

    ///
    /// Everything one frame is allowed to change, gathered so the frame loop can be written as
    /// ordinary functions rather than as one closure over eight separate `Ref`s.
    ///
    /// `heldNow` is written by the keyboard callbacks and read by the frame; `heldPrev` is the
    /// reading the last tick compared against, and the two together are what makes a press an
    /// edge rather than a state. `accNs` is simulated time owed but not yet run, and `prevNs`
    /// the clock reading this frame is measured from.
    ///
    type alias LoopRefs[s: Type, rc: Region] = {
        world = Ref[s, rc],
        heldNow = Ref[Set[Key], rc],
        heldPrev = Ref[Set[Key], rc],
        accNs = Ref[Int64, rc],
        prevNs = Ref[Int64, rc],
        frames = Ref[Int32, rc],
        stats = Ref[Stats, rc]
    }

    ///
    /// Everything a frame needs, settled once when the window opens.
    ///
    /// The alternative is handing each beat the five or six of these it happens to want, which
    /// is how a frame loop acquires an eight-argument function nobody can call from memory.
    /// The two halves stay apart inside it: the fields here are fixed for the run, and `refs`
    /// is the only thing a frame may write.
    ///
    type alias Loop[s: Type, rc: Region] = {
        cfg = Config,
        stepNs = Int64,
        budgetNs = Int64,
        voices = Audio.Voices,
        refs = LoopRefs[s, rc],
        step = (s, Snapshot) -> s \ Sound,
        view = (s, Stats) -> Unit \ Canvas
    }

    ///
    /// One frame, as the five things a frame does.
    ///
    /// Read the body downwards and you have the whole loop: the clock moves, the keyboard is
    /// read, the world catches up, the world is painted, and the frame is counted. Each beat
    /// is one function below and each hands the next what it needs, so the order here is the
    /// data flow rather than a convention that could quietly drift.
    ///
    /// The two timings come back from the beats that earn them, rather than from a stopwatch
    /// strung across this body, because it is the *work* that has to be bracketed: Processing
    /// sleeps to hold the target rate, so timing a whole frame measures the rate limiter and
    /// reports ~16.7ms at 60Hz whatever the sketch actually costs.
    ///
    def drawFrame(app: PApplet, loop: Loop[s, rc]): Unit \ IO + rc = {
        let elapsed         = accumulate(loop);
        let (due, snapshot) = readKeyboard(app, loop);
        let simNs           = simulate(loop, due, snapshot);
        let drawNs          = paint(app, loop);
        observe(loop, { frameNs = elapsed, simNs = simNs, drawNs = drawNs,
                        steps = due, clamped = elapsed > loop#budgetNs });
        countFrame(app, loop)
    }

    ///
    /// The clock beat: how long since the last frame, and that long added to what is owed.
    ///
    /// `System.nanoTime` and not `Time.Clock`, whose handler is the wall-clock
    /// `currentTimeMillis` and can jump backwards on an NTP correction.
    ///
    /// What is *owed* is clamped to the catch-up budget; what is *returned* is the whole gap.
    /// Two numbers on purpose: the simulation must not try to make up an arbitrary stall, but
    /// the frame-rate figure should still show that the stall happened. A gap below zero
    /// cannot come from a monotonic clock and is floored anyway, so that a surprising reading
    /// cannot run the accumulator backwards.
    ///
    def accumulate(loop: Loop[s, rc]): Int64 \ IO + rc = {
        let refs = loop#refs;
        let now = System.nanoTime();
        let elapsed = now - Ref.get(refs#prevNs);
        let owed = if (elapsed < 0i64) 0i64 else Int64.min(elapsed, loop#budgetNs);
        Ref.put(now, refs#prevNs);
        Ref.put(Ref.get(refs#accNs) + owed, refs#accNs);
        elapsed
    }

    ///
    /// The input beat: one reading of the keyboard, and how many ticks it has to drive.
    ///
    /// The reading is taken once and frozen, so every tick this frame owes sees the same
    /// keyboard rather than whatever the Animation Thread has done to it since.
    ///
    /// The count is worked out here, before any tick runs, because the edges belong to the
    /// first tick alone and the previous key state may only be retired once a tick has
    /// actually consumed it. A frame that owes no tick therefore leaves `heldPrev` where it
    /// is: retiring it would hand the press to nobody, since the next frame would compare
    /// against a set that already holds the key and see no transition at all. On a display
    /// faster than the simulation that is most frames, so it is the common case, not a corner.
    ///
    def readKeyboard(app: PApplet, loop: Loop[s, rc]): (Int32, Snapshot) \ IO + rc = {
        let refs = loop#refs;
        let current = Ref.get(refs#heldNow);
        let snapshot = Input.diff(previous = Ref.get(refs#heldPrev), current = current,
                                  mouseX = app.mouseX, mouseY = app.mouseY);
        let due = Input.ticksDue(Ref.get(refs#accNs), loop#stepNs, maxCatchUpSteps());
        if (due > 0) Ref.put(current, refs#heldPrev) else ();
        (due, snapshot)
    }

    ///
    /// The simulation beat: run the ticks this frame owes, and report what they cost.
    ///
    /// `Input.acrossTicks` decides which of the ticks carry the edges and `advance` only walks
    /// the list. The time those ticks cover is spent here, in one line, before they run: it is
    /// exactly `due` of them and always was, so there is nothing to find out afterwards by
    /// subtracting one accumulator reading from another -- which is also why the caller can
    /// report `due` as the number of steps taken.
    ///
    def simulate(loop: Loop[s, rc], due: Int32, snapshot: Snapshot): Int64 \ IO + rc = {
        let refs = loop#refs;
        Ref.put(Ref.get(refs#accNs) - loop#stepNs * Int32.toInt64(due), refs#accNs);
        let started = System.nanoTime();
        runWithClips(loop#voices, () ->
            advance(loop#step, refs#world, Input.acrossTicks(due, snapshot)));
        System.nanoTime() - started
    }

    ///
    /// The drawing beat: paint the world as it now stands, and report what that cost.
    ///
    /// The `Canvas` handler is installed here, inside the callback, on purpose: handlers are
    /// stack-scoped and `draw` runs on Processing's Animation Thread, so one installed around
    /// `runSketch` on the main thread would be invisible from here.
    ///
    /// The figures handed to `view` are the previous frame's, because this frame's are still
    /// being measured -- which is what any such display shows.
    ///
    def paint(app: PApplet, loop: Loop[s, rc]): Int64 \ IO + rc = {
        let world = Ref.get(loop#refs#world);
        let figures = Ref.get(loop#refs#stats);
        let started = System.nanoTime();
        runWithSurface(app, () -> (loop#view)(world, figures));
        System.nanoTime() - started
    }

    ///
    /// The telemetry beat: fold this frame's measurements into the running figures.
    ///
    def observe(loop: Loop[s, rc], sample: Stats.Sample): Unit \ rc =
        Ref.put(Stats.observe(Ref.get(loop#refs#stats), sample), loop#refs#stats)

    ///
    /// The counting beat: one more frame gone, and the window closed if that was the last one.
    ///
    /// `maxFrames` is how the smoke test bounds a windowed run on a machine nobody is sitting
    /// in front of. `app.exit()` arrives at `exitActual`, which this sketch overrides.
    ///
    def countFrame(app: PApplet, loop: Loop[s, rc]): Unit \ IO + rc = {
        let frames = Ref.get(loop#refs#frames) + 1;
        Ref.put(frames, loop#refs#frames);
        match loop#cfg#maxFrames {
            case Some(limit) => if (frames >= limit) app.exit() else ()
            case None => ()
        }
    }

    ///
    /// Drives a Processing Core window from a pure state function.
    ///
    /// Opens the window, instantiates the sound engine, and runs until the window closes.
    ///
    /// `init` builds the starting world from `cfg`'s seed, `step` advances it by exactly one
    /// logical tick, and `view` describes what to draw. `step` may use only `Sound` and
    /// `view` only `Canvas`; neither can reach `IO`. That is the whole point of the boundary,
    /// and it is enforced by these types rather than by convention.
    ///
    /// A step with nothing to play is lifted with `Sound.silent`.
    ///
    /// The simulation advances on a fixed timestep, so behaviour does not depend on frame rate
    /// or machine speed. That is what makes a recorded input script replay exactly.
    ///
    /// Returns the state the window closed on, so a caller can persist something the player
    /// earned. It is read after `park` returns, by which point the Animation Thread has
    /// stopped writing it.
    ///
    /// `view` is also handed the runtime's own performance figures, because the frame loop is
    /// the only thing that can measure them and the view is the only thing that can show them.
    /// They describe the *previous* frame -- this one is not finished being drawn -- which is
    /// what any such display shows.
    ///
    pub def start(cfg: Config,
                  init: (Int64 -> s),
                  step: ((s, Snapshot) -> s \ Sound),
                  view: ((s, Stats) -> Unit \ Canvas)
    ): s \ IO = region rc {

        // `Config` is a public record anyone can build, and an hz of nought divides by zero
        // before the window even opens. A negative one runs the clock backwards, and anything
        // above a billion rounds `stepNs` down to nought and divides by zero again on the
        // frame-timing arithmetic. None of those are worth a crash in a game, so the rate is
        // brought into a range a display can plausibly be asked for.
        let hz = Int32.max(minimumHz(), Int32.min(maximumHz(), cfg#hz));
        let stepNs = 1000000000i64 / Int32.toInt64(hz);
        let budgetNs = stepNs * Int32.toInt64(maxCatchUpSteps());

        let refs = {
            world = Ref.fresh(rc, init(cfg#seed)),
            heldNow = Ref.fresh(rc, (Set.empty(): Set[Key])),
            heldPrev = Ref.fresh(rc, (Set.empty(): Set[Key])),
            accNs = Ref.fresh(rc, 0i64),
            prevNs = Ref.fresh(rc, 0i64),
            frames = Ref.fresh(rc, 0),
            stats = Ref.fresh(rc, Stats.empty())
        };
        let done = Ref.fresh(rc, false);

        // Opened once. An empty pool means the machine has no usable audio device, and every
        // Audio call then does nothing.
        let voices = Audio.open();

        // Assembled here and never rebuilt: `draw` is handed one value rather than eight.
        let loop = { cfg = cfg, stepNs = stepNs, budgetNs = budgetNs, voices = voices,
                     refs = refs, step = step, view = view };

        let sketch = new PApplet {

            def settings(app: PApplet): Unit \ IO = {
                app.size(cfg#width, cfg#height);
                // Outside the PDE, size/pixelDensity/fullScreen/smooth are legal ONLY here.
                // Pinning the density keeps geometry identical on HiDPI and standard displays.
                app.pixelDensity(1)
            }

            def setup(app: PApplet): Unit \ IO + rc = {
                setupApplet(app, cfg, hz);
                Ref.put(System.nanoTime(), refs#prevNs)
            }

            def draw(app: PApplet): Unit \ IO + rc =
                drawFrame(app, loop)

            def keyPressed(app: PApplet): Unit \ IO + rc =
                Ref.put(Set.insert(Key.fromCode(app.keyCode), Ref.get(refs#heldNow)), refs#heldNow)

            def keyReleased(app: PApplet): Unit \ IO + rc =
                Ref.put(Set.remove(Key.fromCode(app.keyCode), Ref.get(refs#heldNow)), refs#heldNow)

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
        park(done);
        Audio.close(voices);
        Ref.get(refs#world)
    }

    ///
    /// Interprets `Sound` by triggering clips.
    ///
    /// The counterpart to `Sound.runWithCollector`, and the only interpretation that needs a
    /// device -- which is why it lives here rather than in `Sound`. `Clip.start()` returns
    /// immediately, so a frame is never held up waiting for audio.
    ///
    def runWithClips(voices: Audio.Voices, f: Unit -> a \ ef): a \ (ef - Sound) + IO =
        run {
            f()
        } with handler Sound {
            def play(cmd, k) = { Audio.play(voices, cmd); k() }
        }

    ///
    /// Interprets `Canvas` by painting onto a live sketch.
    ///
    /// The counterpart to `Canvas.runWithCollector`, and the only interpretation that needs
    /// a window -- which is why it lives here rather than in `Canvas`.
    ///
    def runWithSurface(app: PApplet, f: Unit -> a \ ef): a \ (ef - Canvas) + IO =
        run {
            f()
        } with handler Canvas {
            def clear(c, k) = { let (r, g, b) = channels(c); app.background(r, g, b); k() }
            def fill(c, k) = { let (r, g, b) = channels(c); app.fill(r, g, b); k() }
            def fillAlpha(c, a, k) = {
                let (r, g, b) = channels(c);
                app.fill(r, g, b, Int32.toFloat32(a));
                k()
            }
            def rect(x, y, w, h, k) = { app.rect(x, y, w, h); k() }
            def ellipse(x, y, w, h, k) = { app.ellipse(x, y, w, h); k() }
            def text(s, x, y, k) = { app.text(s, x, y); k() }
            def textSize(px, k) = { app.textSize(px); k() }
            def dimensions(k) = k((app.width, app.height))
        }

    ///
    /// Runs one tick per snapshot it is given.
    ///
    /// How many there are, and which of them carry the edges, is decided in `Input` where it
    /// can be tested -- this only walks the list. Each tick covers exactly the same amount of
    /// simulated time, so the result depends on the inputs and never on how long a frame took.
    /// The clock is `simulate`'s business, not this function's: it knows the list's length
    /// before the walk starts, so nothing is learned by paying for the ticks one at a time.
    ///
    def advance(step: ((s, Snapshot) -> s \ Sound),
                world: Ref[s, r],
                inputs: List[Snapshot]): Unit \ Sound + r =
        inputs |> List.forEach(snapshot -> Ref.transform(s -> step(s, snapshot), world))

    ///
    /// Parks the main thread until the sketch reports that it has exited.
    ///
    /// A recursion because there is no sequence to traverse: it waits on a flag another
    /// thread will set, and how many times it looks is not known in advance.
    ///
    def park(done: Ref[Bool, r]): Unit \ IO + r =
        if (Ref.get(done)) ()
        else { Thread.sleep(20i64); park(done) }

}
