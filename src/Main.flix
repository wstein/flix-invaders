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
/// Run it:   bin/flix run
///
def main(): Unit \ { Fs.FileRead, Fs.FileWrite, Sys.Env, IO } = {
    let limit = Sketch.maxFramesFromEnv();
    let saved = readScores();
    let closed = Sketch.start(
        { title = "Flix Invaders",
          width = 640,
          height = 480,
          seed = 2026i64,
          hz = 60,
          maxFrames = limit,
          // Relative to the working directory; bin/flix cds to the project root first.
          fontPath = Some("assets/PressStart2P-Regular.ttf") },
        seed -> Session.withScores(seed, saved),
        Session.step,
        Screens.render);
    // Only when somebody earned something. A session that changed nothing should not create
    // a config directory, and should not rewrite a file it merely read.
    if (Scores.render(closed#scores) != Scores.render(saved)) writeScores(closed#scores) else ()
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
