///
/// A computer player.
///
/// This is the same code in two jobs. `aim` is the bot the balance test drives to decide
/// whether the game is winnable; `imperfect` is that bot with its hands shaking, which is
/// what plays behind the title screen. Having one implementation means the demo can never
/// drift away from the thing the tests measure.
///
/// Everything here is pure. The imperfection is threaded through an `Rng` the *caller* owns
/// -- never the world's own generator -- so watching the demo cannot perturb the determinism
/// the replay tests depend on.
///
mod Demo {

    /// How far the shaky bot's aim can be off, in pixels, either way.
    def aimJitter(): Int32 = 14

    /// Roughly one tick in this many, it does nothing at all.
    def idleOneIn(): Int32 = 9

    /// How close overhead a bomb has to be to count as a threat to a position.
    def dangerWidth(): Float32 = 30.0f32

    /// The offsets from its current position that the bot considers standing at.
    def options(): List[Float32] =
        -96.0f32 :: -64.0f32 :: -36.0f32 :: -16.0f32 :: 0.0f32 ::
        16.0f32 :: 36.0f32 :: 64.0f32 :: 96.0f32 :: Nil

    /// What one unit of danger is worth, against being in position to shoot.
    def selfPreservation(): Float32 = 4.0f32

    ///
    /// The distance, in pixels, that costs as much as one unit of danger.
    ///
    /// Sets the exchange rate between the two halves of the decision. Too high and the bot
    /// never leaves a shot; too low and it dodges so eagerly that the formation lands on it.
    ///
    def urgency(): Float32 = 40.0f32

    ///
    /// What to shoot at.
    ///
    /// The saucer first when it is on screen -- it is worth up to 300 and a shield, which is
    /// what a human would go for. Otherwise the lowest living invader: it is the closest, and
    /// it is the one dropping bombs.
    ///
    def chooseTarget(w: World): Option[Vec2] = match w#mystery {
        case Some(m) => Some({ x = m#x, y = Rules.mysteryY() })
        case None =>
            Vector.foldLeft((best, inv) ->
                if (not inv#alive) best
                else match best {
                    case None => Some(inv#pos)
                    case Some(p) => if (inv#pos#y > p#y) Some(inv#pos) else best
                }, None, w#invaders)
    }

    ///
    /// How dangerous it is to stand at `x`.
    ///
    /// Every bomb still above the cannon contributes, weighted by how nearly overhead it is
    /// and how close it has got. Scoring positions rather than reacting to a single bomb is
    /// what stops the bot sidestepping out of one bomb's path and into another's -- which is
    /// how it kept dying with lives to spare.
    ///
    def danger(x: Float32, w: World): Float32 =
        List.foldLeft((total, b) ->
            if (b#y > Rules.playerY()) total
            else {
                let across = Float32.abs(b#x - x);
                if (across > dangerWidth()) total
                else {
                    // Near 0 up at the formation, near 1 just above the cannon: a bomb about
                    // to land matters far more than one just dropped.
                    let closeness = Float32.max(0.0f32, b#y) / Rules.playerY();
                    total + (1.0f32 - across / dangerWidth()) * (0.3f32 + closeness)
                }
            }, 0.0f32, w#bombs)

    /// `x` clamped to somewhere the cannon can actually stand.
    def onField(x: Float32): Float32 = {
        let half = Rules.playerSize()#x / 2.0f32;
        if (x < half) half else if (x > Rules.fieldWidth() - half) Rules.fieldWidth() - half else x
    }

    ///
    /// Whether a shot fired now would hit something.
    ///
    /// Not just the chosen target: a shot that connects with any invader is a shot worth
    /// taking. Firing only when lined up on the target wasted every tick the cannon spent
    /// under some *other* column, and the formation landed while it was still being fussy.
    ///
    def worthFiring(dx: Float32, w: World): Bool = {
        let reach = Rules.invaderSize()#x / 2.0f32;
        Float32.abs(dx) < 6.0f32 or
            Vector.exists(inv -> inv#alive and Float32.abs(inv#pos#x - w#playerX) < reach, w#invaders)
    }

    ///
    /// The best place to stand: safe first, in position second.
    ///
    def bestSpot(aimX: Float32, w: World): Float32 = {
        let scored = List.map(offset -> {
            let x = onField(w#playerX + offset);
            (x, danger(x, w) * selfPreservation() + Float32.abs(aimX - x) / urgency())
        }, options());
        List.foldLeft((best, candidate) -> {
            let (x, score) = candidate;
            match best {
                case None => Some((x, score))
                case Some((_, bestScore)) => if (score < bestScore) Some((x, score)) else best
            }
        }, None, scored)
            |> Option.map(fst)
            |> Option.getWithDefault(w#playerX)
    }

    ///
    /// One tick of play, with `error` added to where the bot thinks the target is.
    ///
    /// The aim leads the target by the bullet's flight time: a bullet takes roughly forty
    /// ticks to reach the formation, and the invaders move most of their own width in that
    /// time. Aiming at where a target *is* rather than where it will *be* misses nearly
    /// every shot.
    ///
    def aimOffBy(error: Float32, w: World): Snapshot = {
        match chooseTarget(w) {
            case None => Input.empty()
            case Some(p) => {
                let living = Vector.count(inv -> inv#alive, w#invaders);
                let flight = (Rules.playerY() - p#y) / Rules.bulletSpeed();
                // The saucer crosses at its own speed; the formation marches at the rate the
                // rules derive from how many are left.
                let drift = match w#mystery {
                    case Some(m) => m#dir * Rules.mysterySpeed()
                    case None => w#marchDir * Rules.marchSpeedFor(living, w#level)
                };
                let dx = (p#x + drift * flight + error) - w#playerX;

                // Aiming and dodging are one decision, not two: score every place it could
                // stand by how dangerous it is and how far it is from the shot, and walk
                // towards the best. Treating them separately made the bot oscillate between
                // fleeing and lining up, and do neither well.
                let aimX = w#playerX + dx;
                let goal = bestSpot(aimX, w) - w#playerX;
                let move =
                    if (goal < -1.5f32) Key.Left :: Nil
                    else if (goal > 1.5f32) Key.Right :: Nil
                    else Nil;
                let fire = if (worthFiring(dx, w)) Key.Space :: Nil else Nil;
                Input.holding(List.append(move, fire))
            }
        }
    }

    ///
    /// A competent player: perfect aim, and it dodges.
    ///
    /// Used by the balance test, where the point is to measure the *game* rather than the
    /// player. Its results are an optimistic bound -- a human misses.
    ///
    pub def aim(w: World): Snapshot = aimOffBy(0.0f32, w)

    ///
    /// A fallible player: the same aim, blurred, and occasionally not paying attention.
    ///
    /// Perfect play makes a dull demo -- the formation evaporates in a straight line and
    /// nothing ever threatens the cannon. A little jitter and the odd idle tick make the
    /// attract screen look like somebody playing.
    ///
    /// Returns the advanced generator, so the caller keeps the demo's randomness entirely
    /// separate from the world's.
    ///
    pub def imperfect(w: World, rng: Rng): (Snapshot, Rng) = {
        let (distracted, afterIdle) = Rng.chance(idleOneIn(), rng);
        if (distracted) (Input.empty(), afterIdle)
        else {
            let (drawn, afterJitter) = Rng.nextInt32Below(2 * aimJitter() + 1, afterIdle);
            let error = Int32.toFloat32(drawn - aimJitter());
            (aimOffBy(error, w), afterJitter)
        }
    }

}
