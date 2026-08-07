///
/// Space Invaders.
///
/// Notice how little there is here. The runtime owns the window and the frame loop, `Game`
/// owns the rules, and `View` owns the drawing -- this file only introduces them. If it ever
/// needs to grow much beyond this, something has leaked across the boundary.
///
/// Run it:   bin/flix run
///
def main(): Unit \ IO = {
    let limit = Sketch.maxFramesFromEnv();
    Sketch.start(
        { title = "Flix Invaders",
          width = 640,
          height = 480,
          seed = 2026i64,
          hz = 60,
          maxFrames = limit,
          // Relative to the working directory; bin/flix cds to the project root first.
          fontPath = Some("assets/PressStart2P-Regular.ttf") },
        Game.initial,
        Game.step,
        View.render)
}
