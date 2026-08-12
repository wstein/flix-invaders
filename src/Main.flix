///
/// Space Invaders.
///
/// Notice how little there is here. The runtime owns the window and the frame loop, `Game`
/// owns the rules, `View` owns the drawing, and `Session` owns the cabinet around them --
/// this file only introduces them. If it ever needs to grow much beyond this, something has
/// leaked across the boundary.
///
/// It is also the only place that touches a file. `Sketch.start` takes a pure `init` and
/// returns the state the window closed on, so the table is read before the window opens and
/// written after it closes, and nothing in between knows a filesystem exists. That is what
/// keeps `Session.step` testable without a disk.
///
/// Run it:   ./flixw run
///
def main(): Unit \ { Fs.FileRead, Fs.FileWrite, Sys.Env, Sys.Exit, IO } = {
    let saved = readScores();
    let tuning = readTuning();
    let closed = runSession(saved, tuning);
    // Only when somebody earned something. A session that changed nothing should not create
    // a config directory, and should not rewrite a file it merely read.
    if (Scores.render(closed#scores) != Scores.render(saved)) writeScores(closed#scores) else ();

    // And now stop, having finished.
    //
    // `Sketch` overrides `exitActual` so that closing the window returns control here instead
    // of Processing calling `System.exit(0)` mid-frame -- which is what makes saving the
    // scores possible at all. The cost is that nothing exits the JVM afterwards: AWT's event
    // thread is not a daemon, so returning from `main` leaves it running and the process
    // hangs. `./flixw run` hides this because its launcher owns the JVM; a plain
    // `java -jar` does not, and the released game would never terminate.
    //
    // So the exit is explicit, and it is here rather than in `Sketch` on purpose: it belongs
    // after the last thing that must happen, not at the end of the window's life.
    Sys.Exit.exit(0)
}

///
/// Opens the window and returns the session it closed on.
///
/// Separate from `main` so that the one function reaching a disk is not also the one building
/// a window, and `main` reads as what it is: read the files, play the game, write the files.
/// The table and the tuning arrive as arguments rather than being read here, which is what
/// keeps `Sketch.start`'s `init` a pure function of the seed.
///
def runSession(saved: List[Entry], tuning: Tuning): Session \ IO = {
    let limit = Sketch.maxFramesFromEnv();
    Sketch.start(
        { title = "Flix Invaders",
          width = 640,
          height = 480,
          seed = Sketch.freshSeed(),
          hz = 60,
          maxFrames = limit,
          // Relative to the working directory, which ./flixw deliberately does not
          // change -- run the game from the project root.
          fontPath = Some("assets/PressStart2P-Regular.ttf") },
        seed -> Session.withTuning(seed, saved, tuning),
        Session.step,
        Screens.render)
}

///
/// The stored high scores, or none at all if they cannot be read.
///
/// A missing file is the ordinary first run and is silent. Anything else is reported and
/// then tolerated: not being able to read a score table is no reason to refuse to play.
///
def readScores(): List[Entry] \ { Fs.FileRead, Sys.Env, IO } =
    match Scores.location() {
        case None => Nil
        case Some(at) => match Scores.load(at) {
            case Ok(entries) => entries
            case Err(why) => {
                println("could not read ${at#file}: ${why}");
                Nil
            }
        }
    }

///
/// The demo player's numbers, or the shipped defaults if there is no config.
///
/// The attract screen is the only thing this affects, so a config that cannot be read costs
/// you a slightly different demo and nothing else. `bin/bench --recalc` is what writes it.
///
def readTuning(): Tuning \ { Fs.FileRead, Sys.Env, IO } =
    match Tuning.path() {
        case None => Demo.defaults()
        case Some(file) => match Tuning.load(file) {
            case Ok(t) => t
            case Err(why) => {
                println("could not read ${file}: ${why}");
                Demo.defaults()
            }
        }
    }

///
/// Stores the high scores, reporting rather than throwing if it cannot.
///
/// Losing a table to a full disk should not be the last thing the player sees.
///
def writeScores(scores: List[Entry]): Unit \ { Fs.FileWrite, Sys.Env, IO } =
    match Scores.location() {
        case None => ()
        case Some(at) => match Scores.save(at, scores) {
            case Ok(_) => ()
            case Err(why) => println("could not write ${at#file}: ${why}")
        }
    }
