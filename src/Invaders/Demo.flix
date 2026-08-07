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
        let target = Vector.foldLeft((best, inv) ->
            if (not inv#alive) best
            else match best {
                case None => Some(inv#pos)
                case Some(p) => if (inv#pos#y > p#y) Some(inv#pos) else best
            }, None, w#invaders);
        match target {
            case None => Input.empty()
            case Some(p) => {
                let living = Vector.count(inv -> inv#alive, w#invaders);
                let flight = (Rules.playerY() - p#y) / Rules.bulletSpeed();
                let lead = w#marchDir * Rules.marchSpeedFor(living, w#level) * flight;
                let dx = (p#x + lead + error) - w#playerX;
                let move =
                    if (dx < -1.5f32) Key.Left :: Nil
                    else if (dx > 1.5f32) Key.Right :: Nil
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
