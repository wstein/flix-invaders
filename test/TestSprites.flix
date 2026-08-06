mod TestSprites {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertNeq
    use Assert.assertTrueWithMsg

    def tiny(): Sprite = Sprite.of(Vector#{
        "#.#",
        "###",
        "..."
    })

    @Test
    def testDimensionsComeFromTheRows(): Unit \ Assert = {
        assertEq(expected = 3, tiny()#width);
        assertEq(expected = 3, tiny()#height)
    }

    @Test
    def testWidthIsTheLongestRow(): Unit \ Assert =
        assertEq(expected = 5, Sprite.of(Vector#{"#", "##...", "###"})#width)

    @Test
    def testRunsAreCollapsedHorizontally(): Unit \ Assert = {
        // Row 0 has two single pixels with a gap; row 1 is one run of three; row 2 is empty.
        // Emitting one rectangle per run rather than per pixel is the whole point.
        assertEq(expected = (0, 0, 1) :: (0, 2, 1) :: (1, 0, 3) :: Nil, Sprite.runs(tiny()))
    }

    @Test
    def testAnEmptySpriteHasNoRuns(): Unit \ Assert =
        assertEq(expected = (Nil: List[(Int32, Int32, Int32)]),
                 Sprite.runs(Sprite.of(Vector#{"...", "..."})))

    @Test
    def testARunReachingTheRowEndIsClosed(): Unit \ Assert =
        // A run that never hits a trailing gap still has to be emitted.
        assertEq(expected = (0, 1, 3) :: Nil, Sprite.runs(Sprite.of(Vector#{".###"})))

    @Test
    def testASingleFullRowIsOneRun(): Unit \ Assert =
        assertEq(expected = (0, 0, 8) :: Nil, Sprite.runs(Sprite.of(Vector#{"########"})))

    @Test
    def testLitPixelsCountsEveryLitCell(): Unit \ Assert =
        assertEq(expected = 5, Sprite.litPixels(tiny()))

    @Test
    def testRunsCoverExactlyTheLitPixels(): Unit \ Assert =
        // The run lengths must add up to the lit pixel count for every sprite in the game,
        // which catches an off-by-one at either end of a row.
        List.forEach(sprite -> {
            let fromRuns = List.foldLeft((total, segment) -> {
                let (_, _, length) = segment;
                total + length
            }, 0, Sprite.runs(sprite));
            assertEq(expected = Sprite.litPixels(sprite), fromRuns)
        }, everySprite())

    def everySprite(): List[Sprite] =
        Sprites.squidA() :: Sprites.squidB()
            :: Sprites.crabA() :: Sprites.crabB()
            :: Sprites.octopusA() :: Sprites.octopusB()
            :: Sprites.cannon() :: Sprites.bullet() :: Sprites.bomb() :: Nil

    @Test
    def testEverySpriteHasArtworkInIt(): Unit \ Assert =
        List.forEach(sprite ->
            assertTrueWithMsg(Sprite.litPixels(sprite) > 0, "a sprite is blank"),
            everySprite())

    @Test
    def testEverySpriteRowIsTheSameWidth(): Unit \ Assert =
        // A ragged row would silently shift part of a sprite left.
        List.forEach(sprite ->
            Vector.forEach(row ->
                assertTrueWithMsg(String.length(row) == sprite#width,
                    "ragged sprite row: '${row}' is ${String.length(row)}, expected ${sprite#width}"),
                sprite#rows),
            everySprite())

    @Test
    def testTheInvaderFramesDiffer(): Unit \ Assert = {
        // Two identical frames would animate to nothing.
        assertNeq(unexpected = Sprite.runs(Sprites.squidA()), Sprite.runs(Sprites.squidB()));
        assertNeq(unexpected = Sprite.runs(Sprites.crabA()), Sprite.runs(Sprites.crabB()));
        assertNeq(unexpected = Sprite.runs(Sprites.octopusA()), Sprite.runs(Sprites.octopusB()))
    }

    @Test
    def testForKindAlternatesAndWraps(): Unit \ Assert = {
        assertEq(expected = Sprite.runs(Sprites.crabA()), Sprite.runs(Sprites.forKind(InvaderKind.Crab, 0)));
        assertEq(expected = Sprite.runs(Sprites.crabB()), Sprite.runs(Sprites.forKind(InvaderKind.Crab, 1)));
        assertEq(expected = Sprite.runs(Sprites.crabA()), Sprite.runs(Sprites.forKind(InvaderKind.Crab, 2)))
    }

    @Test
    def testEachKindHasItsOwnArtwork(): Unit \ Assert = {
        assertNeq(unexpected = Sprite.runs(Sprites.forKind(InvaderKind.Squid, 0)),
                  Sprite.runs(Sprites.forKind(InvaderKind.Crab, 0)));
        assertNeq(unexpected = Sprite.runs(Sprites.forKind(InvaderKind.Crab, 0)),
                  Sprite.runs(Sprites.forKind(InvaderKind.Octopus, 0)))
    }

    @Test
    def testDrawingIsCentredOnThePosition(): Unit \ Assert = {
        // A 3x3 sprite at scale 2 is 6x6, so its top-left corner sits 3 above and left of
        // the centre it is asked to draw at.
        let cmds = Canvas.commands((640, 480), () ->
            Sprite.draw(tiny(), { x = 100.0f32, y = 100.0f32 }, 2.0f32));
        match List.head(cmds) {
            case Some(DrawCmd.Rect(x, y, w, h)) => {
                assertEq(expected = 97.0f32, x);
                assertEq(expected = 97.0f32, y);
                assertEq(expected = 2.0f32, w);
                assertEq(expected = 2.0f32, h)
            }
            case other => Assert.fail("expected a rect first, got ${other}")
        }
    }

    @Test
    def testDrawingEmitsOneRectPerRun(): Unit \ Assert = {
        let cmds = Canvas.commands((640, 480), () ->
            Sprite.draw(tiny(), { x = 0.0f32, y = 0.0f32 }, 1.0f32));
        assertEq(expected = List.length(Sprite.runs(tiny())), List.length(cmds))
    }

    @Test
    def testScaleChangesSizeNotShape(): Unit \ Assert = {
        let single = Canvas.commands((640, 480), () ->
            Sprite.draw(Sprites.crabA(), { x = 0.0f32, y = 0.0f32 }, 1.0f32));
        let double = Canvas.commands((640, 480), () ->
            Sprite.draw(Sprites.crabA(), { x = 0.0f32, y = 0.0f32 }, 2.0f32));
        assertEq(expected = List.length(single), List.length(double))
    }

    @Test
    def testTheInvadersAreWiderThanTheyAreTall(): Unit \ Assert =
        // Sanity check on the artwork: these are 8 rows tall, as in the original.
        List.forEach(sprite -> assertEq(expected = 8, sprite#height),
            Sprites.squidA() :: Sprites.crabA() :: Sprites.octopusA() :: Sprites.cannon() :: Nil)

}
