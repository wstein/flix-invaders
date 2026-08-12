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

    def updateClock(budgetNs: Int64, refs: LoopRefs[s, rc]): (Int64, Int64) \ IO + rc = {
        let now = System.nanoTime();
        let elapsed = now - Ref.get(refs#prevNs);
        let capped = if (elapsed < 0i64) 0i64 else if (elapsed > budgetNs) budgetNs else elapsed;
        Ref.put(now, refs#prevNs);
        Ref.put(Ref.get(refs#accNs) + capped, refs#accNs);
        (now, elapsed)
    }

    def sampleInput(app: PApplet, stepNs: Int64, refs: LoopRefs[s, rc]): (Snapshot, Int32) \ IO + rc = {
        let current = Ref.get(refs#heldNow);
        let snapshot = Input.diff(previous = Ref.get(refs#heldPrev), current = current,
                                  mouseX = app.mouseX, mouseY = app.mouseY);
        let due = Input.ticksDue(Ref.get(refs#accNs), stepNs, maxCatchUpSteps());
        if (due > 0) Ref.put(current, refs#heldPrev) else ();
        (snapshot, due)
    }

    def stepSimulation(voices: Audio.Voices, stepNs: Int64, snapshot: Snapshot, due: Int32,
                       step: ((s, Snapshot) -> s \ Sound), refs: LoopRefs[s, rc]
    ): (Int64, Int64, Int64) \ IO + rc = {
        let simStart = System.nanoTime();
        let before = Ref.get(refs#accNs);
        runWithClips(voices, () ->
            advance(step, refs#world, refs#accNs, stepNs, Input.acrossTicks(due, snapshot)));
        let simEnd = System.nanoTime();
        (simStart, simEnd, before)
    }

    def renderAndRecord(app: PApplet, elapsed: Int64, budgetNs: Int64, stepNs: Int64,
                        simStart: Int64, simEnd: Int64, before: Int64,
                        view: ((s, Stats) -> Unit \ Canvas), refs: LoopRefs[s, rc]
    ): Unit \ IO + rc = {
        runWithSurface(app, () -> view(Ref.get(refs#world), Ref.get(refs#stats)));
        let drawEnd = System.nanoTime();
        let taken = Int64.tryToInt32((before - Ref.get(refs#accNs)) / stepNs) |> Option.getWithDefault(0);
        let sample = { frameNs = elapsed, simNs = simEnd - simStart,
                       drawNs = drawEnd - simEnd, steps = taken,
                       clamped = elapsed > budgetNs };
        Ref.put(Stats.observe(Ref.get(refs#stats), sample), refs#stats)
    }

    def checkFrameLimit(app: PApplet, cfg: Config, refs: LoopRefs[s, rc]): Unit \ IO + rc = {
        Ref.put(Ref.get(refs#frames) + 1, refs#frames);
        match cfg#maxFrames {
            case Some(limit) => if (Ref.get(refs#frames) >= limit) app.exit() else ()
            case None => ()
        }
    }

    type alias FrameContext = {
        elapsed = Int64,
        snapshot = Snapshot,
        due = Int32,
        simStart = Int64,
        simEnd = Int64,
        before = Int64
    }

    def initFrame(budgetNs: Int64, refs: LoopRefs[s, rc]): FrameContext \ IO + rc = {
        let (_, elapsed) = updateClock(budgetNs, refs);
        { elapsed = elapsed, snapshot = Input.empty(), due = 0, simStart = 0i64, simEnd = 0i64, before = 0i64 }
    }

    def withInput(app: PApplet, stepNs: Int64, refs: LoopRefs[s, rc], ctx: FrameContext): FrameContext \ IO + rc = {
        let (snapshot, due) = sampleInput(app, stepNs, refs);
        { snapshot = snapshot, due = due | ctx }
    }

    def withSimulation(voices: Audio.Voices, stepNs: Int64, step: ((s, Snapshot) -> s \ Sound), refs: LoopRefs[s, rc], ctx: FrameContext): FrameContext \ IO + rc = {
        let (simStart, simEnd, before) = stepSimulation(voices, stepNs, ctx#snapshot, ctx#due, step, refs);
        { simStart = simStart, simEnd = simEnd, before = before | ctx }
    }

    def withRender(app: PApplet, budgetNs: Int64, stepNs: Int64, view: ((s, Stats) -> Unit \ Canvas), refs: LoopRefs[s, rc], ctx: FrameContext): Unit \ IO + rc = {
        renderAndRecord(app, ctx#elapsed, budgetNs, stepNs, ctx#simStart, ctx#simEnd, ctx#before, view, refs)
    }

    ///
    /// Executes one frame iteration: updates telemetry, samples keyboard input, advances the
    /// simulation across owed ticks, and renders the current world to the Processing canvas.
    ///
    def drawFrame(app: PApplet, cfg: Config, stepNs: Int64, budgetNs: Int64,
                  voices: Audio.Voices, refs: LoopRefs[s, rc],
                  step: ((s, Snapshot) -> s \ Sound),
                  view: ((s, Stats) -> Unit \ Canvas)
    ): Unit \ IO + rc = {
        let ctx = initFrame(budgetNs, refs)
            |> withInput(app, stepNs, refs)
            |> withSimulation(voices, stepNs, step, refs);
        withRender(app, budgetNs, stepNs, view, refs, ctx);
        checkFrameLimit(app, cfg, refs)
    }

    ///
    /// Drives a Processing Core window from a pure state function.
    ///
    /// Opens the window, instantiates the sound engine, and runs until the window closes.
    ///
    /// Telemetry for the frame loop (rate, simulation time, draw time, catch-up steps) is
    /// measured automatically and passed to `view` as a `Stats` record on every frame.
    /// They describe the *previous* frame -- this one is not finished being drawn -- which is
    /// what any such display shows.
    ///
    pub def start(cfg: Config,
                  init: (Int64 -> s),
                  step: ((s, Snapshot) -> s \ Sound),
                  view: ((s, Stats) -> Unit \ Canvas)
    ): s \ IO = region rc {

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
        let voices = Audio.open();

        let sketch = new PApplet {

            def settings(app: PApplet): Unit \ IO = {
                app.size(cfg#width, cfg#height);
                app.pixelDensity(1)
            }

            def setup(app: PApplet): Unit \ IO + rc = {
                setupApplet(app, cfg, hz);
                Ref.put(System.nanoTime(), refs#prevNs)
            }

            def draw(app: PApplet): Unit \ IO + rc =
                drawFrame(app, cfg, stepNs, budgetNs, voices, refs, step, view)

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
    /// Runs one tick per snapshot it is given, spending the accumulator as it goes.
    ///
    /// How many there are, and which of them carry the edges, is decided in `Input` where it
    /// can be tested -- this only walks the list. Each tick covers exactly the same amount of
    /// simulated time, so the result depends on the inputs and never on how long a frame took.
    ///
    def advance(step: ((s, Snapshot) -> s \ Sound),
                world: Ref[s, r],
                accNs: Ref[Int64, r],
                stepNs: Int64,
                inputs: List[Snapshot]): Unit \ Sound + r = match inputs {
        case Nil => ()
        case snapshot :: rest => {
            Ref.put(step(Ref.get(world), snapshot), world);
            Ref.put(Ref.get(accNs) - stepNs, accNs);
            advance(step, world, accNs, stepNs, rest)
        }
    }

    ///
    /// Parks the main thread until the sketch reports that it has exited.
    ///
    def park(done: Ref[Bool, r]): Unit \ IO + r =
        if (Ref.get(done)) ()
        else { Thread.sleep(20i64); park(done) }

}
