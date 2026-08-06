///
/// M0 spike: Flix drives a Processing window directly, with no Java in this repository.
///
/// Run it:   bin/flix run --entrypoint Spike.main
///
/// Arrow keys move the box, space toggles its brightness, ESC or the window's close
/// button quits. See `docs/spike-result.md` for what this proved and
/// `docs/SMOKE-CHECKLIST.md` for the manual test steps.
///
/// Throwaway: superseded by `Runtime/Sketch.flix` in M1.
///
mod Spike {

    import processing.core.PApplet
    import java.lang.Thread

    ///
    /// The drawing vocabulary. Note this effect knows nothing about Processing -- the
    /// handler in `draw` is the only place the two meet.
    ///
    eff Canvas {
        def clear(grey: Float32): Unit
        def shade(grey: Float32): Unit
        def box(x: Float32, y: Float32, w: Float32, h: Float32): Unit
        def label(s: String, x: Float32, y: Float32): Unit
    }

    /// What the sketch knows. Plain immutable data.
    type alias Box = { x = Float32, y = Float32, bright = Bool, frames = Int32 }

    def width(): Int32 = 480
    def height(): Int32 = 320
    def boxSize(): Float32 = 40.0f32
    def speed(): Float32 = 3.0f32

    // Arrow key codes, as reported by PApplet.keyCode (java.awt.event.KeyEvent.VK_*).
    def kLeft(): Int32 = 37
    def kUp(): Int32 = 38
    def kRight(): Int32 = 39
    def kDown(): Int32 = 40
    def kSpace(): Int32 = 32

    def clamp(lo: Float32, hi: Float32, v: Float32): Float32 =
        if (v < lo) lo else if (v > hi) hi else v

    /// Pure: given the held keys, where does the box go next?
    def advance(b: Box, held: Set[Int32]): Box = {
        let dx = (if (Set.memberOf(kLeft(), held)) -speed() else 0.0f32)
               + (if (Set.memberOf(kRight(), held)) speed() else 0.0f32);
        let dy = (if (Set.memberOf(kUp(), held)) -speed() else 0.0f32)
               + (if (Set.memberOf(kDown(), held)) speed() else 0.0f32);
        let maxX = Int32.toFloat32(width()) - boxSize();
        let maxY = Int32.toFloat32(height()) - boxSize();
        { x = clamp(0.0f32, maxX, b#x + dx),
          y = clamp(0.0f32, maxY, b#y + dy),
          bright = b#bright,
          frames = b#frames + 1 }
    }

    /// Pure: what should the screen look like?
    def scene(b: Box, held: Set[Int32]): Unit \ Canvas = {
        Canvas.clear(30.0f32);
        Canvas.shade(if (b#bright) 255.0f32 else 120.0f32);
        Canvas.box(b#x, b#y, boxSize(), boxSize());
        Canvas.shade(180.0f32);
        Canvas.label("arrows move, space toggles, ESC quits", 12.0f32, 24.0f32);
        Canvas.label("frame " + Int32.toString(b#frames)
                     + "   keys held: " + Int32.toString(Set.size(held)), 12.0f32, 44.0f32)
    }

    def newSketch(box: Ref[Box, r], held: Ref[Set[Int32], r], done: Ref[Bool, r]): PApplet \ IO =
        new PApplet {

            def settings(app: PApplet): Unit \ IO = {
                app.size(width(), height());
                // Processing defaults to pixelDensity(2) on HiDPI displays, which would make
                // geometry display-dependent. Pin it so every machine renders identically.
                // size/pixelDensity/fullScreen/smooth are legal ONLY in settings() outside
                // the PDE -- calling pixelDensity from setup() throws IllegalStateException.
                app.pixelDensity(1)
            }

            def setup(app: PApplet): Unit \ IO = {
                app.frameRate(60.0f32);
                println("window " + Int32.toString(app.width) + "x" + Int32.toString(app.height))
            }

            def draw(app: PApplet): Unit \ IO + r = {
                let h = Ref.get(held);
                let b = advance(Ref.get(box), h);
                Ref.put(b, box);

                // The handler lives INSIDE draw on purpose: handlers are stack-scoped, and
                // draw runs on Processing's Animation Thread, so one installed around
                // runSketch on the main thread would not be visible here.
                run {
                    scene(b, h)
                } with handler Canvas {
                    def clear(grey, k)     = { app.background(grey); k() }
                    def shade(grey, k)     = { app.fill(grey); k() }
                    def box(x, y, w, hh, k) = { app.rect(x, y, w, hh); k() }
                    def label(s, x, y, k)  = { app.text(s, x, y); k() }
                }
            }

            def keyPressed(app: PApplet): Unit \ IO + r = {
                let code = app.keyCode;
                Ref.put(Set.insert(code, Ref.get(held)), held);
                if (code == kSpace()) {
                    let b = Ref.get(box);
                    Ref.put({bright = not b#bright | b}, box)
                } else ();
                println("down " + Int32.toString(code))
            }

            def keyReleased(app: PApplet): Unit \ IO + r = {
                let code = app.keyCode;
                Ref.put(Set.remove(code, Ref.get(held)), held);
                println("up   " + Int32.toString(code))
            }

            // exitActual is PApplet's only System.exit(0), and is documented as the
            // embedding hook. Overriding it hands control back to main instead of killing
            // the JVM mid-frame. It can fire more than once, so this must be idempotent.
            def exitActual(_app: PApplet): Unit \ r =
                Ref.put(true, done)
        }

    /// Park the main thread until the sketch reports it has exited.
    def waitUntilDone(done: Ref[Bool, r]): Unit \ IO + r =
        if (Ref.get(done)) ()
        else { Thread.sleep(50i64); waitUntilDone(done) }

    pub def main(): Unit \ IO = region rc {
        let box = Ref.fresh(rc, {x = 220.0f32, y = 140.0f32, bright = true, frames = 0});
        let held = Ref.fresh(rc, Set.empty());
        let done = Ref.fresh(rc, false);

        let sketch = newSketch(box, held, done);

        // Processing resolves its renderer (processing.awt.PGraphicsJava2D) and its macOS
        // helper (processing.core.ThinkDifferent) via
        //     Thread.currentThread().getContextClassLoader().loadClass(...)
        // but Flix loads jar dependencies through its own ExternalJarLoader, whose parent is
        // the *platform* loader. Without this line Processing cannot find its own classes and
        // dies with "The processing.awt.PGraphicsJava2D renderer is not in the class path."
        Thread.currentThread().setContextClassLoader(sketch.getClass().getClassLoader());

        PApplet.runSketch(Array#{"spike"} @ rc, sketch);

        // runSketch returns immediately, so the region must be kept alive by hand:
        // draw is still touching these Refs on the Animation Thread.
        waitUntilDone(done);
        println("closed cleanly after " + Int32.toString(Ref.get(box)#frames) + " frames")
    }
}
