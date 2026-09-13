///
/// How a sketch is configured.
///
/// `seed` makes the run reproducible; `hz` is the logical simulation rate, which is
/// deliberately independent of the display's frame rate. `maxFrames` stops the sketch after
/// a fixed number of frames, which is how the smoke test terminates on a CI runner.
///
/// `fontPath` is an optional path to a TrueType file. If it is missing or unreadable the
/// sketch simply keeps the platform's default font, so a broken path costs you looks, not a
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
/// The frame loop.
///
/// `Surface` below it owns the window and the toolkit; this module owns time. It reads the
/// monotonic clock, decides how many logical ticks a frame owes, runs them, and paints --
/// and that one `System.nanoTime` is the only Java it touches.
///
/// Everything above it -- sketches and the game -- sees `Canvas`, `Input`, and pure
/// functions, and never learns that a window exists.
///
mod Sketch {

    import java.lang.System

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
    pub def parseSeed(raw: String): Option[Int64] =
        match Int64.parse(10, String.trim(raw)) {
            case Result.Ok(n) => Some(n)
            case _ => None
        }

    /// Generates a fresh random seed from system nanoTime or reads FLIX_INVADERS_SEED.
    pub def freshSeed(): Int64 \ IO = match seedFromEnv() {
        case Some(n) => n
        case None => System.nanoTime()
    }

    ///
    /// The range of simulation rates the runtime will accept.
    ///
    /// One tick a second is already unplayable and a thousand is far past any display; the
    /// bounds exist to keep the arithmetic sound rather than to express a preference.
    ///
    def minimumHz(): Int32 = 1
    def maximumHz(): Int32 = 1000

    ///
    /// A simulation rate the frame loop's arithmetic can survive.
    ///
    /// `Config` is a public record anyone can build, and an hz of nought divides by zero
    /// before the window even opens. A negative one runs the clock backwards, and anything
    /// above a billion rounds `stepNs` down to nought and divides by zero again on the
    /// frame-timing arithmetic. None of those are worth a crash in a game, so the rate is
    /// brought into a range a display can plausibly be asked for.
    ///
    pub def clampHz(hz: Int32): Int32 =
        Int32.max(minimumHz(), Int32.min(maximumHz(), hz))

