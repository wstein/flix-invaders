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

    /// How close overhead a bomb has to be before the bot bothers to move.
    def dodgeWidth(): Float32 = 24.0f32

    /// How far it steps aside.
    def dodgeStep(): Float32 = 40.0f32

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
    /// The bomb most likely to land on the cannon, if one is close enough to worry about.
    ///
    /// "Closest" means lowest, not nearest in x: a bomb directly overhead but still up by the
    /// formation is less urgent than one about to arrive.
    ///
    def incoming(w: World): Option[Vec2] =
        List.foldLeft((best, b) ->
            if (b#y > Rules.playerY()) best
            else if (Float32.abs(b#x - w#playerX) > dodgeWidth()) best
            else match best {
                case None => Some(b)
                case Some(p) => if (b#y > p#y) Some(b) else best
            }, None, w#bombs)

    ///
    /// Where to stand to get out from under `bomb`, kept inside the field.
    ///
    def sidestep(bomb: Vec2, w: World): Float32 = {
        let half = Rules.playerSize()#x / 2.0f32;
        let away = if (bomb#x < w#playerX) w#playerX + dodgeStep() else w#playerX - dodgeStep();
        if (away < half) w#playerX + dodgeStep()
        else if (away > Rules.fieldWidth() - half) w#playerX - dodgeStep()
        else away
    }

    ///
    /// Where to shoot, given a horizontal error to add to the target.
    ///
    /// The lowest living invader is the target: it is the closest, and it is the one
    /// dropping bombs. The aim leads it by the bullet's flight time, because a bullet takes
    /// roughly forty ticks to reach the formation and the invaders move most of their own
    /// width in that time -- aiming at where a target *is* rather than where it will *be*
    /// misses nearly every shot.
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

                // Staying alive beats lining up a shot: if something is about to land on the
                // cannon, move out from under it and fire only if the aim happens to be good.
                let goal = match incoming(w) {
                    case Some(bomb) => sidestep(bomb, w) - w#playerX
                    case None => dx
                };
                let move =
                    if (goal < -1.5f32) Key.Left :: Nil
                    else if (goal > 1.5f32) Key.Right :: Nil
                    else Nil;
                let fire = if (Float32.abs(dx) < 6.0f32) Key.Space :: Nil else Nil;
                Input.holding(List.append(move, fire))
            }
        }
    }

    ///
    /// A competent player: perfect aim, no dodging.
    ///
    /// Used by the balance test, where the point is to measure the *game* rather than the
    /// player. It does not dodge, so its results are a floor -- a human who also dodges does
    /// better.
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
