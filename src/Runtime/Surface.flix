///
/// A lightweight, Processing-shaped drawing surface built on Swing and Java2D.
///
/// This is the only module in `src/` that opens a window, and the vocabulary it offers is
/// deliberately the one a Processing sketch already knows: `background`, `fill`, `rect`
/// from its top-left corner, `ellipse` from its centre, `text` on its baseline. Keeping
/// those names and those conventions is what let the `Canvas` handler above it stay a
/// one-line-per-operation translation when Processing Core was dropped.
///
/// It comes in two halves, and the seam between them is the point. A `Sheet` is somewhere
/// to draw -- a back buffer, the graphics that writes to it, and the current colour and
/// font -- and knows nothing about a display, so `offscreen` hands one out on a machine
/// with no screen at all and `test/TestSurface.flix` checks the rasteriser against real
/// pixels. A `Window` is a sheet with a frame around it, a keyboard, and a frame loop.
///
/// It is a *surface*, not a framework: no sketch lifecycle, no `setup`/`draw` pair to
/// subclass, and no global state -- everything it knows travels in the records it hands
/// back. The frame loop lives one layer up, in `Sketch`, where it can be read as ordinary
/// functions. The one policy it does impose is that Escape closes the window, which is what
/// a sketch of this shape has always done.
///
/// Drawing goes to an offscreen `BufferedImage` of exactly the requested size, which
/// `present` then blits to the window through a `BufferStrategy`. That fixes the geometry
/// at one image pixel per sketch pixel on every display, HiDPI or not -- the job
/// Processing's `pixelDensity(1)` used to do -- so a sketch that lines up on one machine
/// lines up on all of them.
///
mod Surface {

    import java.awt.{Canvas => AwtCanvas}
    import java.awt.{Color => AwtColor}
    import java.awt.Component
    import java.awt.Dimension
    import java.awt.Font
    import java.awt.Graphics2D
    import java.awt.RenderingHints
    import java.awt.Toolkit
    import java.awt.event.ActionEvent
    import java.awt.event.ActionListener
    import java.awt.event.FocusAdapter
    import java.awt.event.FocusEvent
    import java.awt.event.KeyAdapter
    import java.awt.event.KeyEvent
    import java.awt.event.WindowAdapter
    import java.awt.event.WindowEvent
    import java.awt.geom.{Ellipse2D$Float => EllipseF}
    import java.awt.geom.{Rectangle2D$Float => RectangleF}
    import java.awt.image.BufferStrategy
    import java.awt.image.BufferedImage
    import java.awt.image.ImageObserver
    import java.io.FileInputStream
    import java.lang.Exception
    import java.lang.System
    import java.lang.Thread
    import java.util.concurrent.atomic.AtomicBoolean
    import java.util.concurrent.atomic.AtomicLong

    import javax.swing.JFrame
    import javax.swing.Timer
    import javax.swing.WindowConstants

    // -- somewhere to draw --------------------------------------------------------------

