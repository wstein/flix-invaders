mod TestStill {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertTrueWithMsg

    ///
    /// The teaching sketch, checked the way every other drawing here is: as data, no window.
    ///
    /// `Still` is an entry point -- `bin/sketch static` runs it -- so nothing in `src/` calls
    /// it and nothing ever should. Without this file it would be the one drawing in the
    /// project that no test ever runs, and its header invites the reader to edit it, which is
    /// a poor thing to invite with nothing to catch an edit that goes wrong.
    ///
    /// So these pin what any such edit must keep true -- the frame is cleared, everything
    /// drawn can actually be seen, the colours stay in the palette -- and deliberately not
    /// where the sun sits or how tall the buildings are. Move them freely.
    ///

    /// The size `Still.main` opens, so the picture is judged at the size it is drawn at.
    def canvas(): (Int32, Int32) = (640, 480)

    def scene(): List[DrawCmd] = Canvas.commands(canvas(), Still.scene)

    /// Whether a box overlaps the canvas at all, however little.
    def visible(x: Float32, y: Float32, w: Float32, h: Float32): Bool = {
        let (cw, ch) = canvas();
        let xVis = x + w > 0.0f32 and x < Int32.toFloat32(cw);
        let yVis = y + h > 0.0f32 and y < Int32.toFloat32(ch);
        xVis and yVis
    }

    @Test
    def testTheFrameIsClearedBeforeAnythingIsDrawn(): Unit \ Assert = match scene() {
        case DrawCmd.Clear(c) :: _ => assertEq(expected = Palette.background(), c)
        // Without a clear, whatever the previous frame drew stays on screen underneath.
        case _ => assertTrueWithMsg(false, "the scene must clear before it draws")
    }

    @Test
    def testTheSceneDrawsASunAndSomeBuildings(): Unit \ Assert = {
        let cmds = scene();
        let ellipses = List.count(cmd -> match cmd {
            case DrawCmd.Ellipse(_, _, _, _) => true
            case _ => false
        }, cmds);
        let rects = List.count(cmd -> match cmd {
            case DrawCmd.Rect(_, _, _, _) => true
            case _ => false
        }, cmds);
        assertTrueWithMsg(ellipses >= 1, "the sun is gone");
        // Ground, three buildings, two windows each.
        assertTrueWithMsg(rects >= 4, "only ${rects} rectangles left in the skyline")
    }

    ///
    /// Nothing is drawn entirely off the canvas.
    ///
    /// A shape outside the frame is invisible, which in a picture is the same mistake as
    /// unreachable code: it costs the same to draw and shows nothing.
    ///
    @Test
    def testEverythingDrawnIsAtLeastPartlyVisible(): Unit \ Assert =
        List.forEach(cmd -> match cmd {
            case DrawCmd.Rect(x, y, w, h) =>
                assertTrueWithMsg(visible(x, y, w, h), "rect at (${x}, ${y}) is off-canvas")
            case DrawCmd.Ellipse(x, y, w, h) =>
                // Ellipses are centred, rectangles are not.
                assertTrueWithMsg(visible(x - w / 2.0f32, y - h / 2.0f32, w, h),
                    "ellipse at (${x}, ${y}) is off-canvas")
            case DrawCmd.Text(s, x, y) =>
                assertTrueWithMsg(visible(x, y, 1.0f32, 1.0f32),
                    "text \"${s}\" starts off-canvas at (${x}, ${y})")
            case _ => ()
        }, scene())

    ///
    /// Every colour on screen is one `TestContrast` already vouches for.
    ///
    /// `Still` says so in a comment; this is what makes it true. A colour written inline here
    /// would be readable or not by luck, and nothing else in the project would ever check it.
    ///
    @Test
    def testEveryColourComesFromThePalette(): Unit \ Assert = {
        let known = Palette.background() :: Palette.textColors() ::: Palette.shapeColors();
        let vouched = (c, place) ->
            assertTrueWithMsg(List.memberOf(c, known), "${place} uses ${c}, which is not in the palette");
        List.forEach(cmd -> match cmd {
            case DrawCmd.Clear(c) => vouched(c, "the sky")
            case DrawCmd.Fill(c) => vouched(c, "a shape")
            case DrawCmd.FillAlpha(c, _) => vouched(c, "an overlay")
            case _ => ()
        }, scene())
    }

    @Test
    def testTheSceneIsPure(): Unit \ Assert = {
        // No state, no time, no input -- which is the whole claim the sketch is teaching.
        assertEq(expected = scene(), scene());
        assertTrue(not List.isEmpty(scene()))
    }

}
