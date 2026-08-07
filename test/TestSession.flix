mod TestSession {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertNeq
    use Assert.assertTrueWithMsg

    def start(): Session = Session.initial(2026i64)

    /// One cabinet tick, discarding sound.
    def tick(s: Session, input: Snapshot): Session =
        Sound.runWithNoOp(() -> Session.step(s, input))

    def ticks(n: Int32, s: Session, input: Snapshot): Session =
        if (n <= 0) s else ticks(n - 1, tick(s, input), input)

    /// The digit keys, as the runtime delivers them.
    def digit(n: Int32): Snapshot = Input.holding(Key.Other(48 + n) :: Nil)

    def rectCount(s: Session): Int32 =
        List.count(cmd -> match cmd {
            case DrawCmd.Rect(_, _, _, _) => true
            case _ => false
        }, Canvas.commands((640, 480), () -> Screens.render(s)))

    // -- the attract loop --------------------------------------------------------------

    @Test
    def testTheCabinetStartsInAttract(): Unit \ Assert =
        assertEq(expected = Screen.Attract, start()#screen)

    @Test
    def testTheDemoPlaysWhileNobodyIs(): Unit \ Assert = {
        // The attract screen is a real game being played, not a still image.
        let later = ticks(60, start(), Input.empty());
        assertTrue(later#demo#tick > 0);
        assertNeq(unexpected = start()#demo#playerX, later#demo#playerX)
    }

    @Test
    def testTheAttractScreenIsSilent(): Unit \ Assert = {
        // A cabinet on a desk should not fire continuously. The demo runs under
        // `Sound.runWithNoOp`, so nothing escapes into the room.
        let heard = Sound.played(() -> {
            def loop(n, s) = if (n <= 0) s else loop(n - 1, Session.step(s, Input.empty()));
            let _ = loop(200, start());
            ()
        });
        assertEq(expected = (Nil: List[SoundCmd]), heard)
    }

    @Test
    def testTheDemoRestartsWhenTheBotLoses(): Unit \ Assert = {
        // Long enough for a shaky bot to die at least once; the loop must keep going.
        let later = ticks(4000, start(), Input.empty());
        assertEq(expected = Screen.Attract, later#screen);
        assertNeq(unexpected = Phase.Lost, later#demo#phase)
    }

    @Test
    def testTheDemoUsesItsOwnGeneratorNotTheGames(): Unit \ Assert = {
        // The attract game is seeded separately, so it never mirrors the game you get when
        // you press start.
        assertNeq(unexpected = start()#demo#seed, start()#seed)
    }

    // -- starting a game ---------------------------------------------------------------

    @Test
    def testPressingOneStartsASinglePlayerGame(): Unit \ Assert = {
        let playing = tick(start(), digit(1));
        assertEq(expected = Screen.Playing, playing#screen);
        assertEq(expected = 1, playing#players);
        assertEq(expected = 1, Vector.length(playing#worlds))
    }

    @Test
    def testPressingTwoStartsATwoPlayerGame(): Unit \ Assert = {
        let playing = tick(start(), digit(2));
        assertEq(expected = Screen.Playing, playing#screen);
        assertEq(expected = 2, playing#players);
        assertEq(expected = 2, Vector.length(playing#worlds))
    }

    @Test
    def testEnterAlsoStartsOnePlayer(): Unit \ Assert =
        assertEq(expected = 1, tick(start(), Input.holding(Key.Enter :: Nil))#players)

    @Test
    def testAFreshGameIsNotTheDemo(): Unit \ Assert = {
        // Pressing start must hand you a new game, not drop you into the bot's.
        let playing = tick(ticks(300, start(), Input.empty()), digit(1));
        assertEq(expected = 0, Session.active(playing)#tick);
        assertEq(expected = 0, Session.active(playing)#score)
    }

    @Test
    def testTheStartRequestReadsEdgesNotHeldKeys(): Unit \ Assert = {
        // Holding 1 must not restart the game every tick once you are playing.
        let held = Input.diff(previous = Set#{Key.Other(49)}, current = Set#{Key.Other(49)},
                              mouseX = 0, mouseY = 0);
        assertEq(expected = (None: Option[Int32]), Session.startRequest(held))
    }

    // -- playing ------------------------------------------------------------------------

    @Test
    def testARealGameIsAudible(): Unit \ Assert = {
        // The silence is the attract screen's, not the game's.
        let playing = tick(start(), digit(1));
        let heard = Sound.played(() -> {
            let _ = Session.step(playing, Input.holding(Key.Space :: Nil));
            ()
        });
        assertTrueWithMsg(List.memberOf(SoundCmd.Shoot, heard), "firing was inaudible: ${heard}")
    }

    @Test
    def testTheGameAdvancesWhilePlaying(): Unit \ Assert = {
        let playing = tick(start(), digit(1));
        assertTrue(Session.active(ticks(30, playing, Input.empty()))#tick > 0)
    }

    @Test
    def testEnterOnGameOverReturnsToAttract(): Unit \ Assert = {
        let playing = tick(start(), digit(1));
        let lost = { worlds = Vector#{{ phase = Phase.Lost | Session.active(playing) }} | playing };
        assertEq(expected = Screen.Attract, tick(lost, Input.holding(Key.Enter :: Nil))#screen)
    }

    // -- what is on screen ---------------------------------------------------------------

    @Test
    def testTheAttractScreenDrawsTheGameUnderneath(): Unit \ Assert = {
        // The title is an overlay, not a replacement -- the point is to show the game.
        let attract = start();
        let playing = tick(attract, digit(1));
        assertTrueWithMsg(rectCount(attract) > rectCount(playing) / 2,
            "the attract screen is not drawing a game behind the title")
    }

    @Test
    def testTheAttractScreenSaysHowToStart(): Unit \ Assert = {
        let cmds = Canvas.commands((640, 480), () -> Screens.render(start()));
        let says = needle -> List.exists(cmd -> match cmd {
            case DrawCmd.Text(t, _, _) => String.contains(substr = needle, t)
            case _ => false
        }, cmds);
        assertTrue(says("1 OR 2"));
        assertTrue(says("DEMO"))
    }

    @Test
    def testPlayingDrawsNoTitle(): Unit \ Assert = {
        let playing = tick(start(), digit(1));
        let cmds = Canvas.commands((640, 480), () -> Screens.render(playing));
        assertTrue(not List.exists(cmd -> match cmd {
            case DrawCmd.Text(t, _, _) => String.contains(substr = "DEMO", t)
            case _ => false
        }, cmds))
    }

}
