mod TestCanvas {

    use Assert.assertEq

    ///
    /// These tests are the point of the `Canvas` effect: rendering is checked as data, with
    /// no window and no `IO`. If any of them needed a display, the effect boundary would
    /// have leaked.
    ///

    @Test
    def testRecordsOperationsInOrder(): Unit \ Assert = {
        let cmds = Canvas.commands((640, 480), () -> {
            Canvas.clear(Color.black());
            Canvas.fill(Color.white());
            Canvas.rect(1.0f32, 2.0f32, 3.0f32, 4.0f32)
        });
        let expected =
            DrawCmd.Clear(Color.Rgb(0, 0, 0)) ::
            DrawCmd.Fill(Color.Rgb(255, 255, 255)) ::
            DrawCmd.Rect(1.0f32, 2.0f32, 3.0f32, 4.0f32) :: Nil;
        assertEq(expected = expected, cmds)
    }

    @Test
    def testDrawingNothingRecordsNothing(): Unit \ Assert =
        assertEq(expected = (Nil: List[DrawCmd]), Canvas.commands((640, 480), () -> ()))

    @Test
    def testDimensionsReportsTheConfiguredSize(): Unit \ Assert = {
        let (dims, cmds) = Canvas.runCollecting((320, 240), () -> Canvas.dimensions());
        assertEq(expected = (320, 240), dims);
        // Querying the canvas must not be recorded as a drawing operation.
        assertEq(expected = (Nil: List[DrawCmd]), cmds)
    }

    @Test
    def testRunCollectingReturnsTheResult(): Unit \ Assert = {
        let (value, _) = Canvas.runCollecting((10, 10), () -> {
            Canvas.rect(0.0f32, 0.0f32, 1.0f32, 1.0f32);
            42
        });
        assertEq(expected = 42, value)
    }

    @Test
    def testPaintRoundTrips(): Unit \ Assert = {
        let cmds =
            DrawCmd.Clear(Color.grey(30)) ::
            DrawCmd.TextSize(12.0f32) ::
            DrawCmd.Text("hi", 5.0f32, 6.0f32) ::
            DrawCmd.Ellipse(1.0f32, 2.0f32, 3.0f32, 4.0f32) :: Nil;
        assertEq(expected = cmds, Canvas.commands((640, 480), () -> Canvas.paint(cmds)))
    }

    @Test
    def testRenderingIsDeterministic(): Unit \ Assert = {
        let scene = () -> { Canvas.clear(Color.grey(10)); Canvas.rect(1.0f32, 1.0f32, 2.0f32, 2.0f32) };
        assertEq(expected = Canvas.commands((64, 64), scene), Canvas.commands((64, 64), scene))
    }

    @Test
    def testColorPacksToRrggbb(): Unit \ Assert = {
        assertEq(expected = 0, Color.toInt32(Color.black()));
        assertEq(expected = 16777215, Color.toInt32(Color.white()));
        assertEq(expected = 16711680, Color.toInt32(Color.Rgb(255, 0, 0)));
        assertEq(expected = 65280, Color.toInt32(Color.Rgb(0, 255, 0)));
        assertEq(expected = 255, Color.toInt32(Color.Rgb(0, 0, 255)))
    }

    @Test
    def testColorChannelsAreClamped(): Unit \ Assert = {
        assertEq(expected = Color.toInt32(Color.white()), Color.toInt32(Color.Rgb(999, 300, 256)));
        assertEq(expected = Color.toInt32(Color.black()), Color.toInt32(Color.Rgb(-1, -50, -999)))
    }

}