    /// How long one logical tick covers, in nanoseconds.
    pub def stepNsFor(hz: Int32): Int64 =
        1000000000i64 / Int32.toInt64(clampHz(hz))

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
    /// `heldPrev` is the keyboard reading the last tick compared against, and it together
    /// with what the surface reports now is what makes a press an edge rather than a state.
    /// `accNs` is simulated time owed but not yet run, and `prevNs` the clock reading this
    /// frame is measured from.
    ///
    type alias LoopRefs[s: Type, rc: Region] = {
        world = Ref[s, rc],
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
        surface = Surface.Window[rc],
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
    /// strung across this body, because it is the *work* that has to be bracketed: the timer
    /// paces the loop to the target rate, so timing a whole frame measures the pacing and
    /// reports ~16ms at 60Hz whatever the sketch actually costs.
    ///
    def drawFrame(loop: Loop[s, rc]): Unit \ IO + rc = {
        let elapsed         = accumulate(loop);
        let (due, snapshot) = readKeyboard(loop);
        let simNs           = simulate(loop, due, snapshot);
        let drawNs          = paint(loop);
        observe(loop, { frameNs = elapsed, simNs = simNs, drawNs = drawNs,
                        steps = due, clamped = elapsed > loop#budgetNs });
        countFrame(loop)
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
    /// keyboard. The surface reports AWT key codes, and this is where a number becomes a
    /// name -- nothing above the runtime ever sees a code.
    ///
    /// The count is worked out here, before any tick runs, because the edges belong to the
    /// first tick alone and the previous key state may only be retired once a tick has
    /// actually consumed it. A frame that owes no tick therefore leaves `heldPrev` where it
    /// is: retiring it would hand the press to nobody, since the next frame would compare
    /// against a set that already holds the key and see no transition at all. On a display
    /// faster than the simulation that is most frames, so it is the common case, not a corner.
    ///
    def readKeyboard(loop: Loop[s, rc]): (Int32, Snapshot) \ rc = {
        let refs = loop#refs;
        let current = Set.map(Key.fromCode, Surface.keysHeld(loop#surface));
        let prev = Ref.get(refs#heldPrev);
        let snapshot = Input.diff(previous = prev, current = current);
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
    def simulate(loop: Loop[s, rc], due: Int32,
                 snapshot: Snapshot): Int64 \ IO + rc = {
        let refs = loop#refs;
        let stepsNs = loop#stepNs * Int32.toInt64(due);
        Ref.put(Ref.get(refs#accNs) - stepsNs, refs#accNs);
        let started = System.nanoTime();
        let currentSnapshot = Input.acrossTicks(due, snapshot);
        runWithClips(loop#voices, () ->
            advance(loop#step, refs#world, currentSnapshot));
        System.nanoTime() - started
    }

    ///
    /// The drawing beat: paint the world as it now stands, and report what that cost.
    ///
    /// The `Canvas` handler is installed here, inside the callback, on purpose: handlers are
    /// stack-scoped and the frame runs on AWT's event dispatch thread, so one installed
    /// around `Surface.loop` on the main thread would be invisible from here.
    ///
    /// The figures handed to `view` are the previous frame's, because this frame's are still
    /// being measured -- which is what any such display shows.
    ///
    def paint(loop: Loop[s, rc]): Int64 \ IO + rc = {
        let world = Ref.get(loop#refs#world);
        let figures = Ref.get(loop#refs#stats);
        let started = System.nanoTime();
        runWithSurface(loop#surface, () -> (loop#view)(world, figures));
        Surface.present(loop#surface);
        System.nanoTime() - started
    }

    ///
    /// The telemetry beat: fold this frame's measurements into the running figures.
    ///
    def observe(loop: Loop[s, rc], sample: Stats.Sample): Unit \ rc = {
        let currentStats = Ref.get(loop#refs#stats);
        Ref.put(Stats.observe(currentStats, sample), loop#refs#stats)
    }

    ///
    /// The counting beat: one more frame gone, and the window closed if that was the last one.
    ///
    /// `maxFrames` is how the smoke test bounds a windowed run on a machine nobody is sitting
    /// in front of.
    ///
    def countFrame(loop: Loop[s, rc]): Unit \ IO + rc = {
        let frames = Ref.get(loop#refs#frames) + 1;
        Ref.put(frames, loop#refs#frames);
        match loop#cfg#maxFrames {
            case Some(limit) =>
                if (frames >= limit) Surface.requestClose(loop#surface) else ()
            case None => ()
        }
    }

    ///
    /// Opens the resources and references that remain fixed for one run of the frame loop.
    ///
    /// A `Loop` collects the resulting resources with the pure callbacks. It is built once,
    /// before any frame runs, so the callback has one stable value rather than reconstructing
    /// window, audio, or timing state per frame.
    ///
    def openLoop(rc: Region[r],
                 cfg: Config,
                 init: Int64 -> s,
                 step: (s, Snapshot) -> s \ Sound,
                 view: (s, Stats) -> Unit \ Canvas
    ): Loop[s, r] \ IO + r = {
        let hz = clampHz(cfg#hz);
        let stepNs = stepNsFor(hz);
        let budgetNs = stepNs * Int32.toInt64(maxCatchUpSteps());

        let refs = {
            world = Ref.fresh(rc, init(cfg#seed)),
            heldPrev = Ref.fresh(rc, (Set.empty(): Set[Key])),
            accNs = Ref.fresh(rc, 0i64),
            prevNs = Ref.fresh(rc, System.nanoTime()),
            frames = Ref.fresh(rc, 0),
            stats = Ref.fresh(rc, Stats.empty())
        };

        let surface = Surface.open(rc, cfg#title, width = cfg#width, height = cfg#height,
                                   cfg#fontPath);
        Surface.textSize(Surface.sheet(surface), defaultTextSize());
        let voices = Audio.open();

        { cfg = cfg, stepNs = stepNs, budgetNs = budgetNs, surface = surface,
          voices = voices, refs = refs, step = step, view = view }
    }

    ///
    /// Closes a loop's resources after its frame callback has stopped and returns its last world.
    ///
    def closeLoop(loop: Loop[s, r]): s \ IO + r = {
        Surface.close(loop#surface);
        Audio.close(loop#voices);
        Ref.get(loop#refs#world)
    }

    ///
    /// Drives a window from a pure state function.
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
    /// earned. It is read after `Surface.loop` returns, by which point no frame is running.
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
    ): s \ IO =
        region rc {
        let loop = openLoop(rc, cfg, init, step, view);

        // The display is asked for the same rate as the simulation. They are not the same
        // thing -- the accumulator exists precisely because a frame is not a tick -- but
        // there is no reason to draw more often than the world changes.
        Surface.loop(loop#surface, loop#stepNs, () -> drawFrame(loop));
        closeLoop(loop)
    }

    ///
    /// The text size a sketch starts at, before any `Canvas.textSize` call.
    ///
    def defaultTextSize(): Float32 = 14.0f32

    ///
    /// Interprets `Sound` by triggering clips.
    ///
    /// The counterpart to `Sound.runWithCollector`, and the only interpretation that needs a
    /// device -- which is why it lives here rather than in `Sound`. `Clip.start()` returns
    /// immediately, so a frame is never held up waiting for audio.
    ///
    def runWithClips(voices: Audio.Voices, f: Unit -> a \ ef)
        : a \ (ef - Sound) + IO =
        run {
            f()
        } with handler Sound {
            def play(cmd, k) = { Audio.play(voices, cmd); k() }
        }

    ///
    /// Interprets `Canvas` by painting onto a live surface.
    ///
    /// The counterpart to `Canvas.runWithCollector`, and the only interpretation that needs
    /// a window -- which is why it lives here rather than in `Canvas`. Every case is one
    /// call, because `Surface` was given the same vocabulary the effect is written in.
    ///
    def runWithSurface(win: Surface.Window[rc], f: Unit -> a \ ef)
        : a \ (ef - Canvas) + IO + rc =
        let sheet = Surface.sheet(win);
        run {
            f()
        } with handler Canvas {
            def clear(c, k) = { Surface.background(sheet, c); k() }
            def fill(c, k) = { Surface.fill(sheet, c); k() }
            def fillAlpha(c, a, k) = { Surface.fillAlpha(sheet, c, a); k() }
            def rect(x, y, w, h, k) = { Surface.rect(sheet, x, y, w, h); k() }
            def ellipse(x, y, w, h, k) = { Surface.ellipse(sheet, x, y, w, h); k() }
            def text(str, x, y, k) = { Surface.text(sheet, str, x, y); k() }
            def textSize(px, k) = { Surface.textSize(sheet, px); k() }
            def dimensions(k) = k(Surface.size(sheet))
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

}
