mod TestAnimation {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertNeq

    def ball(x: Float32, y: Float32, dx: Float32, dy: Float32): Ball =
        { x = x, y = y, dx = dx, dy = dy, radius = 10.0f32, tint = Color.white() }

    def worldOf(b: Ball): Bouncing =
        { balls = b :: Nil, nudge = 0.0f32 }

    def only(w: Bouncing): Ball =
        match List.head(w#balls) {
            case Some(b) => b
            case None => ball(0.0f32, 0.0f32, 0.0f32, 0.0f32)
        }

    def stepTimes(n: Int32, w: Bouncing, snapshot: Snapshot): Bouncing =
        if (n <= 0) w else stepTimes(n - 1, Animation.step(w, snapshot), snapshot)

    @Test
    def testBallMovesByItsVelocity(): Unit \ Assert = {
        let after = only(Animation.step(worldOf(ball(100.0f32, 100.0f32, 2.0f32, 3.0f32)), Input.empty()));
        assertEq(expected = 102.0f32, after#x);
        assertEq(expected = 103.0f32, after#y)
    }

    @Test
    def testBallBouncesOffTheRightWall(): Unit \ Assert = {
        let start = ball(Animation.fieldWidth() - 10.0f32, 100.0f32, 5.0f32, 0.0f32);
        let after = only(Animation.step(worldOf(start), Input.empty()));
        assertEq(expected = Animation.fieldWidth() - 10.0f32, after#x);
        assertTrue(after#dx < 0.0f32)
    }

    @Test
    def testBallBouncesOffTheLeftWall(): Unit \ Assert = {
        let after = only(Animation.step(worldOf(ball(10.0f32, 100.0f32, -5.0f32, 0.0f32)), Input.empty()));
        assertEq(expected = 10.0f32, after#x);
        assertTrue(after#dx > 0.0f32)
    }

    @Test
    def testBallBouncesOffTheTopAndBottom(): Unit \ Assert = {
        let top = only(Animation.step(worldOf(ball(100.0f32, 10.0f32, 0.0f32, -5.0f32)), Input.empty()));
        assertEq(expected = 10.0f32, top#y);
        assertTrue(top#dy > 0.0f32);

        let low = ball(100.0f32, Animation.fieldHeight() - 10.0f32, 0.0f32, 5.0f32);
        let bottom = only(Animation.step(worldOf(low), Input.empty()));
        assertEq(expected = Animation.fieldHeight() - 10.0f32, bottom#y);
        assertTrue(bottom#dy < 0.0f32)
    }

    @Test
    def testBallNeverEscapesTheField(): Unit \ Assert = {
        // A ball moving faster than the wall is thick must not tunnel through or get stuck
        // outside flipping its velocity every frame.
        def loop(n, w) =
            if (n <= 0) ()
            else {
                let b = only(w);
                Assert.assertTrueWithMsg(
                    b#x >= b#radius and b#x <= Animation.fieldWidth() - b#radius,
                    "x escaped: ${b#x}");
                Assert.assertTrueWithMsg(
                    b#y >= b#radius and b#y <= Animation.fieldHeight() - b#radius,
                    "y escaped: ${b#y}");
                loop(n - 1, Animation.step(w, Input.empty()))
            };
        loop(2000, worldOf(ball(100.0f32, 100.0f32, 37.0f32, 29.0f32)))
    }

    @Test
    def testArrowKeysNudgeSideways(): Unit \ Assert = {
        let start = worldOf(ball(300.0f32, 100.0f32, 0.0f32, 0.0f32));
        let right = only(Animation.step(start, Input.holding(Key.Right :: Nil)));
        let left = only(Animation.step(start, Input.holding(Key.Left :: Nil)));
        assertTrue(right#dx > 0.0f32);
        assertTrue(left#dx < 0.0f32)
    }

    @Test
    def testOppositeArrowsCancel(): Unit \ Assert = {
        let start = worldOf(ball(300.0f32, 100.0f32, 1.0f32, 0.0f32));
        let after = only(Animation.step(start, Input.holding(Key.Left :: Key.Right :: Nil)));
        assertEq(expected = 1.0f32, after#dx)
    }

    @Test
    def testNoInputMeansNoNudge(): Unit \ Assert = {
        let after = Animation.step(worldOf(ball(300.0f32, 100.0f32, 1.0f32, 0.0f32)), Input.empty());
        assertEq(expected = 0.0f32, after#nudge)
    }

    @Test
    def testSameSeedGivesTheSameWorld(): Unit \ Assert = {
        let script = Input.holding(Key.Right :: Nil);
        let a = stepTimes(300, Animation.initial(7i64), script);
        let b = stepTimes(300, Animation.initial(7i64), script);
        assertEq(expected = List.map(x -> x#x, a#balls), List.map(x -> x#x, b#balls));
        assertEq(expected = List.map(x -> x#y, a#balls), List.map(x -> x#y, b#balls))
    }

    @Test
    def testDifferentSeedsGiveDifferentWorlds(): Unit \ Assert =
        assertNeq(unexpected = List.map(b -> b#x, Animation.initial(7i64)#balls),
                  List.map(b -> b#x, Animation.initial(8i64)#balls))

    @Test
    def testViewDrawsOneEllipsePerBall(): Unit \ Assert = {
        // Rendering checked as data: no window, no IO.
        let cmds = Canvas.commands((640, 480), () -> Animation.view(Animation.initial(1i64)));
        let ellipses = List.count(cmd -> match cmd {
            case DrawCmd.Ellipse(_, _, _, _) => true
            case _ => false
        }, cmds);
        assertEq(expected = 4, ellipses)
    }

    @Test
    def testViewClearsTheBackgroundFirst(): Unit \ Assert = {
        let cmds = Canvas.commands((640, 480), () -> Animation.view(Animation.initial(1i64)));
        match List.head(cmds) {
            case Some(DrawCmd.Clear(_)) => Assert.success("cleared first")
            case other => Assert.fail("expected a Clear first, got ${other}")
        }
    }

    // -- ball-to-ball collisions ------------------------------------------------------

    def worldOfTwo(a: Ball, b: Ball): Bouncing =
        { balls = a :: b :: Nil, nudge = 0.0f32 }

    def at(index: Int32, w: Bouncing): Ball =
        match List.nth(index, w#balls) {
            case Some(b) => b
            case None => ball(0.0f32, 0.0f32, 0.0f32, 0.0f32)
        }

    def separation(w: Bouncing): Float32 = {
        let a = at(0, w);
        let b = at(1, w);
        Float32.pow(base = (b#x - a#x) * (b#x - a#x) + (b#y - a#y) * (b#y - a#y), 0.5f32)
    }

    @Test
    def testHeadOnCollisionExchangesVelocities(): Unit \ Assert = {
        // Equal masses meeting head-on swap their speeds; that is the defining property.
        let a = ball(300.0f32, 240.0f32, 4.0f32, 0.0f32);
        let b = ball(320.0f32, 240.0f32, -4.0f32, 0.0f32);
        let after = Animation.step(worldOfTwo(a, b), Input.empty());
        assertTrue(at(0, after)#dx < 0.0f32);
        assertTrue(at(1, after)#dx > 0.0f32)
    }

    @Test
    def testCollisionPushesOverlappingBallsApart(): Unit \ Assert = {
        // Start them badly overlapped; one step must separate them to at least touching.
        let a = ball(300.0f32, 240.0f32, 0.0f32, 0.0f32);
        let b = ball(305.0f32, 240.0f32, 0.0f32, 0.0f32);
        let after = Animation.step(worldOfTwo(a, b), Input.empty());
        let touching = at(0, after)#radius + at(1, after)#radius;
        Assert.assertTrueWithMsg(separation(after) >= touching - 0.01f32,
            "still overlapping: ${separation(after)} < ${touching}")
    }

    @Test
    def testBallsMovingApartAreNotFlipped(): Unit \ Assert = {
        // Overlapping but already separating: they must be unstuck, not bounced again.
        // Without this guard a pair vibrates in place forever.
        let a = ball(300.0f32, 240.0f32, -3.0f32, 0.0f32);
        let b = ball(310.0f32, 240.0f32, 3.0f32, 0.0f32);
        let after = Animation.step(worldOfTwo(a, b), Input.empty());
        assertTrue(at(0, after)#dx < 0.0f32);
        assertTrue(at(1, after)#dx > 0.0f32)
    }

    @Test
    def testDistantBallsDoNotInteract(): Unit \ Assert = {
        let a = ball(100.0f32, 240.0f32, 1.0f32, 0.0f32);
        let b = ball(500.0f32, 240.0f32, -1.0f32, 0.0f32);
        let after = Animation.step(worldOfTwo(a, b), Input.empty());
        assertEq(expected = 1.0f32, at(0, after)#dx);
        assertEq(expected = -1.0f32, at(1, after)#dx)
    }

    @Test
    def testCollisionConservesMomentum(): Unit \ Assert = {
        // Equal masses, so the sum of the velocities is unchanged by the exchange.
        let a = ball(300.0f32, 240.0f32, 5.0f32, 2.0f32);
        let b = ball(322.0f32, 244.0f32, -3.0f32, -1.0f32);
        let before = 5.0f32 + -3.0f32;
        let after = Animation.step(worldOfTwo(a, b), Input.empty());
        let total = at(0, after)#dx + at(1, after)#dx;
        Assert.assertTrueWithMsg(Float32.abs(total - before) < 0.001f32,
            "momentum changed: ${before} -> ${total}")
    }

    @Test
    def testGlancingBlowKeepsThemMoving(): Unit \ Assert = {
        // Only the velocity along the line of centres is exchanged, so a glancing hit
        // deflects rather than stopping either ball.
        let a = ball(300.0f32, 240.0f32, 4.0f32, 0.0f32);
        let b = ball(326.0f32, 258.0f32, 4.0f32, 0.0f32);
        let after = Animation.step(worldOfTwo(a, b), Input.empty());
        assertTrue(at(0, after)#dx > 0.0f32 or at(0, after)#dy != 0.0f32);
        assertTrue(at(1, after)#dx > 0.0f32 or at(1, after)#dy != 0.0f32)
    }

    @Test
    def testBallsNeverOverlapOverALongRun(): Unit \ Assert = {
        def loop(n, w) =
            if (n <= 0) ()
            else {
                let touching = at(0, w)#radius + at(1, w)#radius;
                Assert.assertTrueWithMsg(separation(w) >= touching - 0.5f32,
                    "balls overlapped: ${separation(w)} < ${touching}");
                loop(n - 1, Animation.step(w, Input.empty()))
            };
        let a = ball(200.0f32, 240.0f32, 7.0f32, 3.0f32);
        let b = ball(400.0f32, 250.0f32, -5.0f32, -2.0f32);
        loop(1500, worldOfTwo(a, b))
    }

    @Test
    def testCollisionsKeepBallsInsideTheField(): Unit \ Assert = {
        // A collision resolves positions after the wall bounce, so the field clamp has to
        // come last or a ball can be shoved through a wall.
        def loop(n, w) =
            if (n <= 0) ()
            else {
                List.forEach(b -> {
                    Assert.assertTrueWithMsg(
                        b#x >= b#radius and b#x <= Animation.fieldWidth() - b#radius,
                        "x escaped after a collision: ${b#x}");
                    Assert.assertTrueWithMsg(
                        b#y >= b#radius and b#y <= Animation.fieldHeight() - b#radius,
                        "y escaped after a collision: ${b#y}")
                }, w#balls);
                loop(n - 1, Animation.step(w, Input.empty()))
            };
        loop(1500, Animation.initial(4i64))
    }

    @Test
    def testSpawnedBallsDoNotOverlap(): Unit \ Assert = {
        // If they started overlapped the first frame would show them jumping apart.
        let balls = List.toVector(Animation.initial(3i64)#balls);
        let count = Vector.length(balls);
        def inner(i, j) =
            if (j >= count) ()
            else {
                let a = Vector.get(i, balls);
                let b = Vector.get(j, balls);
                let d = Float32.pow(base = (b#x - a#x) * (b#x - a#x) + (b#y - a#y) * (b#y - a#y), 0.5f32);
                Assert.assertTrueWithMsg(d >= a#radius + b#radius,
                    "balls ${i} and ${j} spawned overlapping: ${d}");
                inner(i, j + 1)
            };
        def outer(i) = if (i >= count) () else { inner(i, i + 1); outer(i + 1) };
        outer(0)
    }

    // -- mass ------------------------------------------------------------------------

    def ballR(x: Float32, y: Float32, dx: Float32, dy: Float32, r: Float32): Ball =
        { x = x, y = y, dx = dx, dy = dy, radius = r, tint = Color.white() }

    /// Mass goes with area, matching the sketch.
    def massOf(b: Ball): Float64 = Float32.toFloat64(b#radius * b#radius)

    def momentumX(w: Bouncing): Float64 =
        List.foldLeft((acc, b) -> acc + massOf(b) * Float32.toFloat64(b#dx), 0.0, w#balls)

    def kineticEnergy(w: Bouncing): Float64 =
        List.foldLeft((acc, b) -> {
            let vx = Float32.toFloat64(b#dx);
            let vy = Float32.toFloat64(b#dy);
            acc + massOf(b) * (vx * vx + vy * vy)
        }, 0.0, w#balls)

    /// A heavy ball overlapping a light one, closing head-on.
    def heavyMeetsLight(): Bouncing =
        worldOfTwo(ballR(300.0f32, 240.0f32, 4.0f32, 0.0f32, 30.0f32),
                   ballR(338.0f32, 240.0f32, -4.0f32, 0.0f32, 10.0f32))

    @Test
    def testHeavyBallIsDeflectedLessThanLightBall(): Unit \ Assert = {
        let before = heavyMeetsLight();
        let after = Animation.step(before, Input.empty());
        let heavyChange = Float32.abs(at(0, after)#dx - at(0, before)#dx);
        let lightChange = Float32.abs(at(1, after)#dx - at(1, before)#dx);
        Assert.assertTrueWithMsg(lightChange > heavyChange * 3.0f32,
            "expected the light ball to be thrown much harder: heavy ${heavyChange}, light ${lightChange}")
    }

    @Test
    def testHeavyBallKeepsGoingForwards(): Unit \ Assert = {
        // A 9x heavier ball is not turned around by the one it hits -- it shoves it aside.
        let after = Animation.step(heavyMeetsLight(), Input.empty());
        assertTrue(at(0, after)#dx > 0.0f32);
        assertTrue(at(1, after)#dx > 0.0f32);
        assertTrue(at(1, after)#dx > at(0, after)#dx)
    }

    @Test
    def testUnequalMassCollisionConservesMomentum(): Unit \ Assert = {
        let before = heavyMeetsLight();
        let after = Animation.step(before, Input.empty());
        let drift = Float64.abs(momentumX(after) - momentumX(before));
        Assert.assertTrueWithMsg(drift < 1.0,
            "momentum drifted by ${drift}: ${momentumX(before)} -> ${momentumX(after)}")
    }

    @Test
    def testElasticCollisionConservesKineticEnergy(): Unit \ Assert = {
        // "Elastic" is exactly this property. A sign or divisor slip in the impulse shows
        // up here even when momentum still looks right.
        let before = heavyMeetsLight();
        let after = Animation.step(before, Input.empty());
        let drift = Float64.abs(kineticEnergy(after) - kineticEnergy(before));
        Assert.assertTrueWithMsg(drift < kineticEnergy(before) * 0.001,
            "energy changed: ${kineticEnergy(before)} -> ${kineticEnergy(after)}")
    }

    @Test
    def testLighterBallGivesWayWhenSeparating(): Unit \ Assert = {
        // Two stationary overlapping balls are pushed apart, and the lighter one moves the
        // larger share of the distance.
        let heavy = ballR(300.0f32, 240.0f32, 0.0f32, 0.0f32, 30.0f32);
        let light = ballR(320.0f32, 240.0f32, 0.0f32, 0.0f32, 10.0f32);
        let after = Animation.step(worldOfTwo(heavy, light), Input.empty());
        let heavyMoved = Float32.abs(at(0, after)#x - heavy#x);
        let lightMoved = Float32.abs(at(1, after)#x - light#x);
        Assert.assertTrueWithMsg(lightMoved > heavyMoved,
            "expected the lighter ball to give way: heavy moved ${heavyMoved}, light moved ${lightMoved}")
    }

    @Test
    def testEqualMassesStillExchangeVelocities(): Unit \ Assert = {
        // The mass-weighted impulse must reduce to a plain swap when the masses match.
        let a = ballR(300.0f32, 240.0f32, 5.0f32, 0.0f32, 15.0f32);
        let b = ballR(328.0f32, 240.0f32, -2.0f32, 0.0f32, 15.0f32);
        let after = Animation.step(worldOfTwo(a, b), Input.empty());
        Assert.assertTrueWithMsg(Float32.abs(at(0, after)#dx - -2.0f32) < 0.001f32,
            "expected -2.0, got ${at(0, after)#dx}");
        Assert.assertTrueWithMsg(Float32.abs(at(1, after)#dx - 5.0f32) < 0.001f32,
            "expected 5.0, got ${at(1, after)#dx}")
    }

}
