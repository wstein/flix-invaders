mod TestContrast {

    use Assert.assertTrue
    use Assert.assertTrueWithMsg

    ///
    /// Colour choices are checked, not eyeballed.
    ///
    /// These use the WCAG 2.1 contrast ratio. The thresholds are the standard ones: 4.5 for
    /// body text, 3.0 for shapes and large text. If you change a colour in `Palette` and
    /// these fail, the new colour is genuinely harder to read -- pick a different one rather
    /// than lowering the bound.
    ///

    /// WCAG AA for normal-size text.
    def textThreshold(): Float64 = 4.5

    /// WCAG AA for graphics and large text.
    def shapeThreshold(): Float64 = 3.0

    def close(a: Float64, b: Float64, tolerance: Float64): Bool =
        Float64.abs(a - b) <= tolerance

    @Test
    def testBlackOnWhiteIsTheMaximumRatio(): Unit \ Assert = {
        let ratio = Color.contrastRatio(Color.black(), Color.white());
        assertTrueWithMsg(close(ratio, 21.0, 0.01), "expected 21:1, got ${ratio}")
    }

    @Test
    def testAColourAgainstItselfHasNoContrast(): Unit \ Assert = {
        let ratio = Color.contrastRatio(Palette.sun(), Palette.sun());
        assertTrueWithMsg(close(ratio, 1.0, 0.0001), "expected 1:1, got ${ratio}")
    }

    @Test
    def testContrastIsSymmetric(): Unit \ Assert = {
        let forward = Color.contrastRatio(Palette.background(), Palette.ink());
        let backward = Color.contrastRatio(Palette.ink(), Palette.background());
        assertTrueWithMsg(close(forward, backward, 0.0001), "${forward} vs ${backward}")
    }

    @Test
    def testLuminanceEndpoints(): Unit \ Assert = {
        assertTrueWithMsg(close(Color.luminance(Color.black()), 0.0, 0.0001),
            "black should be 0.0, got ${Color.luminance(Color.black())}");
        assertTrueWithMsg(close(Color.luminance(Color.white()), 1.0, 0.0001),
            "white should be 1.0, got ${Color.luminance(Color.white())}")
    }

    @Test
    def testLuminanceIsMonotonicInBrightness(): Unit \ Assert = {
        // Grey ramps must never go backwards, which catches a broken gamma transform.
        def loop(v) =
            if (v >= 255) ()
            else {
                let lower = Color.luminance(Color.grey(v));
                let higher = Color.luminance(Color.grey(v + 1));
                assertTrueWithMsg(higher >= lower, "luminance dropped between ${v} and ${v + 1}");
                loop(v + 1)
            };
        loop(0)
    }

    @Test
    def testGreenContributesMoreThanBlue(): Unit \ Assert =
        // Sanity check on the WCAG coefficients: the eye is far more sensitive to green.
        assertTrue(Color.luminance(Color.Rgb(0, 255, 0)) > Color.luminance(Color.Rgb(0, 0, 255)))

    @Test
    def testEveryTextColourIsReadableOnTheBackground(): Unit \ Assert =
        List.forEach(c -> {
            let ratio = Color.contrastRatio(c, Palette.background());
            assertTrueWithMsg(ratio >= textThreshold(),
                "text colour ${c} has only ${ratio}:1 on the background; needs ${textThreshold()}:1")
        }, Palette.textColors())

    @Test
    def testEveryShapeColourIsVisibleOnTheBackground(): Unit \ Assert =
        List.forEach(c -> {
            let ratio = Color.contrastRatio(c, Palette.background());
            assertTrueWithMsg(ratio >= shapeThreshold(),
                "shape colour ${c} has only ${ratio}:1 on the background; needs ${shapeThreshold()}:1")
        }, Palette.shapeColors())

    @Test
    def testWindowsAreVisibleAgainstTheSilhouette(): Unit \ Assert = {
        // The Still sketch draws lit windows onto the building silhouette, so that pair has
        // to hold up too -- not just everything against the background.
        let ratio = Color.contrastRatio(Palette.sun(), Palette.silhouette());
        assertTrueWithMsg(ratio >= shapeThreshold(),
            "lit windows have only ${ratio}:1 against the silhouette")
    }

    @Test
    def testPaletteColoursAreDistinguishableFromEachOther(): Unit \ Assert = {
        // Two accents that look alike make the balls in the animation sketch ambiguous.
        let accents = Palette.coral() :: Palette.mint() :: Palette.sun() :: Palette.azure() :: Nil;
        List.forEach(a ->
            List.forEach(b ->
                if (a == b) ()
                else {
                    let same = Color.redOf(a) == Color.redOf(b)
                        and Color.greenOf(a) == Color.greenOf(b)
                        and Color.blueOf(a) == Color.blueOf(b);
                    assertTrueWithMsg(not same, "two accents are identical: ${a}")
                }, accents), accents)
    }

}
