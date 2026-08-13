///
/// Drawing, as an effect.
///
/// Sketch and game code calls these operations directly, so drawing code reads the way it
/// would in Processing. What makes that safe is that the effect has two interpretations:
/// `Canvas.runWithCollector` turns the calls into data with no window, and the runtime's
/// handler paints them onto a real sketch. Rendering is therefore testable without a
/// display.
///
pub eff Canvas {

    /// Fills the whole canvas with `c`, erasing the previous frame.
    def clear(c: Color): Unit

    /// Sets the fill colour used by subsequent shapes and text.
    def fill(c: Color): Unit

    ///
    /// Sets a translucent fill, with `alpha` from 0 (invisible) to 255 (opaque).
    ///
    /// Exists so an overlay can dim what is behind it instead of hiding it -- the attract
    /// screen draws its title over a live game, and a solid band would cut the formation in
    /// half.
    ///
    def fillAlpha(c: Color, alpha: Int32): Unit

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
    pub def paint(cmds: List[DrawCmd]): Unit \ Canvas = {
        let processCmd = cmd -> match cmd {
            case DrawCmd.Clear(c)             => Canvas.clear(c)
            case DrawCmd.Fill(c)              => Canvas.fill(c)
            case DrawCmd.FillAlpha(c, a)      => Canvas.fillAlpha(c, a)
            case DrawCmd.Rect(x, y, w, h)     => Canvas.rect(x, y, w, h)
            case DrawCmd.Ellipse(x, y, w, h)  => Canvas.ellipse(x, y, w, h)
            case DrawCmd.Text(s, x, y)        => Canvas.text(s, x, y)
            case DrawCmd.TextSize(px)         => Canvas.textSize(px)
        };
        List.forEach(processCmd, cmds)
    }

    ///
    /// Interprets `Canvas` by recording every drawing operation instead of performing it.
    ///
    /// Pure: the accumulator lives in a region that is fully discharged here, so this needs
    /// no `IO` and opens no window. This is what the rendering tests use.
    ///
    /// The `handle`/`runWith` pair follows the stdlib's companion-module convention -- see
    /// `Logger.flix`, which offers seven interpretations of one effect this way. Adding an
    /// eighth interpretation of `Canvas` means adding a function here, not editing the
    /// runtime.
    ///
    type alias CmdCollector[a: Type, b: Type, ef: Eff] = a -> (b, List[DrawCmd]) \ ef - Canvas

    pub def handleWithCollector(dims: (Int32, Int32),
                                f: a -> b \ ef)
        : CmdCollector[a, b, ef] =
        input -> region rc {
            let acc: Ref[List[DrawCmd], rc] = Ref.fresh(rc, Nil);
            let emit = cmd -> Ref.put(cmd :: Ref.get(acc), acc);
            let result = run {
                f(input)
            } with handler Canvas {
                def clear(c, k)              = { emit(DrawCmd.Clear(c)); k() }
                def fill(c, k)               = { emit(DrawCmd.Fill(c)); k() }
                def fillAlpha(c, a, k)       = { emit(DrawCmd.FillAlpha(c, a)); k() }
                def rect(x, y, w, h, k)      = { emit(DrawCmd.Rect(x, y, w, h)); k() }
                def ellipse(x, y, w, h, k)   = { emit(DrawCmd.Ellipse(x, y, w, h)); k() }
                def text(s, x, y, k)         = { emit(DrawCmd.Text(s, x, y)); k() }
                def textSize(px, k)          = { emit(DrawCmd.TextSize(px)); k() }
                def dimensions(k)            = k(dims)
            };
            let cmds = List.reverse(Ref.get(acc));
            (result, cmds)
        }

    ///
    /// Runs `f`, returning its result together with the draw commands it produced.
    ///
    pub def runWithCollector(dims: (Int32, Int32), f: Unit -> a \ ef
    ): (a, List[DrawCmd]) \ ef - Canvas =
        handleWithCollector(dims, f)()

    ///
    /// Interprets `Canvas` by discarding every drawing operation.
    ///
    /// Deliberately *not* installed as a `@DefaultHandler`: with a default in place, a test
    /// that forgot to choose an interpretation would compile and silently assert on a frame
    /// that was never drawn. Leaving `Canvas` without one keeps that a type error.
    ///
    pub def runWithNoOp(dims: (Int32, Int32), f: Unit -> a \ ef)
        : a \ ef - Canvas =
        run {
            f()
        } with handler Canvas {
            def clear(_c, k) = k()
            def fill(_c, k) = k()
            def fillAlpha(_c, _a, k) = k()
            def rect(_x, _y, _w, _h, k) = k()
            def ellipse(_x, _y, _w, _h, k) = k()
            def text(_s, _x, _y, k) = k()
            def textSize(_px, k) = k()
            def dimensions(k) = k(dims)
        }

    ///
    /// Runs `f` and returns only the draw commands it produced.
    ///
    pub def commands(dims: (Int32, Int32), f: Unit -> Unit \ ef)
        : List[DrawCmd] \ ef - Canvas =
        snd(runWithCollector(dims, f))

}
