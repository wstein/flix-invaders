///
/// The rasteriser, checked against real pixels.
///
/// Everything above this asserts on *intentions*: `TestCanvas` collects `DrawCmd`s and
/// `TestView` asserts on where the game says a banner goes. Nothing asked what Java2D
/// actually painted -- so a `rect` that drew at the wrong corner, or an `ellipse` measured
/// from its edge instead of its centre, would have passed every test in the suite and been
/// caught only by someone looking at the screen.
///
/// `Surface.offscreen` is what makes this possible without a display: it hands back a sheet
/// with no window anywhere near it, so these run on a CI machine with no screen. That is
/// also why the headless grep in CI names `Surface.open` and not `Surface`.
///
mod TestSurface {

    use Assert.assertEq
    use Assert.assertTrue

    /// A small black sheet with the platform font, which none of these tests read.
    def sheet(rc: Region[r], w: Int32, h: Int32): Surface.Sheet[r] \ IO + r = {
        let s = Surface.offscreen(rc, width = w, height = h, None);
        Surface.background(s, Color.black());
        s
    }

    // -- the sheet itself -----------------------------------------------------------------

    @Test
    def testASheetIsTheSizeItWasAskedFor(): Unit \ IO + Assert =
        region rc {
            let s = Surface.offscreen(rc, width = 7, height = 3, None);
            assertEq(expected = (7, 3), Surface.size(s));
            Surface.release(s)
        }

    ///
    /// A font path that names nothing is the ordinary case on a CI runner and in a jar run
    /// from the wrong directory. It must cost looks, not a crash. The line it prints while
    /// this test runs is the behaviour, not noise: silently drawing in the wrong font is how
    /// a broken asset path survives a release.
    ///
    @Test
    def testAMissingFontIsSurvivable(): Unit \ IO + Assert =
        region rc {
            let s = Surface.offscreen(rc, width = 4, height = 4, Some("no/such/font.ttf"));
            Surface.background(s, Color.white());
            assertEq(expected = Color.white(), Surface.pixelAt(s, 2, 2));
            Surface.release(s)
        }

    // -- clearing and filling --------------------------------------------------------------

