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
/// One occupied column of the formation: its lowest invader, and how deep it is.
pub type alias Column = { x = Float32, y = Float32, depth = Int32 }

///
/// Every number that decides how the demo player behaves.
///
/// A record rather than sixteen `def`s, because they were sixteen `def`s and every one of them
/// had to be found, edited and recompiled to try a different value. As data they can be varied
/// in a loop, read from a file, and searched -- see `bin/bench --recalc`.
///
/// None of them can be reasoned about in isolation. Widening `dangerWidth` from 30 to 60 cut
/// deaths sixfold; a cleverer dodge that predicted where the cannon would be when each bomb
/// landed measured worse at every setting. They are tuned by measurement, and the record of
/// that is in `docs/ARCHITECTURE.md`.
///
pub type alias Tuning = {
    aimJitter = Int32,
    judgeFor = Int32,
    judgeSpread = Int32,
    lapseOneIn = Int32,
    lapseFor = Int32,
    lapseSpread = Int32,
    startAt = Float32,
    reverseAt = Float32,
    dangerWidth = Float32,
    selfPreservation = Float32,
    urgency = Float32,
    shelterRelief = Float32,
    blockedCost = Float32,
    calm = Float32,
    stragglers = Int32,
    finishFlank = Float32,
    narrowTo = Float32,
    narrowing = Float32,
    fireWindow = Float32,
    imminence = Float32
}

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
    /// The tuning the game ships with.
    ///
    /// Every value here was measured, not chosen. The reasoning for each is below; the
    /// evidence is in `docs/ARCHITECTURE.md` and reproducible with `bin/bench`.
    ///
    pub def defaults(): Tuning = {
        // Small, because the error *persists* for a stretch of ticks. Drawn fresh every tick
        // it was self-cancelling noise averaging to nothing; held, the same number is a bias
        // the cannon acts on for half a second.
        aimJitter = 8,

        // How long it sticks with one judgement, and how much that varies. Re-judging every
        // tick is what made the cannon shake at six reversals a second.
        judgeFor = 18,
        judgeSpread = 19,

        // How often it stops watching, and for how long. A pause has to read as a hesitation
        // rather than a freeze -- and a third of a second of no input dies to a bomb.
        lapseOneIn = 200,
        lapseFor = 4,
        lapseSpread = 9,

        // How far off the mark before it starts walking, and before it turns round. Turning
        // costs more than starting, or the cannon chatters whenever it is nearly right.
        startAt = 1.5f32,
        reverseAt = 6.0f32,

        // How near a bomb must pass to count as a threat. At 30 the bot only reacted once a
        // bomb was nearly overhead, which at 4px of travel a tick against 3px of fall is far
        // too late. Sixty cut deaths across ten games from 24 to 4.
        dangerWidth = 60.0f32,

        // What one unit of danger is worth against being in position to shoot, and the
        // distance that costs as much as one unit of danger.
        selfPreservation = 6.0f32,
        urgency = 40.0f32,

        // A bunker overhead stops the bomb, but standing where it cannot shoot has to cost
        // something -- or the safest game is the one it loses without firing.
        shelterRelief = 0.25f32,
        blockedCost = 2.0f32,

        // Tidying the flanks pays only while there is a level left to spend the slower descent
        // on. Letting it continue to three-quarters of the way down costs a whole level.
        calm = 0.25f32,

        // Only a *finished* outer column moves the formation's edge, so one survivor is the
        // case worth taking. Extending to two drops the mean from 4.5 to 3.9.
        stragglers = 1,
        finishFlank = 1.1f32,

        // Narrowing the block is the only thing that buys time early, so an outer column is
        // worth taking for its own sake until the formation is down to `narrowTo` of its
        // starting width -- not merely when it is nearly empty, which is what `finishFlank`
        // covers. Over sixty seeds this is worth +0.4 levels (4.52 to 4.95), and it is the
        // largest single improvement the bot has had.
        //
        // The block's width sets how far it marches before it turns and drops, so clearing a
        // flank buys a permanently slower descent: 74 row drops per 10000 ticks becomes 58, and
        // the descent paid per invader killed falls 17%. It costs kill rate, which is why
        // chasing flanks *in general* measured worse -- the cutoff is what makes it pay.
        //
        // Both numbers are a plateau rather than a peak. Anything from 1.5 to 3.0 scores
        // 4.90-4.95 and every one of them beats not doing it at all, so this is a real effect
        // and not a value fitted to the sample. A cutoff of 0.50 or 0.75 gives most of it back:
        // the last few columns are where the width is worth the least and the invaders are
        // lowest, and that is exactly when the bot should be shooting whatever is about to land.
        narrowTo = 0.30f32,
        narrowing = 2.0f32,

        // How wide the "this shot will connect" window is, as a multiple of the exact
        // bullet-meets-invader overlap. One means only shots the geometry guarantees; five
        // means any target roughly overhead is worth a shot.
        //
        // Widened back when five shots could be aloft at once and a miss cost twelve ticks;
        // over sixty seeds it was the largest single gain the bot ever had, mean level 5.2 to
        // 6.0. One shot aloft inverts that economy -- a miss now costs the whole climb, about
        // sixty-eight ticks -- so this is retuned below against the same benchmark.
        //
        // A plateau, not a peak -- 3, 5, 7 and 10 all score 5.9 to 6.1 and every one beats
        // exact aiming, so this is a real effect rather than a value fitted to the sample.
        // Five sat in the middle of a plateau -- 3, 5, 7 and 10 all scored 5.9 to 6.1 -- and
        // firing unconditionally was never better even then, because a shot at empty sky
        // spends the flight the next real target needed. That penalty is now five times
        // larger.
        fireWindow = 5.0f32,

        // What a target's nearness to the invasion line is worth, against the tidiness of
        // clearing a flank. This was the priority the game itself set: sixty games in sixty
        // ended by invasion and none by running out of lives, so a descending column was the only
        // genuinely urgent thing on the screen.
        //
        // That premise no longer holds. With each wave starting lower than the last, eight of
        // ten games now end out of lives and only two by invasion -- a lower formation means
        // bombs fall a shorter way and there is less room to step aside. The weight below was
        // chosen against the old distribution and is very likely wrong for the new one, but
        // guessing at it is not an improvement: it wants the same sweep that produced it,
        // and that belongs with the wider bot work the one-shot rule already called for.
        //
        // It was 1 by construction and never chosen -- `nearness` is a fraction, so it topped
        // out at 1.0 while the flank bonuses reached 3.1 between them. `composure` rescued the
        // emergency by fading those bonuses once the formation was very low, but nothing acted
        // *before* the emergency: the bot kept tidying flanks until a column had passed 76% of
        // the way down, by which point there is no longer time to kill it. At 4 it switches at
        // 46%.
        //
        // The largest gain the bot has had: mean level 6.0 to 7.7, games reaching level seven
        // from 20 in 60 to 52, and the worst seed from 3 to 6 -- every game now clears level
        // six. A plateau, as usual: 3 through 10 all score 7.0 to 7.9. Four is where the worst
        // case peaks, and the worst case is what a demo is judged on.
        imminence = 4.0f32
    }

    /// The offsets from its current position that the bot considers standing at.
    def options(): List[Float32] =
        -96.0f32 :: -64.0f32 :: -36.0f32 :: -16.0f32 :: 0.0f32 ::
        16.0f32 :: 36.0f32 :: 64.0f32 :: 96.0f32 :: Nil

    ///
    /// What to shoot at.
    ///
    /// The saucer first when it is on screen -- it is worth up to 300 and a shield, which is
    /// what a human would go for. Otherwise the lowest living invader: it is the closest, and
    /// it is the one dropping bombs.
    ///
    def chooseTarget(t: Tuning, w: World): Option[Vec2] = match w#mystery {
        case Some(m) => Some({ x = m#x, y = Rules.mysteryY() })
        case None => bestColumn(t, w)
    }

    ///
    /// Every occupied column: its lowest invader, and how many are stacked in it.
    ///
    /// A shot rising through a column meets the lowest one in it first, so the lowest is the
    /// only reachable target there. The depth matters separately, below.
    ///
    def columns(w: World): List[Column] =
        Vector.foldLeft((acc, inv) ->
            if (not inv#alive) acc
            else Map.insertWith(arriving -> found -> {
                    let (newY, newN) = arriving;
                    let (oldY, oldN) = found;
                    (Float32.max(newY, oldY), newN + oldN)
                }, inv#pos#x, (inv#pos#y, 1), acc),
            (Map.empty(): Map[Float32, (Float32, Int32)]), w#invaders)
            |> Map.toList
            |> List.map(match (x, found) -> {
                let (y, depth) = found;
                { x = x, y = y, depth = depth }
            })

    ///
    /// Which column to shoot at.
    ///
    /// Lowest-first, with two exceptions, both of which trade kill rate for a slower descent.
    /// An outer column is worth taking while the formation is still wide, and worth finishing
    /// once it is nearly empty.
    ///
    /// `Game.liveBounds` measures the formation from its *living* invaders, so the last
    /// invader in the leftmost or rightmost column is single-handedly holding the block at its
    /// full width -- and the block's width is what decides how far it marches before it turns
    /// and drops. Left to itself the bot never takes that shot: the survivor is high up, so it
    /// scores badly on imminence, and the formation stays 400px wide from eleven columns down
    /// to six. One shot buys a permanent reduction in the descent rate, which is the best
    /// value on the board.
    ///
    /// `narrowing` is the same argument applied earlier: the whole outer column, not just its
    /// last survivor, while the block is still wider than `narrowTo`. Chasing flanks with no
    /// cutoff is measurably worse -- it costs more kill rate than it buys descent -- so what
    /// makes this pay is stopping. Below the cutoff the bonus goes away and the bot returns to
    /// shooting whatever is lowest.
    ///
    def bestColumn(t: Tuning, w: World): Option[Vec2] = {
        let candidates = columns(w);
        let edges = List.foldLeft((acc, c) -> match acc {
            case None => Some((c#x, c#x))
            case Some((left, right)) => Some((Float32.min(left, c#x), Float32.max(right, c#x)))
        }, None, candidates);
        match edges {
            case None => None
            case Some((left, right)) =>
                let looming = pressure(candidates);
                let spread = (right - left) / fullWidth();
                List.foldLeft((best, c) -> {
                    let score = columnWorth(t, c, left, right, spread, looming);
                    match best {
                        case None => Some(({ x = c#x, y = c#y }, score))
                        case Some((_, top)) =>
                            if (score > top) Some(({ x = c#x, y = c#y }, score)) else best
                    }
                }, None, candidates)
                    |> Option.map(fst)
        }
    }

    ///
    /// How wide the formation is when a level begins.
    ///
    /// Measured between the *centres* of the outer columns, which is what `liveBounds` reports,
    /// so the two are comparable.
    ///
    def fullWidth(): Float32 =
        Int32.toFloat32(Rules.columns() - 1) * Rules.columnSpacing()

    def columnWorth(t: Tuning, target: Column, left: Float32, right: Float32,
                    spread: Float32, looming: Float32): Float32 = {
        // Near 0 at the top of the formation, near 1 on the invasion line.
        let nearness = Float32.max(0.0f32, target#y) / Rules.playerY();
        let onAFlank = target#x == left or target#x == right;
        let nearlyDone = target#depth <= t#stragglers;
        let steady = composure(t, looming);
        let narrowing = if (spread > t#narrowTo) t#narrowing * steady else 0.0f32;
        let finishing = if (nearlyDone) t#finishFlank * steady else 0.0f32;
        t#imminence * nearness + (if (onAFlank) narrowing + finishing else 0.0f32)
    }

    ///
    /// How far down the formation has come: 0 at the top, 1 on the invasion line.
    ///
    def pressure(candidates: List[Column]): Float32 = {
        let deepest = List.foldLeft((low, c) -> Float32.max(low, c#y), 0.0f32, candidates);
        Float32.max(0.0f32, deepest) / Rules.invasionLine()
    }

    ///
    /// How much appetite there is for tidying up the flanks, given how low they have got.
    ///
    /// Finishing an outer column is a long game -- it pays back over the rest of the level --
    /// and there is no rest of the level once the front row is at the door. Past `t#calm` the
    /// bonus fades out, so the bot drops the housekeeping and clears the bottom row, which is
    /// both the thing about to land on it and the thing dropping the bombs.
    ///
    def composure(t: Tuning, looming: Float32): Float32 =
        if (looming < t#calm) 1.0f32
        else Float32.max(0.0f32, (1.0f32 - looming) / (1.0f32 - t#calm))




    ///
    /// How dangerous it is to stand at `x`.
    ///
    /// Every bomb still above the cannon contributes, weighted by how nearly overhead it is
    /// and how close it has got. Scoring positions rather than reacting to a single bomb is
    /// what stops the bot sidestepping out of one bomb's path and into another's -- which is
    /// how it kept dying with lives to spare.
    ///
    def danger(t: Tuning, x: Float32, w: World): Float32 =
        // A standing bunker overhead stops the bomb before it arrives, which is what bunkers
        // are for. Shelter is not total -- blocks are being eaten all game, and the bot should
        // not treat a two-block stub as a roof -- but it is worth most of a dodge.
        if (Bunkers.blocks(w#bunkers, x)) t#shelterRelief * rawDanger(t, x, w)
        else rawDanger(t, x, w)



    def rawDanger(t: Tuning, x: Float32, w: World): Float32 =
        List.foldLeft((total, b) ->
            if (b#y > Rules.playerY() or harmless(b, w)) total
            else {
                let across = Float32.abs(b#x - x);
                if (across > t#dangerWidth) total
                else {
                    // Near 0 up at the formation, near 1 just above the cannon: a bomb about
                    // to land matters far more than one just dropped.
                    let closeness = Float32.max(0.0f32, b#y) / Rules.playerY();
                    total + (1.0f32 - across / t#dangerWidth) * (0.3f32 + closeness)
                }
            }, 0.0f32, w#bombs)

    ///
    /// Whether the shield will still be up when this bomb arrives.
    ///
    /// Shooting the saucer buys ten seconds of immunity, and dodging through it wastes the
    /// prize -- that is time the cannon should spend standing under the formation and firing.
    /// Checked bomb by bomb rather than as a blanket "shielded, ignore everything", because
    /// the shield runs on a clock: one with twenty ticks left does nothing about a bomb that
    /// takes forty to land, and walking calmly into that would be a strange way to celebrate.
    ///
    def harmless(bomb: Bomb, w: World): Bool = {
        // Per kind: a dagger arrives in two thirds the time a wiggler does, so a shield that
        // covers one may not cover the other.
        let fall = (Rules.playerY() - bomb#y) / Rules.bombSpeedFor(bomb#kind);
        fall < Int32.toFloat32(w#shield)
    }

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
    def willConnect(t: Tuning, w: World): Bool = {
        // The formation's own drift, not the drift of whatever the bot happens to be aiming
        // at. When the saucer is the target that number describes the saucer, and projecting
        // the invaders by it answers a question about neither.
        let living = Vector.count(inv -> inv#alive, w#invaders);
        let drift = w#marchDir * Rules.marchSpeedFor(living, w#level);
        let overlap = t#fireWindow * (Rules.invaderSize()#x + Rules.bulletSize()#x) / 2.0f32;
        Vector.exists(
            inv -> { if (not inv#alive) false else {
                let flight = (Rules.playerY() - inv#pos#y) / Rules.bulletSpeed();
                if (flight <= 0.0f32) false else Float32.abs(inv#pos#x + drift * flight - w#playerX) < overlap
            } },
            w#invaders
        )
    }

    def worthFiring(t: Tuning, dx: Float32, w: World): Bool =
        // Never through its own shelter. The rules allow it -- carving a slit is legal, and in
        // the arcade original it is a tactic -- but a bot doing it by accident is spending
        // shots to demolish its own cover.
        if (Bunkers.obstructs(w#bunkers, w#playerX, Rules.bulletSize()#x)) false
        // The saucer crosses above the formation on its own path, so being lined up on it is
        // its own reason to fire; the formation is judged separately and always.
        else if (Option.isEmpty(w#mystery)) willConnect(t, w)
        else Float32.abs(dx) < 6.0f32 or willConnect(t, w)

    ///
    /// The best place to stand: safe first, in position second.
    ///
    def bestSpot(t: Tuning, aimX: Float32, w: World): Float32 = {
        let scored = List.map(offset -> {
            let x = onField(w#playerX + offset);
            (x, danger(t, x, w) * t#selfPreservation
                + Float32.abs(aimX - x) / t#urgency
                + (if (Bunkers.obstructs(w#bunkers, x, Rules.bulletSize()#x)) t#blockedCost else 0.0f32))
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
    def intent(t: Tuning, error: Float32, w: World): Option[{ goal = Float32, fire = Bool }] = {
        match chooseTarget(t, w) {
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
                Some({ goal = bestSpot(t, aimX, w) - w#playerX, fire = worthFiring(t, dx, w) })
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
    def wants(t: Tuning, goal: Float32): Int32 =
        if (goal < -t#startAt) -1 else if (goal > t#startAt) 1 else 0

    ///
    /// A competent player: perfect aim, and it dodges.
    ///
    /// Used by the balance test, where the point is to measure the *game* rather than the
    /// player. Its results are an optimistic bound -- a human misses.
    ///
    pub def aim(t: Tuning, w: World): Snapshot = match intent(t, 0.0f32, w) {
        case None => Input.empty()
        case Some(i) => keysFor(wants(t, i#goal), i#fire)
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
    pub def imperfect(t: Tuning, w: World, hand: Hand): (Snapshot, Hand) =
        if (hand#lapse > 0)
            // Still looking away. Hands off the controls until it comes back.
            (Input.empty(), { lapse = hand#lapse - 1, moving = 0 | hand })
        else {
            let (lapsing, afterChance) = Rng.chance(t#lapseOneIn, hand#rng);
            if (lapsing) {
                let (extra, next) = Rng.nextInt32Below(t#lapseSpread, afterChance);
                (Input.empty(), { rng = next, lapse = t#lapseFor + extra, moving = 0 | hand })
            } else {
                let (error, settled, next) = judge(t, hand, afterChance);
                match intent(t, error, w) {
                    case None =>
                        (Input.empty(), { rng = next, error = error, settled = settled, moving = 0 | hand })
                    case Some(i) => {
                        let moving = commit(t, hand#moving, i#goal);
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
    def judge(t: Tuning, hand: Hand, rng: Rng): (Float32, Int32, Rng) =
        if (hand#settled > 0) (hand#error, hand#settled - 1, rng)
        else {
            let (drawn, afterError) = Rng.nextInt32Below(2 * t#aimJitter + 1, rng);
            let (extra, afterHold) = Rng.nextInt32Below(t#judgeSpread, afterError);
            (Int32.toFloat32(drawn - t#aimJitter), t#judgeFor + extra, afterHold)
        }

    ///
    /// Which way to push, given which way it is already pushing.
    ///
    /// A hand already moving one way needs a real reason to go the other, so reversing takes a
    /// wider miss than starting does. The cannon still corrects an overshoot -- it covers 4px
    /// a tick, so it passes `reverseAt` within two ticks of going too far -- it just no longer
    /// twitches when it is nearly right.
    ///
    def commit(t: Tuning, moving: Int32, goal: Float32): Int32 = {
        let wanted = wants(t, goal);
        let reversing = wanted != 0 and moving != 0 and wanted != moving;
        if (reversing and Float32.abs(goal) < t#reverseAt) moving else wanted
    }

}