    ///
    /// A drawing surface, with no display behind it.
    ///
    /// `image` is the buffer and `graphics` the one `Graphics2D` that writes to it, made
    /// once and kept: Java2D carries the current colour and font on the graphics object,
    /// which is exactly the "set it, then draw with it" model the `Canvas` effect is
    /// written in.
    ///
    /// `rectangle` and `ellipse` are two mutable shapes reused for every call rather than
    /// allocated per shape. They are what makes drawing sub-pixel: the formation marches at
    /// 0.65 pixels a tick, so rounding a rectangle to whole pixels would turn a glide into a
    /// stutter.
    ///
    /// `sized` remembers the font the last `textSize` derived, so a screen that sets the
    /// same size before every line of text derives the font once instead of twenty times.
    /// Its `Float32` is the size of the `Font` beside it, and seeding it with anything else
    /// would make `textSize` skip a derivation it owed.
    ///
    pub type alias Sheet[rc: Region] = {
        image = BufferedImage,
        width = Int32,
        height = Int32,
        graphics = Graphics2D,
        base = Font,
        sized = Ref[(Float32, Font), rc],
        rectangle = RectangleF,
        ellipse = EllipseF
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
    /// A sheet of exactly `width` by `height` pixels, with no window anywhere near it.
    ///
    /// This is what `open` builds its back buffer with, and what the rasteriser's tests draw
    /// on: nothing here needs a display, a toolkit peer, or a graphics device, so it runs on
    /// a CI machine with no screen.
    ///
    /// A `fontPath` that is missing or unreadable costs you looks, not a crash -- the sheet
    /// keeps the platform's default font and says so.
    ///
    pub def offscreen(rc: Region[r],
                      width: {width = Int32},
                      height: {height = Int32},
                      fontPath: Option[String]): Sheet[r] \ IO + r = {
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
        // Derived even when it is the platform's own: `sized` records this size, and a
        // default font left at its natural twelve points would make that record a lie -- the
        // first `textSize(16.0)` would find the cache already there and draw at twelve.
        let base = Option.getWithDefault(graphics.getFont().deriveFont(baseFontSize()), loaded);
        graphics.setFont(base);

        { image = image, width = w, height = h, graphics = graphics,
          base = base, sized = Ref.fresh(rc, (baseFontSize(), base)),
          rectangle = new RectangleF(), ellipse = new EllipseF() }
    }

    ///
    /// Releases the graphics a sheet was drawing through.
    ///
    pub def release(sheet: Sheet[r]): Unit \ IO =
        sheet#graphics.dispose()

    ///
    /// The sheet's size, in sketch pixels.
    ///
    /// Held rather than asked of the buffer, so the frame loop can read it without reaching
    /// into the toolkit: a sheet cannot be resized, so it never changes.
    ///
    pub def size(sheet: Sheet[r]): (Int32, Int32) =
        (sheet#width, sheet#height)

    ///
    /// The colour of one pixel, as it currently stands.
    ///
    /// The read-back that makes the rasteriser testable: with `offscreen` there is no window
    /// to look at, so this is how a test asks what was actually drawn rather than what was
    /// asked for. The buffer has no alpha channel, so what comes back is already composited.
    ///
    pub def pixelAt(sheet: Sheet[r], x: Int32, y: Int32): Color \ IO = {
        let argb = sheet#image.getRGB(x, y);
        let channel = shift -> Int32.bitwiseAnd(Int32.rightShift(argb, shift), 255);
        Color.Rgb(channel(16), channel(8), channel(0))
    }

    // -- drawing --------------------------------------------------------------------------

    /// The AWT colour for one of ours.
    def awt(c: Color): AwtColor \ IO =
        new AwtColor(Color.redOf(c), Color.greenOf(c), Color.blueOf(c))

    ///
    /// Fills the whole sheet with `c`, erasing what was there.
    ///
    /// Leaves `c` as the fill colour, as Processing's `background` does.
    ///
    pub def background(sheet: Sheet[r], c: Color): Unit \ IO = {
        let (w, h) = size(sheet);
        fill(sheet, c);
        sheet#graphics.fillRect(0, 0, w, h)
    }

    ///
    /// Sets the colour subsequent shapes and text are drawn in.
    ///
    pub def fill(sheet: Sheet[r], c: Color): Unit \ IO =
        sheet#graphics.setColor(awt(c))

    ///
    /// Sets a translucent fill, with `alpha` from 0 (invisible) to 255 (opaque).
    ///
    pub def fillAlpha(sheet: Sheet[r], c: Color, alpha: Int32): Unit \ IO =
        sheet#graphics.setColor(new AwtColor(Color.redOf(c), Color.greenOf(c),
                                             Color.blueOf(c),
                                             Int32.max(0, Int32.min(255, alpha))))

    ///
    /// Draws a rectangle with its top-left corner at `(x, y)`.
    ///
    pub def rect(sheet: Sheet[r], x: Float32, y: Float32, w: Float32, h: Float32)
        : Unit \ IO = {
        sheet#rectangle.setRect(x, y, w, h);
        sheet#graphics.fill(sheet#rectangle)
    }

    ///
    /// Draws an ellipse centred on `(x, y)`.
    ///
    pub def ellipse(sheet: Sheet[r], x: Float32, y: Float32, w: Float32, h: Float32)
        : Unit \ IO = {
        sheet#ellipse.setFrame(x - w / 2.0f32, y - h / 2.0f32, w, h);
        sheet#graphics.fill(sheet#ellipse)
    }

    ///
    /// Draws `str` with its baseline starting at `(x, y)`.
    ///
    pub def text(sheet: Sheet[r], str: String, x: Float32, y: Float32): Unit \ IO =
        sheet#graphics.drawString(str, x, y)