    @Test
    def testBackgroundReachesEveryCorner(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 5, 4);
            Surface.background(s, Color.Rgb(10, 20, 30));
            let corners = (0, 0) :: (4, 0) :: (0, 3) :: (4, 3) :: Nil;
            List.forEach(xy -> {
                let (x, y) = xy;
                assertEq(expected = Color.Rgb(10, 20, 30), Surface.pixelAt(s, x, y))
            }, corners);
            Surface.release(s)
        }

    ///
    /// `background` leaves its colour as the fill, the way Processing's does -- so a screen
    /// that clears and then draws without setting a colour draws in the clear colour rather
    /// than in whatever was left over.
    ///
    @Test
    def testBackgroundLeavesItsColourAsTheFill(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 6, 6);
            Surface.background(s, Color.Rgb(0, 0, 40));
            Surface.rect(s, 1.0f32, 1.0f32, 2.0f32, 2.0f32);
            assertEq(expected = Color.Rgb(0, 0, 40), Surface.pixelAt(s, 2, 2));
            Surface.release(s)
        }

    // -- rectangles ------------------------------------------------------------------------

    ///
    /// The corner convention, which nothing else in the project can check: `rect(x, y, w, h)`
    /// puts its *top-left* at `(x, y)`. Centring it instead would move every sprite in the
    /// game by half its size and no existing test would notice.
    ///
    @Test
    def testARectangleStartsAtItsTopLeftCorner(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 8, 8);
            Surface.fill(s, Color.white());
            Surface.rect(s, 2.0f32, 3.0f32, 2.0f32, 2.0f32);
            // Inside.
            assertEq(expected = Color.white(), Surface.pixelAt(s, 2, 3));
            assertEq(expected = Color.white(), Surface.pixelAt(s, 3, 4));
            // Just outside, on every side.
            assertEq(expected = Color.black(), Surface.pixelAt(s, 1, 3));
            assertEq(expected = Color.black(), Surface.pixelAt(s, 2, 2));
            assertEq(expected = Color.black(), Surface.pixelAt(s, 4, 3));
            assertEq(expected = Color.black(), Surface.pixelAt(s, 2, 5));
            Surface.release(s)
        }

    ///
    /// The reason `Surface` fills a `Rectangle2D$Float` rather than calling `fillRect` with
    /// whole pixels. The formation marches at 0.65 pixels a tick, so a shape that snapped to
    /// the pixel grid would advance in visible jumps instead of gliding.
    ///
    /// Half a pixel of white on black must land as something that is neither.
    ///
    @Test
    def testHalfAPixelIsDrawnAsHalfAPixel(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 8, 8);
            Surface.fill(s, Color.white());
            Surface.rect(s, 2.0f32, 2.0f32, 0.5f32, 4.0f32);
            let covered = Color.redOf(Surface.pixelAt(s, 2, 3));
            assertTrue(covered > 0 and covered < 255)
        }

    // -- ellipses --------------------------------------------------------------------------

    ///
    /// The other convention: an ellipse is measured from its *centre*, so `ellipse(4, 4, 6, 6)`
    /// covers the middle of an eight-pixel sheet and not its bottom-right quarter.
    ///
    @Test
    def testAnEllipseIsCentredOnItsPoint(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 9, 9);
            Surface.fill(s, Color.white());
            Surface.ellipse(s, 4.0f32, 4.0f32, 6.0f32, 6.0f32);
            assertEq(expected = Color.white(), Surface.pixelAt(s, 4, 4));
            // The corners of the sheet are outside a circle of radius three about the middle.
            assertEq(expected = Color.black(), Surface.pixelAt(s, 0, 0));
            assertEq(expected = Color.black(), Surface.pixelAt(s, 8, 8));
            Surface.release(s)
        }

    // -- translucency ----------------------------------------------------------------------

    ///
    /// What the attract screen's dimmed panel is made of: a fill that lets the live game show
    /// through instead of cutting the formation in half.
    ///
    @Test
    def testATranslucentFillLandsBetweenTheTwoColours(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 6, 6);
            Surface.fillAlpha(s, Color.white(), 128);
            Surface.rect(s, 0.0f32, 0.0f32, 6.0f32, 6.0f32);
            let mixed = Color.redOf(Surface.pixelAt(s, 3, 3));
            assertTrue(mixed > 100 and mixed < 160);
            Surface.release(s)
        }

    @Test
    def testAFullyTransparentFillDrawsNothing(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 6, 6);
            Surface.fillAlpha(s, Color.white(), 0);
            Surface.rect(s, 0.0f32, 0.0f32, 6.0f32, 6.0f32);
            assertEq(expected = Color.black(), Surface.pixelAt(s, 3, 3));
            Surface.release(s)
        }

    ///
    /// An alpha outside 0..255 is clamped rather than wrapped: `new Color` throws on a
    /// component out of range, and a crash is a poor answer to a bad number.
    ///
    @Test
    def testAnAlphaOutOfRangeIsClampedRatherThanThrown(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 6, 6);
            Surface.fillAlpha(s, Color.white(), 4000);
            Surface.rect(s, 0.0f32, 0.0f32, 6.0f32, 6.0f32);
            assertEq(expected = Color.white(), Surface.pixelAt(s, 3, 3));
            Surface.fillAlpha(s, Color.black(), -7);
            Surface.rect(s, 0.0f32, 0.0f32, 6.0f32, 6.0f32);
            assertEq(expected = Color.white(), Surface.pixelAt(s, 3, 3));
            Surface.release(s)
        }

    // -- text ------------------------------------------------------------------------------

    ///
    /// Which pixels a glyph lights depends on the platform's font, so this asks only what is
    /// platform-independent: that text is drawn *above* the baseline it is given, which is
    /// the convention every caller in the project relies on when it places a label.
    ///
    @Test
    def testTextSitsOnItsBaseline(): Unit \ IO + Assert =
        region rc {
            let s = sheet(rc, 40, 24);
            Surface.textSize(s, 16.0f32);
            Surface.fill(s, Color.white());
            Surface.text(s, "H", 4.0f32, 20.0f32);
            let litIn = (top, bottom) ->
                List.exists(y -> List.exists(x ->
                    Color.redOf(Surface.pixelAt(s, x, y)) > 0, List.range(0, 40)),
                    List.range(top, bottom));
            assertTrue(litIn(4, 20));
            assertTrue(not litIn(21, 24));
            Surface.release(s)
        }

}
