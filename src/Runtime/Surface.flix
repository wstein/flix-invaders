///
/// A lightweight, Processing-shaped drawing surface built on Swing and Java2D.
///
/// This is the only module in `src/` that opens a window, and the vocabulary it offers is
/// deliberately the one a Processing sketch already knows: `background`, `fill`, `rect`
/// from its top-left corner, `ellipse` from its centre, `text` on its baseline. Keeping
/// those names and those conventions is what let the `Canvas` handler above it stay a
/// one-line-per-operation translation when Processing Core was dropped.
///
/// It is a *surface*, not a framework. It owns a window, a back buffer, the current fill
/// colour and font, and the two input devices -- and nothing else. There is no sketch
/// lifecycle, no `setup`/`draw` pair to subclass, and no global state: everything it knows
/// travels in the `Surface.Window` record it hands back. The frame loop lives one layer up,
/// in `Sketch`, where it can be read as ordinary functions.
///
/// Drawing goes to an offscreen `BufferedImage` of exactly the requested size, which
/// `present` then blits to the window. That fixes the geometry at one image pixel per
/// sketch pixel on every display, HiDPI or not -- the job Processing's `pixelDensity(1)`
/// used to do -- so a sketch that lines up on one machine lines up on all of them.
///
mod Surface {

    import java.awt.{Color => AwtColor}
    import java.awt.Component
    import java.awt.Dimension
    import java.awt.Font
    import java.awt.Graphics
    import java.awt.Graphics2D
    import java.awt.RenderingHints
    import java.awt.event.ActionEvent
    import java.awt.event.ActionListener
    import java.awt.event.KeyAdapter
    import java.awt.event.KeyEvent
    import java.awt.event.MouseEvent
    import java.awt.event.MouseMotionAdapter
    import java.awt.event.WindowAdapter
    import java.awt.event.WindowEvent
    import java.awt.geom.{Ellipse2D$Float => EllipseF}
    import java.awt.geom.{Rectangle2D$Float => RectangleF}
    import java.awt.image.BufferedImage
    import java.awt.image.ImageObserver
    import java.io.FileInputStream
    import java.lang.Exception
    import java.lang.Thread
    import java.util.concurrent.atomic.AtomicBoolean
    import javax.swing.JFrame
    import javax.swing.JPanel
    import javax.swing.Timer
    import javax.swing.WindowConstants

    ///
    /// An open window and everything drawing on it needs.
    ///
    /// `image` is the back buffer and `graphics` the one `Graphics2D` that writes to it,
    /// made once and kept: Java2D carries the current colour and font on the graphics
    /// object, which is exactly the "set it, then draw with it" model the `Canvas` effect
    /// is written in.
    ///
    /// `rectangle` and `ellipse` are two mutable shapes reused for every call rather than
    /// allocated per shape. They are what makes drawing sub-pixel: the formation marches at
    /// 0.65 pixels a tick, so rounding a rectangle to whole pixels would turn a glide into a
    /// stutter.
    ///
    /// `sized` remembers the font the last `textSize` derived, so a screen that sets the
    /// same size before every line of text derives the font once instead of twenty times.
    ///
    /// `keys` and `mouse` are written by the AWT listeners and read by the frame; `closing`
    /// is set when the window is shut, and is the one value the main thread reads while the
    /// event thread may still be writing it -- which is why it is an `AtomicBoolean` and not
    /// a `Ref`.
    ///
    pub type alias Window[rc: Region] = {
        frame = JFrame,
        panel = JPanel,
        image = BufferedImage,
        width = Int32,
        height = Int32,
        graphics = Graphics2D,
        base = Font,
        sized = Ref[(Float32, Font), rc],
        rectangle = RectangleF,
        ellipse = EllipseF,
        keys = Ref[Set[Int32], rc],
        mouse = Ref[(Int32, Int32), rc],
        closing = AtomicBoolean
    }

