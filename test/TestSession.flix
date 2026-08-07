mod TestSession {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertNeq
    use Assert.assertTrueWithMsg
    use Assert.assertFalseWithMsg

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
        }, Canvas.commands((640, 480), () -> Screens.render(s, Stats.empty())))

    /// Every string the cabinet draws for this session.
    def texts(s: Session): List[String] =
        Canvas.commands((640, 480), () -> Screens.render(s, Stats.empty()))
            |> List.filterMap(cmd -> match cmd {
                case DrawCmd.Text(t, _, _) => Some(t)
                case _ => None
            })

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
    def testAFinishedGameLeavesThePlayField(): Unit \ Assert = {
        // However it ends, the cabinet stops simulating and moves on to the score screens.
        let playing = tick(start(), digit(1));
        let lost = { worlds = Vector#{{ phase = Phase.Lost | Session.active(playing) }} | playing };
        assertNeq(unexpected = Screen.Playing, tick(lost, Input.empty())#screen)
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
        let cmds = Canvas.commands((640, 480), () -> Screens.render(start(), Stats.empty()));
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
        let cmds = Canvas.commands((640, 480), () -> Screens.render(playing, Stats.empty()));
        assertTrue(not List.exists(cmd -> match cmd {
            case DrawCmd.Text(t, _, _) => String.contains(substr = "DEMO", t)
            case _ => false
        }, cmds))
    }

    // -- alternating play ---------------------------------------------------------------

    def twoPlayer(): Session = tick(start(), digit(2))

    /// Puts a bomb on the active cannon so the next step destroys it.
    def aboutToDie(s: Session): Session = {
        let w = Session.active(s);
        { worlds = Vector.update(s#current, { bombs = { x = w#playerX, y = Rules.playerY() } :: Nil | w },
                                 s#worlds) | s }
    }

    @Test
    def testTwoPlayersGetSeparateGames(): Unit \ Assert = {
        // Separate formations, bunkers, lives and levels -- not a shared field.
        let s = twoPlayer();
        let a = Vector.get(0, s#worlds);
        let b = Vector.get(1, s#worlds);
        assertEq(expected = Rules.startingLives(), a#lives);
        assertEq(expected = Rules.startingLives(), b#lives);
        assertNeq(unexpected = a#seed, b#seed)
    }

    @Test
    def testLosingACannonDoesNotEndTheTurn(): Unit \ Assert = {
        // A turn is a whole game. Losing a cannon costs a life and nothing else -- the
        // arcade original hands over here, and this does not.
        let hit = tick(aboutToDie(twoPlayer()), Input.empty());
        assertEq(expected = 0, hit#current);
        let after = ticks(Rules.deathPauseTicks() + 2, hit, Input.empty());
        assertEq(expected = 0, after#current);
        assertEq(expected = Rules.startingLives() - 1, Session.active(after)#lives)
    }

    @Test
    def testTheTurnPassesWhenTheLastLifeGoes(): Unit \ Assert = {
        // ...and only then.
        let s = twoPlayer();
        let onLastLife = { worlds = Vector.update(0, { lives = 1 | Vector.get(0, s#worlds) },
                                                  s#worlds) | s };
        // Past the death pause *and* the GAME OVER beat, which now comes between the two.
        let after = ticks(Rules.deathPauseTicks() + Rules.gameOverTicks() + 3,
                          aboutToDie(onLastLife), Input.empty());
        assertEq(expected = 1, after#current)
    }

    @Test
    def testPlayerOnePlaysAWholeGameBeforePlayerTwoStarts(): Unit \ Assert = {
        // The property in one test: player two's world does not advance a single tick until
        // player one has none left.
        let s = twoPlayer();
        let untouched = Vector.get(1, s#worlds)#tick;
        def loop(n, sess) =
            if (n <= 0 or sess#current != 0) sess
            else loop(n - 1, tick(sess, Input.holding(Key.Space :: Nil)));
        let handedOver = loop(20000, s);
        assertEq(expected = 1, handedOver#current);
        assertEq(expected = Phase.Lost, Vector.get(0, handedOver#worlds)#phase);
        assertEq(expected = untouched, Vector.get(1, handedOver#worlds)#tick)
    }

    @Test
    def testTheOtherPlayersGameIsUntouchedWhileWaiting(): Unit \ Assert = {
        // Player two's world must be frozen during player one's turn.
        let s = twoPlayer();
        let waiting = Vector.get(1, s#worlds);
        let later = ticks(60, s, Input.holding(Key.Space :: Nil));
        assertEq(expected = waiting#tick, Vector.get(1, later#worlds)#tick);
        assertTrue(Vector.get(0, later#worlds)#tick > 0)
    }

    @Test
    def testASinglePlayerKeepsTheirTurnAfterDying(): Unit \ Assert = {
        // With nobody to hand over to, the same player carries on with their next life.
        let solo = tick(start(), digit(1));
        let after = ticks(Rules.deathPauseTicks() + 3, aboutToDie(solo), Input.empty());
        assertEq(expected = 0, after#current);
        assertEq(expected = Rules.startingLives() - 1, Session.active(after)#lives)
    }

    @Test
    def testAFinishedPlayerIsSkipped(): Unit \ Assert = {
        // Player two is out; the turn must come back to player one rather than stalling.
        let s = twoPlayer();
        let out = { worlds = Vector.update(1, { phase = Phase.Lost | Vector.get(1, s#worlds) }, s#worlds) | s };
        assertEq(expected = Some(0), Session.nextPlayer(0, out))
    }

    @Test
    def testNobodyLeftEndsTheSession(): Unit \ Assert = {
        let s = twoPlayer();
        let over = { worlds = Vector.map(w -> { phase = Phase.Lost | w }, s#worlds) | s };
        assertEq(expected = (None: Option[Int32]), Session.nextPlayer(0, over));
        assertTrue(Session.allDone(over))
    }

    @Test
    def testAScorelessGameGoesStraightToTheTable(): Unit \ Assert = {
        // Nothing was earned, so there is nothing to sign for.
        let s = twoPlayer();
        let over = { worlds = Vector.map(w -> { phase = Phase.Lost | w }, s#worlds) | s };
        assertEq(expected = Screen.Table, tick(over, Input.empty())#screen)
    }

    @Test
    def testTheTableReturnsToAttract(): Unit \ Assert = {
        let s = twoPlayer();
        let over = { worlds = Vector.map(w -> { phase = Phase.Lost | w }, s#worlds) | s };
        let showing = tick(over, Input.empty());
        assertEq(expected = Screen.Table, ticks(50, showing, Input.empty())#screen);
        assertEq(expected = Screen.Attract, tick(showing, Input.holding(Key.Enter :: Nil))#screen)
    }

    // -- the two-player HUD ---------------------------------------------------------------

    @Test
    def testTheHudCarriesTheOtherPlayersScore(): Unit \ Assert = {
        let s = twoPlayer();
        let scored = { worlds = Vector.update(1, { score = 750 | Vector.get(1, s#worlds) }, s#worlds) | s };
        assertEq(expected = 750, Session.cabinet(scored)#otherScore);
        assertEq(expected = 1, Session.cabinet(scored)#player)
    }

    @Test
    def testASoloGameHasNoOtherScore(): Unit \ Assert = {
        let c = Session.cabinet(tick(start(), digit(1)));
        assertEq(expected = 0, c#otherScore);
        assertEq(expected = 1, c#players)
    }

    @Test
    def testBothScoresAreShownInTwoPlayer(): Unit \ Assert = {
        // The second slot used to be a hard-coded zero; it must now track a real player.
        let s = twoPlayer();
        let scored = { worlds = Vector.update(1, { score = 1234 | Vector.get(1, s#worlds) }, s#worlds) | s };
        let cmds = Canvas.commands((640, 480), () -> Screens.render(scored, Stats.empty()));
        assertTrue(List.exists(cmd -> match cmd {
            case DrawCmd.Text(t, _, _) => String.contains(substr = "1234", t)
            case _ => false
        }, cmds))
    }

    @Test
    def testTheHudNamesWhoseTurnItIs(): Unit \ Assert = {
        let cmds = Canvas.commands((640, 480), () -> Screens.render(twoPlayer(), Stats.empty()));
        assertTrue(List.exists(cmd -> match cmd {
            case DrawCmd.Text(t, _, _) => String.contains(substr = "P1", t)
            case _ => false
        }, cmds))
    }

    // -- initials and the table ----------------------------------------------------------

    def letters(word: String): Snapshot =
        Input.holding(String.toList(word) |> List.map(c -> Key.Other(Char.toBmpCodePoint(c))))

    /// A finished two-player game where player one earned a place.
    def qualified(): Session = {
        let s = twoPlayer();
        let scored = Vector.update(0, { phase = Phase.Lost, score = 2500 | Vector.get(0, s#worlds) },
                                   Vector.update(1, { phase = Phase.Lost | Vector.get(1, s#worlds) }, s#worlds));
        tick({ worlds = scored | s }, Input.empty())
    }

    @Test
    def testAQualifyingScoreAsksForInitials(): Unit \ Assert = {
        let asking = qualified();
        assertEq(expected = Screen.Entering, asking#screen);
        assertEq(expected = 1, List.length(asking#pending))
    }

    @Test
    def testTypingBuildsTheName(): Unit \ Assert = {
        let typed = tick(tick(tick(qualified(), letters("W")), letters("L")), letters("S"));
        assertEq(expected = "WLS", typed#typing)
    }

    @Test
    def testTheNameStopsAtThreeLetters(): Unit \ Assert = {
        let full = ticks(6, qualified(), letters("A"));
        assertEq(expected = Scores.nameLength(), String.length(full#typing))
    }

    @Test
    def testBackspaceCorrectsAMistake(): Unit \ Assert = {
        let typed = tick(tick(qualified(), letters("W")), letters("X"));
        assertEq(expected = "WX", typed#typing);
        assertEq(expected = "W", tick(typed, Input.holding(Key.Backspace :: Nil))#typing)
    }

    @Test
    def testEnterOnAnEmptyNameIsIgnored(): Unit \ Assert = {
        // Otherwise the table gains a blank row for anyone who leans on the key.
        let asking = qualified();
        assertEq(expected = Screen.Entering, tick(asking, Input.holding(Key.Enter :: Nil))#screen)
    }

    @Test
    def testCommittingRecordsTheScore(): Unit \ Assert = {
        let typed = tick(tick(tick(qualified(), letters("W")), letters("L")), letters("S"));
        let done = tick(typed, Input.holding(Key.Enter :: Nil));
        assertEq(expected = Screen.Table, done#screen);
        assertEq(expected = 1, List.length(done#scores));
        assertEq(expected = Some("WLS"), List.head(List.map(e -> e#name, done#scores)));
        assertEq(expected = 2500, Scores.best(done#scores))
    }

    @Test
    def testBothPlayersAreAskedInTurn(): Unit \ Assert = {
        // Two qualifying scores means two names, one after the other.
        let s = twoPlayer();
        let both = Vector.update(0, { phase = Phase.Lost, score = 900 | Vector.get(0, s#worlds) },
                   Vector.update(1, { phase = Phase.Lost, score = 800 | Vector.get(1, s#worlds) }, s#worlds));
        let asking = tick({ worlds = both | s }, Input.empty());
        assertEq(expected = 2, List.length(asking#pending));
        let first = tick(tick(asking, letters("A")), Input.holding(Key.Enter :: Nil));
        assertEq(expected = Screen.Entering, first#screen);
        assertEq(expected = 1, List.length(first#pending));
        let second = tick(tick(first, letters("B")), Input.holding(Key.Enter :: Nil));
        assertEq(expected = Screen.Table, second#screen);
        assertEq(expected = 2, List.length(second#scores))
    }

    @Test
    def testAKnownHighScoreShowsDuringPlay(): Unit \ Assert = {
        // The HI-SCORE slot should show the table's best, not zero, from the first tick.
        let withTable = Session.withScores(2026i64, { name = "ZZZ", score = 5000, level = 3 } :: Nil);
        assertEq(expected = 5000, Session.active(tick(withTable, digit(1)))#hiScore)
    }

    @Test
    def testAGameEndsOnItsOwnScreen(): Unit \ Assert = {
        // Without a beat here, a player's game ended on one frame and whatever came next
        // started on the following one, so nobody ever saw how their own game finished.
        let s = twoPlayer();
        let onLastLife = { worlds = Vector.update(0, { lives = 1 | Vector.get(0, s#worlds) },
                                                  s#worlds) | s };
        let ended = ticks(Rules.deathPauseTicks() + 2, aboutToDie(onLastLife), Input.empty());
        assertTrueWithMsg(ended#over > 0, "the game ended without a GAME OVER screen");
        assertTrueWithMsg(List.memberOf("GAME OVER", texts(ended)),
            "the game-over screen does not say so: ${texts(ended)}");

        // It belongs to the player who just lost, not the one about to start.
        assertEq(expected = 0, ended#current);
        assertEq(expected = 0, ended#handover)
    }

    @Test
    def testNothingMovesWhileTheEndingIsOnScreen(): Unit \ Assert = {
        let waiting = { over = Rules.gameOverTicks(), screen = Screen.Playing | twoPlayer() };
        let before = Session.active(waiting)#tick;
        let later = ticks(30, waiting, Input.holding(Key.Space :: Key.Enter :: Nil));
        assertEq(expected = before, Session.active(later)#tick);
        assertEq(expected = Rules.gameOverTicks() - 30, later#over)
    }

    @Test
    def testTheEndingIsAnnouncedOnlyOnce(): Unit \ Assert = {
        // `View` announces the end of a game when it stands alone, because there is nobody
        // else to do it. In the cabinet the session draws its own, and both drawing it put
        // two GAME OVERs on the screen with an invitation to press a key the cabinet had
        // already taken charge of.
        let waiting = { over = Rules.gameOverTicks(), screen = Screen.Playing | twoPlayer() };
        let shown = texts(waiting);
        assertEq(expected = 1, List.count(t -> t == "GAME OVER", shown));
        assertTrueWithMsg(not List.exists(t -> String.contains(substr = "PLAY AGAIN", t), shown),
            "the cabinet is telling the player to press enter to play again: ${shown}")
    }

    @Test
    def testPlayerTwoGetsABeatBeforeTheirGameStarts(): Unit \ Assert = {
        // Handing straight over meant player two's first life began while they were still
        // reading player one's score.
        let s = twoPlayer();
        let onLastLife = { worlds = Vector.update(0, { lives = 1 | Vector.get(0, s#worlds) },
                                                  s#worlds) | s };
        let handedOver = ticks(Rules.deathPauseTicks() + Rules.gameOverTicks() + 3,
                               aboutToDie(onLastLife), Input.empty());
        assertEq(expected = 1, handedOver#current);
        assertTrueWithMsg(handedOver#handover > 0,
            "player two's game started the instant player one's ended")
    }

    @Test
    def testTheGameIsFrozenWhileTheNextPlayerGetsReady(): Unit \ Assert = {
        // Whatever they do with the controls during the count must not reach the game.
        let waiting = { handover = Rules.handoverTicks(), screen = Screen.Playing | twoPlayer() };
        let before = Session.active(waiting)#tick;
        let later = ticks(30, waiting, Input.holding(Key.Space :: Key.Left :: Nil));
        assertEq(expected = before, Session.active(later)#tick);
        assertEq(expected = Rules.handoverTicks() - 30, later#handover)
    }

    @Test
    def testTheCountdownRunsThenPlayBegins(): Unit \ Assert = {
        let waiting = { handover = Rules.handoverTicks(), current = 1,
                        screen = Screen.Playing | twoPlayer() };
        let shown = texts(waiting);
        assertTrueWithMsg(List.memberOf("PLAYER 2", shown), "the incoming player is not named: ${shown}");
        assertTrueWithMsg(List.memberOf("${Rules.countdownSteps()}", shown),
            "no countdown on the hand-over screen: ${shown}");
        // ...and once it runs out the game is live again.
        let live = ticks(Rules.handoverTicks() + 2, waiting, Input.empty());
        assertEq(expected = 0, live#handover);
        assertTrue(Session.active(live)#tick > Session.active(waiting)#tick)
    }

    @Test
    def testTheGetReadyTextSitsOnADimmedPanel(): Unit \ Assert = {
        // Plain text over a formation is hard to read at a glance; the title screen solved
        // that with a translucent panel sized to the words, and this uses the same one.
        let waiting = { handover = Rules.handoverTicks(), current = 1,
                        screen = Screen.Playing | twoPlayer() };
        let dimmed = Canvas.commands((640, 480), () -> Screens.render(waiting, Stats.empty()))
            |> List.exists(cmd -> match cmd {
                case DrawCmd.FillAlpha(_, _) => true
                case _ => false
            });
        assertTrueWithMsg(dimmed, "the get-ready text is drawn straight onto the game");

        // ...and it is not there once play begins.
        let live = { handover = 0 | waiting };
        let plain = Canvas.commands((640, 480), () -> Screens.render(live, Stats.empty()))
            |> List.exists(cmd -> match cmd {
                case DrawCmd.FillAlpha(_, _) => true
                case _ => false
            });
        assertFalseWithMsg(plain, "the panel is still up after the count finished")
    }

    @Test
    def testANameMayContainDigits(): Unit \ Assert = {
        // `Scores.clean` has always accepted A-Z and 0-9 on the way in from a file, so a
        // hand-edited table could hold a name the game would not let you type.
        let asking = { screen = Screen.Entering,
                       pending = { player = 0, entry = { name = "", score = 5000, level = 4 } } :: Nil
                     | tick(start(), digit(1)) };
        let typed = ticks(1, asking, Input.holding(Key.Other(87) :: Nil))   // W
            |> (s1 -> ticks(1, s1, Input.holding(Key.Other(51) :: Nil)))    // 3
            |> (s2 -> ticks(1, s2, Input.holding(Key.Other(83) :: Nil)));   // S
        assertEq(expected = "W3S", typed#typing)
    }

    @Test
    def testADigitNameIsRecordedAsTyped(): Unit \ Assert = {
        let asking = { screen = Screen.Entering, typing = "R2D",
                       pending = { player = 0, entry = { name = "", score = 5000, level = 4 } } :: Nil
                     | tick(start(), digit(1)) };
        let done = ticks(1, asking, Input.holding(Key.Enter :: Nil));
        assertEq(expected = Some("R2D"), Option.map(e -> e#name, List.head(done#scores)))
    }

    @Test
    def testTheInitialsPromptSaysWhoseTheyAre(): Unit \ Assert = {
        // Two qualifying players get two prompts back to back. Without a name on them they
        // are indistinguishable, and the second reads as the first having gone wrong.
        let base = twoPlayer();
        let asking = { screen = Screen.Entering,
                       pending = { player = 0, entry = { name = "", score = 5000, level = 4 } } ::
                                 { player = 1, entry = { name = "", score = 3130, level = 3 } } :: Nil
                     | base };
        assertTrueWithMsg(List.memberOf("PLAYER 1", texts(asking)),
            "the first prompt does not say whose it is: ${texts(asking)}");

        // Committing the first moves on to the second, which must name the other player.
        let second = ticks(1, { typing = "ABC" | asking }, Input.holding(Key.Enter :: Nil));
        assertTrueWithMsg(List.memberOf("PLAYER 2", texts(second)),
            "the second prompt still names player one: ${texts(second)}")
    }

    @Test
    def testASinglePlayerIsNotToldWhoTheyAre(): Unit \ Assert = {
        // With one candidate there is nothing to disambiguate, and naming them is noise.
        let solo = tick(start(), digit(1));
        let asking = { screen = Screen.Entering,
                       pending = { player = 0, entry = { name = "", score = 5000, level = 4 } } :: Nil
                     | solo };
        assertFalseWithMsg(List.memberOf("PLAYER 1", texts(asking)),
            "a one-player game is being told which player it is")
    }

    @Test
    def testTheRecordedNameGoesToTheRightScore(): Unit \ Assert = {
        // The player number is display only -- what gets written must still be the score the
        // prompt was showing.
        let base = twoPlayer();
        let asking = { screen = Screen.Entering, typing = "WLS",
                       pending = { player = 1, entry = { name = "", score = 3130, level = 3 } } :: Nil
                     | base };
        let done = ticks(1, asking, Input.holding(Key.Enter :: Nil));
        assertEq(expected = Some(3130), Option.map(e -> e#score, List.head(done#scores)));
        assertEq(expected = Some("WLS"), Option.map(e -> e#name, List.head(done#scores)))
    }

    @Test
    def testTheInitialsPromptShowsThePlayersGameNotTheDemo(): Unit \ Assert = {
        // Reported from a screenshot: the HUD read 0090 while the banner above it announced a
        // new high score in the thousands. Both numbers were real -- the banner was the
        // player's and the HUD was the *demo's*, because the initials screen was drawing the
        // attract game behind it.
        let base = twoPlayer();
        let played = { worlds = Vector.update(0, { score = 7310, hiScore = 7310 | Vector.get(0, base#worlds) },
                                              base#worlds),
                       demo = { score = 90, hiScore = 90 | base#demo },
                       screen = Screen.Entering,
                       pending = { player = 0, entry = { name = "", score = 7310, level = 5 } } :: Nil | base };
        let shown = texts(played);
        assertTrueWithMsg(List.memberOf(View.scoreText(7310), shown),
            "the player's score is not on the screen that is asking for their initials: ${shown}");
        assertTrueWithMsg(not List.memberOf(View.scoreText(90), shown),
            "the demo's score is being shown to the player instead: ${shown}")
    }

    @Test
    def testTheInitialsPromptStillShowsBothPlayers(): Unit \ Assert = {
        // A two-player game has to keep both scores up while the second is typing.
        let base = twoPlayer();
        let both = { worlds = Vector.update(0, { score = 4400 | Vector.get(0, base#worlds) },
                             Vector.update(1, { score = 2200 | Vector.get(1, base#worlds) }, base#worlds)),
                     current = 1,
                     screen = Screen.Entering,
                     pending = { player = 1, entry = { name = "", score = 2200, level = 3 } } :: Nil | base };
        let shown = texts(both);
        assertTrue(List.memberOf(View.scoreText(2200), shown));
        assertTrueWithMsg(List.memberOf(View.scoreText(4400), shown),
            "player one's score vanished while player two typed: ${shown}")
    }

    @Test
    def testTheTableScreenListsTheNames(): Unit \ Assert = {
        let withTable = Session.withScores(2026i64, { name = "ABC", score = 4321, level = 2 } :: Nil);
        let showing = { screen = Screen.Table | withTable };
        let cmds = Canvas.commands((640, 480), () -> Screens.render(showing, Stats.empty()));
        let says = needle -> List.exists(cmd -> match cmd {
            case DrawCmd.Text(t, _, _) => String.contains(substr = needle, t)
            case _ => false
        }, cmds);
        assertTrue(says("ABC"));
        assertTrue(says("4321"))
    }

}
