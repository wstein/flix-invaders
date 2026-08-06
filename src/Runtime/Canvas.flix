///
/// Drawing, as an effect.
///
/// Sketch and game code calls these operations directly, so drawing code reads the way it
/// would in Processing. What makes that safe is that the effect has two interpretations:
/// `Canvas.runCollecting` turns the calls into data with no window, and the runtime's
/// handler paints them onto a real sketch. Rendering is therefore testable without a
/// display.
///
pub eff Canvas {

    /// Fills the whole canvas with `c`, erasing the previous frame.
    def clear(c: Color): Unit

    /// Sets the fill colour used by subsequent shapes and text.
    def fill(c: Color): Unit

    /// Draws a rectangle with its top-left corner at `(x, y)`.
    def rect(x: Float32, y: Float32, w: Float32, h: Float32): Unit

    /// Draws an ellipse centred on `(x, y)`.
    def ellipse(x: Float32, y: Float32, w: Float32, h: Float32): Unit

    /// Draws `s` with its baseline starting at `(x, y)`.
    def text(s: String, x: Float32, y: Float32): Unit

    /// Sets the text size in pixels.
    def textSize(px: Float32): Unit

    /// Returns the canvas size as `(width, height)`.
    def dimensions(): (Int32, Int32)

}

mod Canvas {

    ///
    /// Replays a list of draw commands through the `Canvas` effect.
    ///
    /// This is the bridge from a pure `render : world -> List[DrawCmd]` to whichever
    /// handler is currently installed.
    ///
    pub def paint(cmds: List[DrawCmd]): Unit \ Canvas =
        List.forEach(cmd -> match cmd {
            case DrawCmd.Clear(c)             => Canvas.clear(c)
            case DrawCmd.Fill(c)              => Canvas.fill(c)
            case DrawCmd.Rect(x, y, w, h)     => Canvas.rect(x, y, w, h)
            case DrawCmd.Ellipse(x, y, w, h)  => Canvas.ellipse(x, y, w, h)
            case DrawCmd.Text(s, x, y)        => Canvas.text(s, x, y)
            case DrawCmd.TextSize(px)         => Canvas.textSize(px)
        }, cmds)

    ///
    /// Runs `f`, recording every drawing operation instead of performing it.
    ///
    /// Pure: the accumulator lives in a region that is fully discharged here, so this needs
    /// no `IO` and opens no window. This is what the rendering tests use.
    ///
    pub def runCollecting(dims: (Int32, Int32), f: Unit -> a \ ef): (a, List[DrawCmd]) \ ef - Canvas =
        region rc {
            let acc: Ref[List[DrawCmd], rc] = Ref.fresh(rc, Nil);
            let emit = cmd -> Ref.put(cmd :: Ref.get(acc), acc);
            let result = run {
                f()
            } with handler Canvas {
                def clear(c, k)              = { emit(DrawCmd.Clear(c)); k() }
                def fill(c, k)               = { emit(DrawCmd.Fill(c)); k() }
                def rect(x, y, w, h, k)      = { emit(DrawCmd.Rect(x, y, w, h)); k() }
                def ellipse(x, y, w, h, k)   = { emit(DrawCmd.Ellipse(x, y, w, h)); k() }
                def text(s, x, y, k)         = { emit(DrawCmd.Text(s, x, y)); k() }
                def textSize(px, k)          = { emit(DrawCmd.TextSize(px)); k() }
                def dimensions(k)            = k(dims)
            };
            (result, List.reverse(Ref.get(acc)))
        }

    ///
    /// Runs `f` and returns only the draw commands it produced.
    ///
    pub def commands(dims: (Int32, Int32), f: Unit -> Unit \ ef): List[DrawCmd] \ ef - Canvas =
        snd(runCollecting(dims, f))

}