    ///
    /// Sets the text size in pixels.
    ///
    /// Deriving a font allocates, and a screen that sets the same size before each of its
    /// twenty labels would pay for it twenty times, so the last one derived is kept.
    ///
    pub def textSize(sheet: Sheet[r], px: Float32): Unit \ IO + r = {
        let (was, font) = Ref.get(sheet#sized);
        if (was == px) sheet#graphics.setFont(font)
        else {
            let derived = sheet#base.deriveFont(px);
            Ref.put((px, derived), sheet#sized);
            sheet#graphics.setFont(derived)
        }
    }

    // -- a window around it -----------------------------------------------------------------

    ///
    /// An open window and everything showing a sheet in it needs.
    ///
    /// `keys` is written by the AWT listeners and read by the frame -- both on the event
    /// dispatch thread, so it needs no locking. `closing` is set when the window is shut,
    /// and is the one value the parked thread reads while the event thread may still be
    /// writing it, which is why it is an `AtomicBoolean` and not a `Ref`.
    ///
    pub type alias Window[rc: Region] = {
        sheet = Sheet[rc],
        frame = JFrame,
        canvas = AwtCanvas,
        strategy = BufferStrategy,
        keys = Ref[Set[Int32], rc],
        closing = AtomicBoolean
    }

    ///
    /// Opens a window showing a sheet of exactly `width` by `height` sketch pixels.
    ///
    /// The window is not resizable, because the sheet is not: every coordinate a sketch
    /// draws at is an image pixel, and a window that could be dragged wider would have to
    /// answer what that means.
    ///
    pub def open(rc: Region[r],
                 title: String,
                 width: {width = Int32},
                 height: {height = Int32},
                 fontPath: Option[String]): Window[r] \ IO + r = {
        let sheet = offscreen(rc, width, height, fontPath);
        let closing = new AtomicBoolean(false);
        let keys = Ref.fresh(rc, (Set.empty(): Set[Int32]));
        let canvas = openCanvas(sheet, keys, closing);
        let frame = openFrame(title, canvas, closing);

        // Only once the window is showing: a buffer strategy needs a displayable component.
        canvas.createBufferStrategy(buffers());
        { sheet = sheet, frame = frame, canvas = canvas,
          strategy = canvas.getBufferStrategy(), keys = keys, closing = closing }
    }

    /// Two buffers, because the loop always redraws the whole frame and so has no use for
    /// what a third would preserve.
    def buffers(): Int32 = 2

    ///
    /// The component the sheet is shown in, wired to the keyboard.
    ///
    /// A heavyweight `java.awt.Canvas` rather than a `JPanel`: this loop renders actively,
    /// and Swing's repaint machinery would copy the finished frame through a back buffer of
    /// its own on the way to one we already have. `setIgnoreRepaint` turns off the other
    /// half of that -- the toolkit must not paint this component behind the loop's back.
    ///
    /// It is sized from the sheet rather than from a width and a height of its own, so the
    /// two cannot drift apart or be transposed.
    ///
    /// Three listeners, because a key that goes down here may come up anywhere: the third
    /// lets go of everything when the window stops being the one receiving keys.
    ///
    /// `\ IO` and not `\ IO + r` although the listener writes `keys`: a listener is a fixed
    /// JVM method on an anonymous class, and what it does to the caller's region is invisible
    /// from out here -- the same limit that keeps `loop` and `Sketch.start` concrete.
    ///
    def openCanvas(sheet: Sheet[r],
                   keys: Ref[Set[Int32], r],
                   closing: AtomicBoolean): AwtCanvas \ IO = {
        let (w, h) = size(sheet);
        let canvas = new AwtCanvas();
        canvas.setPreferredSize(new Dimension(w, h));
        canvas.setIgnoreRepaint(true);
        canvas.setFocusable(true);
        // Otherwise Tab moves focus out of the game instead of arriving as a key.
        canvas.setFocusTraversalKeysEnabled(false);
        canvas.addKeyListener(new KeyAdapter {
            def keyPressed(_a: KeyAdapter, e: KeyEvent): Unit \ IO + r =
                match afterPress(Ref.get(keys), e.getKeyCode()) {
                    case None => closing.set(true)
                    case Some(now) => Ref.put(now, keys)
                }
            def keyReleased(_a: KeyAdapter, e: KeyEvent): Unit \ IO + r =
                Ref.put(afterRelease(Ref.get(keys), e.getKeyCode()), keys)
        });
        // A key held when the window loses focus is never released, because the release goes
        // wherever the focus went. Without this, switching away mid-move and coming back
        // leaves the cannon walking into the wall on a key nobody is pressing.
        canvas.addFocusListener(new FocusAdapter {
            def focusLost(_a: FocusAdapter, _e: FocusEvent): Unit \ r =
                Ref.put((Set.empty(): Set[Int32]), keys)
        });
        canvas
    }

    ///
    /// The frame around the canvas, shown and focused.
    ///
    /// `DO_NOTHING_ON_CLOSE` and a listener that only raises a flag: the window must not take
    /// the JVM down with it, because the score table is written after the loop returns, so
    /// closing has to mean "stop" and not "exit".
    ///
    def openFrame(title: String, canvas: AwtCanvas, closing: AtomicBoolean): JFrame \ IO = {
        let frame = new JFrame(title);
        frame.setDefaultCloseOperation(WindowConstants.DO_NOTHING_ON_CLOSE);
        frame.addWindowListener(new WindowAdapter {
            def windowClosing(_a: WindowAdapter, _e: WindowEvent): Unit \ IO =
                closing.set(true)
        });
        frame.setResizable(false);
        frame.setIgnoreRepaint(true);
        discard frame.add(canvas);
        frame.pack();
        let noParent: Component = checked_cast(null);
        frame.setLocationRelativeTo(noParent);
        frame.setVisible(true);
        discard canvas.requestFocusInWindow();
        frame
    }

    ///
    /// The sheet this window is showing.
    ///
    pub def sheet(win: Window[r]): Sheet[r] =
        win#sheet

    // -- the keyboard -----------------------------------------------------------------------

    ///
    /// Whether a key press closes the window rather than reaching the sketch.
    ///
    /// Escape does, which is the convention every windowed sketch of this shape has had --
    /// Processing built it into `PApplet`, and a window that could only be dismissed with the
    /// mouse would be a regression rather than a simplification. The consequence is worth
    /// stating plainly: `Key.Escape` never reaches a step, so nothing above the runtime may
    /// use it for anything else.
    ///
    pub def closesWindow(code: Int32): Bool = code == escapeKey()

    /// AWT's `VK_ESCAPE`.
    def escapeKey(): Int32 = 27

    ///
    /// The keys held after a press of `code`, or `None` if the window took that press.
    ///
    /// The decision lives here rather than inside the listener because a listener is an
    /// anonymous JVM method with a window behind it, and nothing about which key does what
    /// needs either.
    ///
    pub def afterPress(held: Set[Int32], code: Int32): Option[Set[Int32]] =
        if (closesWindow(code)) None else Some(Set.insert(code, held))

    ///
    /// The keys held after a release of `code`.
    ///
    pub def afterRelease(held: Set[Int32], code: Int32): Set[Int32] =
        Set.remove(code, held)

    ///
    /// The AWT key codes currently held down.
    ///
    /// Codes rather than named keys: this layer knows about a keyboard and not about a
    /// game, and `Key.fromCode` one layer up is where a number becomes a name.
    ///
    pub def keysHeld(win: Window[r]): Set[Int32] \ r =
        Ref.get(win#keys)

    // -- the frame loop ---------------------------------------------------------------------

    ///
    /// Moves the deadline on by one frame and says how long to wait for it, in milliseconds.
    ///
    /// Swing's timer measures its delay from the moment it fires, so whatever a frame costs
    /// is added to every period after it and the display settles a few frames a second below
    /// the rate asked for. Aiming at a deadline instead spends an overrun once rather than
    /// compounding it, which is what keeps the average rate on target.
    ///
    /// A frame more than a whole period late abandons the ones it missed rather than firing
    /// them back to back: they are gone, and running them now would only put the next frame
    /// further behind. The simulation loses nothing by it -- the accumulator still owes the
    /// ticks that time was worth, and `Sketch` clamps how many of them one frame may run.
    ///
    pub def reschedule(dueNs: Int64, nowNs: Int64, periodNs: Int64): (Int64, Int32) = {
        let next = dueNs + periodNs;
        let target = if (next < nowNs) nowNs + periodNs else next;
        (target, millisOf(target - nowNs))
    }

    ///
    /// A nanosecond span as the whole milliseconds a timer can be asked to wait.
    ///
    /// Swing's timer counts in milliseconds, so 16.67 of them is asked for as 16 and the
    /// third that is dropped would drift the display fast. That is what `reschedule` exists
    /// to correct: the rounding happens once per frame and against a deadline, rather than
    /// accumulating.
    ///
    pub def millisOf(ns: Int64): Int32 =
        if (ns <= 0i64) 0
        else Option.getWithDefault(0, Int64.tryToInt32(ns / 1000000i64))

    ///
    /// How long the timer waits for the very first frame.
    ///
    /// Never zero, however short a period is asked for: a Swing timer with no delay
    /// saturates the event thread before the first frame has drawn, and the window never
    /// becomes responsive enough to be closed. Every frame after this one is scheduled by
    /// `reschedule`, which may legitimately ask for no wait at all -- by then there is a
    /// window, and a frame that is already late should not be delayed further.
    ///
    pub def firstDelay(periodNs: Int64): Int32 =
        Int32.max(1, millisOf(periodNs))

    ///
    /// Calls `frame` once every `periodNs` until the window closes.
    ///
    /// Nanoseconds and not a rate: what a frame is worth is the frame loop's business, and
    /// `Sketch` is where the rate a `Config` asks for is brought into range. Asking twice,
    /// in two units, is how the two would come to disagree.
    ///
    /// The callback runs on AWT's event dispatch thread, which is also the thread the key
    /// listeners run on and the only thread Swing may be touched from. One thread owns
    /// input, simulation and drawing, so none of them needs a lock.
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
    pub def loop(win: Window[r], periodNs: Int64, frame: Unit -> Unit \ IO + r)
        : Unit \ IO = {
        let due = new AtomicLong(System.nanoTime());
        // Built without a listener so that the listener can be given the timer: each frame
        // schedules the next one itself, against a deadline, rather than repeating on a
        // fixed delay that drifts.
        let noListener: ActionListener = checked_cast(null);
        let timer = new Timer(firstDelay(periodNs), noListener);
        timer.setRepeats(false);
        timer.addActionListener(new ActionListener {
            def actionPerformed(_a: ActionListener, _e: ActionEvent): Unit \ IO + r =
                if (win#closing.get()) ()
                else {
                    frame();
                    let (target, waitMs) = reschedule(due.get(), System.nanoTime(), periodNs);
                    due.set(target);
                    timer.setInitialDelay(waitMs);
                    timer.restart()
                }
        });
        timer.start();
        park(win);
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
    def park(win: Window[r]): Unit \ IO =
        if (win#closing.get()) ()
        else { Thread.sleep(pollMillis()); park(win) }

    /// How long the parked thread sleeps between looks at the close flag.
    def pollMillis(): Int64 = 20i64

    ///
    /// Asks the loop to stop, as though the window had been closed.
    ///
    /// This is how a bounded run ends: `FLIX_SKETCH_MAX_FRAMES` gives a sketch a frame
    /// budget so it terminates on a machine nobody is sitting in front of.
    ///
    pub def requestClose(win: Window[r]): Unit \ IO =
        win#closing.set(true)

    ///
    /// Shows everything drawn on the sheet since the last call.
    ///
    /// Blitting the finished buffer and flipping, rather than asking the toolkit to repaint:
    /// the frame is complete now, and a queued repaint would land somewhere inside the next
    /// one -- which shows up as tearing and makes the cost of drawing impossible to measure.
    ///
    /// A buffer the display driver has reclaimed is not retried. Every frame redraws the
    /// whole sheet, so the next one restores it in sixteen milliseconds, and a retry here
    /// would cost that on every frame to save it on almost none.
    ///
    /// The `sync` is for X11, where the toolkit is a client of a display server and may hold
    /// a finished frame in its request buffer until it has some other reason to flush --
    /// which is how a game that is comfortably inside its budget still looks jerky. It is
    /// close to free where it is not needed: measured here at 0.03 to 0.06ms on top of a
    /// present of about 0.1ms, against a frame of 16.7.
    ///
    pub def present(win: Window[r]): Unit \ IO = {
        let noObserver: ImageObserver = checked_cast(null);
        let g = win#strategy.getDrawGraphics();
        discard g.drawImage(win#sheet#image, 0, 0, noObserver);
        g.dispose();
        win#strategy.show();
        Toolkit.getDefaultToolkit().sync()
    }

    ///
    /// Closes the window and releases everything it was drawing through.
    ///
    pub def close(win: Window[r]): Unit \ IO = {
        win#strategy.dispose();
        release(win#sheet);
        win#frame.dispose()
    }

}
