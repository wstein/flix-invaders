///
/// The demo player's hand and attention.
///
/// State, because the things that make play look human are all things that persist. A person
/// misjudges a shot and *commits* to the misjudgement for a beat; they do not re-misjudge
/// sixty times a second. They keep pushing the stick the way it is already going. They look
/// away for a third of a second, not for a single frame.
///
/// The first version of this bot had none of that -- it drew a fresh aim error every tick,
/// which around the target swamped the 1.5px movement deadzone and reversed the cannon's
/// direction about six times a second. Measured, that was 9-11 reversals per 100 moving
/// ticks against 3 for the bot with no error at all: the shake was the jitter, not the game.
///
pub type alias Hand = {
    rng = Rng,
    error = Float32,
    settled = Int32,
    moving = Int32,
    lapse = Int32
}

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

    ///
    /// How far the shaky bot's aim can be off, in pixels, either way.
    ///
    /// Smaller than it looks, because the error now *persists* for a stretch of ticks. Drawn
    /// fresh every tick it was self-cancelling noise averaging to nothing; held, the same
    /// number is a genuine bias the cannon acts on for half a second. Widening it back out
    /// does not make the bot look more human, only worse at the game.
    ///
    def aimJitter(): Int32 = 8

    /// How long it sticks with one judgement of the shot, in ticks, and how much that varies.
    def judgeFor(): Int32 = 18
    def judgeSpread(): Int32 = 19

    ///
    /// Roughly one tick in this many it stops watching, and for how long when it does.
    ///
    /// A pause has to read as a hesitation rather than a freeze. Long lapses also cost lives
    /// outright -- a fifth of a second of no input is survivable, a third of a second with a
    /// bomb overhead is not.
    ///
    def lapseOneIn(): Int32 = 200
    def lapseFor(): Int32 = 4
    def lapseSpread(): Int32 = 9

    /// How far off the mark it must be to start walking, and to turn round once walking.
    ///
    /// Turning costs more than starting. Without the gap the cannon chatters between left and
    /// right whenever it sits near its target, because it moves 4px in a tick and the deadzone
    /// is narrower than that.
    def startAt(): Float32 = 1.5f32
    def reverseAt(): Float32 = 6.0f32

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
    def intent(error: Float32, w: World): Option[{ goal = Float32, fire = Bool }] = {
        match chooseTarget(w) {
            case None => None
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
                Some({ goal = bestSpot(aimX, w) - w#playerX, fire = worthFiring(dx, w) })
            }
        }
    }

    /// The keys for a committed direction and a decision to shoot.
    def keysFor(moving: Int32, fire: Bool): Snapshot = {
        let move =
            if (moving < 0) Key.Left :: Nil
            else if (moving > 0) Key.Right :: Nil
            else Nil;
        Input.holding(List.append(move, if (fire) Key.Space :: Nil else Nil))
    }

    /// Which way to walk, with no commitment to a previous direction.
    def wants(goal: Float32): Int32 =
        if (goal < -startAt()) -1 else if (goal > startAt()) 1 else 0

    ///
    /// A competent player: perfect aim, and it dodges.
    ///
    /// Used by the balance test, where the point is to measure the *game* rather than the
    /// player. Its results are an optimistic bound -- a human misses.
    ///
    pub def aim(w: World): Snapshot = match intent(0.0f32, w) {
        case None => Input.empty()
        case Some(i) => keysFor(wants(i#goal), i#fire)
    }

    /// A hand that has not played yet.
    pub def fresh(seed: Int64): Hand =
        { rng = Rng.fromSeed(seed), error = 0.0f32, settled = 0, moving = 0, lapse = 0 }

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
    pub def imperfect(w: World, hand: Hand): (Snapshot, Hand) =
        if (hand#lapse > 0)
            // Still looking away. Hands off the controls until it comes back.
            (Input.empty(), { lapse = hand#lapse - 1, moving = 0 | hand })
        else {
            let (lapsing, afterChance) = Rng.chance(lapseOneIn(), hand#rng);
            if (lapsing) {
                let (extra, next) = Rng.nextInt32Below(lapseSpread(), afterChance);
                (Input.empty(), { rng = next, lapse = lapseFor() + extra, moving = 0 | hand })
            } else {
                let (error, settled, next) = judge(hand, afterChance);
                match intent(error, w) {
                    case None =>
                        (Input.empty(), { rng = next, error = error, settled = settled, moving = 0 | hand })
                    case Some(i) => {
                        let moving = commit(hand#moving, i#goal);
                        (keysFor(moving, i#fire),
                         { rng = next, error = error, settled = settled, moving = moving | hand })
                    }
                }
            }
        }

    ///
    /// The misjudgement it is working from, re-drawn only when the last one has gone stale.
    ///
    /// Holding it is the whole point. Re-drawing every tick is what made the cannon shake.
    ///
    def judge(hand: Hand, rng: Rng): (Float32, Int32, Rng) =
        if (hand#settled > 0) (hand#error, hand#settled - 1, rng)
        else {
            let (drawn, afterError) = Rng.nextInt32Below(2 * aimJitter() + 1, rng);
            let (extra, afterHold) = Rng.nextInt32Below(judgeSpread(), afterError);
            (Int32.toFloat32(drawn - aimJitter()), judgeFor() + extra, afterHold)
        }

    ///
    /// Which way to push, given which way it is already pushing.
    ///
    /// A hand already moving one way needs a real reason to go the other, so reversing takes a
    /// wider miss than starting does. The cannon still corrects an overshoot -- it covers 4px
    /// a tick, so it passes `reverseAt` within two ticks of going too far -- it just no longer
    /// twitches when it is nearly right.
    ///
    def commit(moving: Int32, goal: Float32): Int32 = {
        let wanted = wants(goal);
        let reversing = wanted != 0 and moving != 0 and wanted != moving;
        if (reversing and Float32.abs(goal) < reverseAt()) moving else wanted
    }

}