    ///
    /// The size a loaded font is first derived to.
    ///
    /// Anything works -- `textSize` re-derives it on every size change -- but it must not be
    /// left at the size of 1 that `Font.createFont` returns, or the first frame drawn before
    /// any `textSize` call is three pixels tall.
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
    /// The stream is closed on both paths. Closing it only after `createFont` returns leaks
    /// the descriptor whenever the file is present but unreadable as a font, which is the one
    /// case this function exists to survive.
    ///
    def loadFont(path: String): Option[Font] \ IO =
        try {
            let stream = new FileInputStream(path);
            let font = try {
                Some(Font.createFont(Font.TRUETYPE_FONT, stream).deriveFont(baseFontSize()))
            } catch {
                case _: Exception => None
            };
            stream.close();
            font
        } catch {
            case _: Exception => None
        }

    ///
    /// Opens a window of exactly `width` by `height` sketch pixels.
    ///
    /// The window is not resizable, because the back buffer is not: every coordinate the
    /// sketch draws at is an image pixel, and a window that could be dragged wider would
    /// have to answer what that means.
    ///
    /// A `fontPath` that is missing or unreadable costs you looks, not a crash -- the
    /// surface keeps the platform's default font and says so.
    ///
    pub def open(rc: Region[r],
                 title: String,
                 width: {width = Int32},
                 height: {height = Int32},
                 fontPath: Option[String]): Window[r] \ IO + r = {
        let w = width#width;
        let h = height#height;

        let image = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        let graphics = image.createGraphics();
        graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                                  RenderingHints.VALUE_ANTIALIAS_ON);
        graphics.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,
                                  RenderingHints.VALUE_TEXT_ANTIALIAS_ON);

        let loaded = match fontPath {
            case None => None
            case Some(path) => match loadFont(path) {
                case None =>
                    println("could not load font ${path}; using the default");
                    None
                case Some(font) => Some(font)
            }
        };
        let base = Option.getWithDefault(graphics.getFont(), loaded);
        graphics.setFont(base);

        let noObserver: ImageObserver = checked_cast(null);
        let panel = new JPanel {
            // `paint` rather than `paintComponent`: Swing hands both of them the graphics of
            // its own double buffer, and this one draws every pixel of the panel, so there is
            // no background left for the superclass to clear.
            def paint(_p: JPanel, g: Graphics): Unit \ IO =
                discard g.drawImage(image, 0, 0, noObserver)
        };
        panel.setPreferredSize(new Dimension(w, h));
        panel.setFocusable(true);
        // Otherwise Tab moves focus out of the game instead of arriving as a key.
        panel.setFocusTraversalKeysEnabled(false);

        let keys = Ref.fresh(rc, (Set.empty(): Set[Int32]));
        let mouse = Ref.fresh(rc, (0, 0));
        panel.addKeyListener(new KeyAdapter {
            def keyPressed(_a: KeyAdapter, e: KeyEvent): Unit \ IO + r =
                Ref.put(Set.insert(e.getKeyCode(), Ref.get(keys)), keys)
            def keyReleased(_a: KeyAdapter, e: KeyEvent): Unit \ IO + r =
                Ref.put(Set.remove(e.getKeyCode(), Ref.get(keys)), keys)
        });
        panel.addMouseMotionListener(new MouseMotionAdapter {
            def mouseMoved(_a: MouseMotionAdapter, e: MouseEvent): Unit \ IO + r =
                Ref.put((e.getX(), e.getY()), mouse)
            def mouseDragged(_a: MouseMotionAdapter, e: MouseEvent): Unit \ IO + r =
                Ref.put((e.getX(), e.getY()), mouse)
        });

        let closing = new AtomicBoolean(false);
        let frame = new JFrame(title);
        // The window must not take the JVM down with it: the score table is written after
        // the loop returns, so closing has to mean "stop" and not "exit".
        frame.setDefaultCloseOperation(WindowConstants.DO_NOTHING_ON_CLOSE);
        frame.addWindowListener(new WindowAdapter {
            def windowClosing(_a: WindowAdapter, _e: WindowEvent): Unit \ IO =
                closing.set(true)
        });
        frame.setResizable(false);
        discard frame.add(panel);
        frame.pack();
        let noParent: Component = checked_cast(null);
        frame.setLocationRelativeTo(noParent);
        frame.setVisible(true);
        discard panel.requestFocusInWindow();

        { frame = frame, panel = panel, image = image, width = w, height = h,
          graphics = graphics,
          base = base, sized = Ref.fresh(rc, (baseFontSize(), base)),
          rectangle = new RectangleF(), ellipse = new EllipseF(),
          keys = keys, mouse = mouse, closing = closing }
    }

    ///
    /// The delay between frames, in whole milliseconds, for a target rate of `hz`.
    ///
    /// Swing's timer counts in whole milliseconds, so 60 Hz asks for 16 and gets about 62
    /// frames a second rather than exactly 60. That is deliberately not corrected for: how
    /// fast the *simulation* runs is the accumulator's business and not the timer's, so a
    /// frame arriving early simply owes fewer ticks and the game plays at the same speed
    /// either way. Truncating rather than rounding up is the safe direction of the two --
    /// 17ms would deliver 58 frames a second, and every frame that arrives late is one the
    /// accumulator then has to catch up on.
    ///
    /// Never zero, whatever `hz` is asked for: a timer with no delay saturates the event
    /// thread and the window stops answering. A rate of nought or less asks for a frame a
    /// second, which is slow enough to be recognised as wrong and calm enough to survive.
    ///
    pub def delayFor(hz: Int32): Int32 =
        if (hz <= 0) 1000 else Int32.max(1, 1000 / hz)

    ///
    /// Calls `frame` at about `hz` times a second until the window closes.
    ///
    /// The callback runs on AWT's event dispatch thread, which is also the thread the key
    /// and mouse listeners run on and the only thread Swing may be touched from. One thread
    /// owns input, simulation and drawing, so none of them needs a lock.
    ///
    /// This call blocks the thread it is made on, which is therefore not the event thread:
    /// it parks until the window reports that it has closed, and only then stops the timer.
    /// A frame that arrives after the close is dropped rather than run, so the last world
    /// the caller reads is the one the last drawn frame produced.
    ///
    /// The region effect `r` does not appear in the result: the callback is compiled into a
    /// fixed JVM method on an anonymous `ActionListener`, so what it does to the caller's
    /// region is invisible from out here. That is the same boundary limit that keeps
    /// `Sketch.start` from being effect-polymorphic.
    ///
    pub def loop(s: Window[r], hz: Int32, frame: Unit -> Unit \ IO + r): Unit \ IO = {
        let timer = new Timer(delayFor(hz), new ActionListener {
            def actionPerformed(_a: ActionListener, _e: ActionEvent): Unit \ IO + r =
                if (s#closing.get()) () else frame()
        });
        // A frame that overruns must not queue a second one behind it; dropping the
        // overlap is what keeps a stall from compounding into a stall.
        timer.setCoalesce(true);
        timer.start();
        park(s);
        timer.stop()
    }

    ///
    /// Parks the calling thread until the window reports that it has closed.
    ///
    /// A recursion because there is no sequence to traverse: it waits on a flag another
    /// thread will set, and how many times it looks is not known in advance.
    ///
    /// `AtomicBoolean` rather than a `Ref`: this is the one value written on the event
    /// thread and read on this one, and reading it is what publishes everything the frames
    /// wrote before it was set.
    ///
    def park(s: Window[r]): Unit \ IO =
        if (s#closing.get()) ()
        else { Thread.sleep(pollMillis()); park(s) }

    /// How long the parked thread sleeps between looks at the close flag.
    def pollMillis(): Int64 = 20i64

    ///
    /// Asks the loop to stop, as though the window had been closed.
    ///
    /// This is how a bounded run ends: `FLIX_SKETCH_MAX_FRAMES` gives a sketch a frame
    /// budget so it terminates on a machine nobody is sitting in front of.
    ///
    pub def requestClose(s: Window[r]): Unit \ IO =
        s#closing.set(true)

    ///
    /// Closes the window and releases the back buffer.
    ///
    pub def close(s: Window[r]): Unit \ IO = {
        s#graphics.dispose();
        s#frame.dispose()
    }

    ///
    /// The canvas size, in sketch pixels.
    ///
    /// Held rather than asked of the back buffer, so that the frame loop can read it without
    /// reaching into the toolkit: the window cannot be resized, so it never changes.
    ///
    pub def size(s: Window[r]): (Int32, Int32) =
        (s#width, s#height)

    ///
    /// The AWT key codes currently held down.
    ///
    /// Codes rather than named keys: this layer knows about a keyboard and not about a
    /// game, and `Key.fromCode` one layer up is where a number becomes a name.
    ///
    pub def keysHeld(s: Window[r]): Set[Int32] \ r =
        Ref.get(s#keys)

    ///
    /// Where the pointer was last seen, as `(x, y)`.
    ///
    pub def mouse(s: Window[r]): (Int32, Int32) \ r =
        Ref.get(s#mouse)

    ///
    /// Shows everything drawn since the last call.
    ///
    /// `paintImmediately` and not `repaint`: the frame is finished now, and a queued repaint
    /// would land somewhere inside the next one -- which shows up as tearing and makes the
    /// cost of drawing impossible to measure.
    ///
    pub def present(s: Window[r]): Unit \ IO = {
        let (w, h) = size(s);
        s#panel.paintImmediately(0, 0, w, h)
    }

    // -- drawing ----------------------------------------------------------------------------

    /// The AWT colour for one of ours.
    def awt(c: Color): AwtColor \ IO =
        new AwtColor(Color.redOf(c), Color.greenOf(c), Color.blueOf(c))

    ///
    /// Fills the whole canvas with `c`, erasing the previous frame.
    ///
    /// Leaves `c` as the fill colour, as Processing's `background` does.
    ///
    pub def background(s: Window[r], c: Color): Unit \ IO = {
        let (w, h) = size(s);
        fill(s, c);
        s#graphics.fillRect(0, 0, w, h)
    }

    ///
    /// Sets the colour subsequent shapes and text are drawn in.
    ///
    pub def fill(s: Window[r], c: Color): Unit \ IO =
        s#graphics.setColor(awt(c))

    ///
    /// Sets a translucent fill, with `alpha` from 0 (invisible) to 255 (opaque).
    ///
    pub def fillAlpha(s: Window[r], c: Color, alpha: Int32): Unit \ IO =
        s#graphics.setColor(new AwtColor(Color.redOf(c), Color.greenOf(c), Color.blueOf(c),
                                         Int32.max(0, Int32.min(255, alpha))))

    ///
    /// Draws a rectangle with its top-left corner at `(x, y)`.
    ///
    pub def rect(s: Window[r], x: Float32, y: Float32, w: Float32, h: Float32): Unit \ IO = {
        s#rectangle.setRect(x, y, w, h);
        s#graphics.fill(s#rectangle)
    }

    ///
    /// Draws an ellipse centred on `(x, y)`.
    ///
    pub def ellipse(s: Window[r], x: Float32, y: Float32, w: Float32, h: Float32)
        : Unit \ IO = {
        s#ellipse.setFrame(x - w / 2.0f32, y - h / 2.0f32, w, h);
        s#graphics.fill(s#ellipse)
    }

    ///
    /// Draws `s` with its baseline starting at `(x, y)`.
    ///
    pub def text(s: Window[r], str: String, x: Float32, y: Float32): Unit \ IO =
        s#graphics.drawString(str, x, y)

    ///
    /// Sets the text size in pixels.
    ///
    /// Deriving a font allocates, and a screen that sets the same size before each of its
    /// twenty labels would pay for it twenty times, so the last one derived is kept.
    ///
    pub def textSize(s: Window[r], px: Float32): Unit \ IO + r = {
        let (was, font) = Ref.get(s#sized);
        if (was == px) s#graphics.setFont(font)
        else {
            let derived = s#base.deriveFont(px);
            Ref.put((px, derived), s#sized);
            s#graphics.setFont(derived)
        }
    }

}
