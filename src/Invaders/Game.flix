///
/// The rules of Invaders, as a pure function.
///
/// `step` takes a world and one input snapshot and returns the next world. It has no clock,
/// no window, and no `IO`, and its randomness is threaded through as data. That is what lets
/// the whole game be tested headlessly, and what makes an identical input script replay to an
/// identical world.
///
/// `step` is a pipeline of small stages. Each one is worth reading on its own, and each is
/// tested on its own.
///
mod Game {

    ///
    /// The formation at the start of a game.
    ///
    def formation(): Vector[Invader] =
        Vector.range(0, Rules.totalInvaders()) |> Vector.map(index -> {
            let column = Int32.remainder(index, Rules.columns());
            let row = index / Rules.columns();
            { pos = { x = Rules.formationLeft() + Int32.toFloat32(column) * Rules.columnSpacing(),
                      y = Rules.formationTop() + Int32.toFloat32(row) * Rules.rowSpacing() },
              alive = true,
              kind = Rules.kindForRow(row),
              row = row }
        })

    ///
    /// A fresh game. Pure, and identical for the same seed.
    ///
    pub def initial(seed: Int64): World =
        { phase = Phase.Playing,
          tick = 0,
          playerX = Rules.fieldWidth() / 2.0f32,
          bullets = Nil,
          bombs = Nil,
          invaders = formation(),
          bunkers = Bunkers.initial(),
          marchDir = 1.0f32,
          cooldown = 0,
          score = 0,
          lives = Rules.startingLives(),
          rng = Rng.fromSeed(seed),
          seed = seed,
          hiScore = 0,
          level = 1,
          pause = 0,
          blasts = Nil,
          mystery = None,
          mysteryTimer = Rules.mysteryInterval(),
          shield = 0,
          nextBonusAt = Rules.bonusLifeScore(),
          sounds = Nil,
          marchNote = 0,
          marchedSince = 0.0f32 }

    def clampTo(lo: Float32, hi: Float32, v: Float32): Float32 =
        if (v < lo) lo else if (v > hi) hi else v

    /// Records a sound for this tick.
    def emit(cmd: SoundCmd, w: World): World =
        { sounds = cmd :: w#sounds | w }

    // -- pipeline stages --------------------------------------------------------------

    /// Left and right move the player, who cannot leave the field.
    def movePlayer(input: Snapshot, w: World): World = {
        let left = if (Set.memberOf(Key.Left, input#held)) -Rules.playerSpeed() else 0.0f32;
        let right = if (Set.memberOf(Key.Right, input#held)) Rules.playerSpeed() else 0.0f32;
        let half = Rules.playerSize()#x / 2.0f32;
        { playerX = clampTo(half, Rules.fieldWidth() - half, w#playerX + left + right) | w }
    }

    /// Space fires, subject to the cooldown. Holding it down fires at a fixed rate.
    def fire(input: Snapshot, w: World): World =
        if (w#cooldown > 0) { cooldown = w#cooldown - 1 | w }
        else if (not Set.memberOf(Key.Space, input#held)) w
        else {
            let muzzle = { x = w#playerX, y = Rules.playerY() - Rules.playerSize()#y };
            emit(SoundCmd.Shoot, { bullets = muzzle :: w#bullets, cooldown = Rules.fireCooldown() | w })
        }

    /// Bullets rise and are dropped when they leave the top of the field.
    def moveBullets(w: World): World =
        { bullets = w#bullets
            |> List.map(b -> { y = b#y - Rules.bulletSpeed() | b })
            |> List.filter(b -> b#y > -Rules.bulletSize()#y) | w }

    /// Bombs fall and are dropped when they leave the bottom of the field.
    def moveBombs(w: World): World =
        { bombs = w#bombs
            |> List.map(b -> { y = b#y + Rules.bombSpeed() | b })
            |> List.filter(b -> b#y < Rules.fieldHeight() + Rules.bombSize()#y) | w }

    /// The x of the leftmost and rightmost living invader, if any are left.
    def liveBounds(invaders: Vector[Invader]): Option[(Float32, Float32)] =
        Vector.foldLeft((acc, inv) ->
            if (not inv#alive) acc
            else match acc {
                case None => Some((inv#pos#x, inv#pos#x))
                case Some((lo, hi)) =>
                    Some((Float32.min(lo, inv#pos#x), Float32.max(hi, inv#pos#x)))
            }, None, invaders)

    ///
    /// The formation marches sideways, and drops a row when it reaches a wall.
    ///
    /// The bounds come from the *living* invaders only, so clearing a whole outer column
    /// lets the rest march further, exactly as the arcade original does.
    ///
    def marchInvaders(w: World): World = {
        let half = Rules.invaderSize()#x / 2.0f32;
        match liveBounds(w#invaders) {
            case None => w
            case Some((lo, hi)) => {
                let living = Vector.count(inv -> inv#alive, w#invaders);
                let stepX = w#marchDir * Rules.marchSpeedFor(living, w#level);
                // The bassline advances by however far the formation just moved, so its
                // tempo tracks the speed-up without a separate timer.
                let sounded = beat(Float32.abs(stepX), w);
                let hitsWall = (lo + stepX) < half or (hi + stepX) > (Rules.fieldWidth() - half);
                if (hitsWall)
                    { marchDir = -sounded#marchDir,
                      invaders = Vector.map(inv -> { pos = { y = inv#pos#y + Rules.marchDrop() | inv#pos } | inv },
                                            sounded#invaders) | sounded }
                else
                    { invaders = Vector.map(inv -> { pos = { x = inv#pos#x + stepX | inv#pos } | inv },
                                            sounded#invaders) | sounded }
            }
        }
    }

    ///
    /// Advances the marching bassline by `distance`, sounding a note when one is due.
    ///
    def beat(distance: Float32, w: World): World = {
        let total = w#marchedSince + distance;
        if (total < Rules.marchNoteDistance()) { marchedSince = total | w }
        else
            emit(SoundCmd.MarchStep(w#marchNote),
                 { marchedSince = total - Rules.marchNoteDistance(),
                   marchNote = Int32.remainder(w#marchNote + 1, SoundCmd.marchNotes()) | w })
    }

    /// The lowest living invader in each column is the only one that can drop a bomb.
    def bombers(invaders: Vector[Invader]): List[Invader] =
        Vector.foldLeft((acc, inv) ->
            if (not inv#alive) acc
            else if (List.exists(other -> other#pos#x == inv#pos#x and other#pos#y > inv#pos#y, acc)) acc
            else inv :: List.filter(other -> other#pos#x != inv#pos#x, acc),
            Nil, invaders)

    /// Occasionally, one of them drops a bomb.
    def invaderFire(w: World): World = {
        let (drops, afterChance) = Rng.chance(Rules.bombChanceFor(w#level), w#rng);
        if (not drops) { rng = afterChance | w }
        else {
            let candidates = bombers(w#invaders);
            let count = List.length(candidates);
            if (count == 0) { rng = afterChance | w }
            else {
                let (pick, afterPick) = Rng.nextInt32Below(count, afterChance);
                match List.nth(pick, candidates) {
                    case None => { rng = afterPick | w }
                    case Some(inv) => {
                        let bomb = { x = inv#pos#x, y = inv#pos#y + Rules.invaderSize()#y };
                        { bombs = bomb :: w#bombs, rng = afterPick | w }
                    }
                }
            }
        }
    }

    /// The index of the first living invader this bullet hits.
    def hitIndex(bullet: Vec2, invaders: Vector[Invader]): Option[Int32] = {
        def loop(i) =
            if (i >= Vector.length(invaders)) None
            else {
                let inv = Vector.get(i, invaders);
                if (inv#alive and Collide.overlaps(bullet, Rules.bulletSize(), inv#pos, Rules.invaderSize()))
                    Some(i)
                else loop(i + 1)
            };
        loop(0)
    }

    ///
    /// Bullets meet invaders.
    ///
    /// A bullet is spent on the first invader it hits, so one shot can never clear two.
    ///
    def resolveBullets(w: World): World = {
        def loop(remaining, invaders, kept, score, blasts) = match remaining {
            case Nil => (List.reverse(kept), invaders, score, blasts)
            case bullet :: rest => match hitIndex(bullet, invaders) {
                case None => loop(rest, invaders, bullet :: kept, score, blasts)
                case Some(i) => {
                    let hit = Vector.get(i, invaders);
                    let struck = { alive = false | hit };
                    let blast = { pos = hit#pos,
                                  ticksLeft = Rules.invaderBlastTicks(),
                                  kind = BlastKind.InvaderBlast };
                    loop(rest, Vector.update(i, struck, invaders), kept,
                         score + Rules.pointsFor(hit#kind), blast :: blasts)
                }
            }
        };
        let (bullets, invaders, score, blasts) = loop(w#bullets, w#invaders, Nil, w#score, w#blasts);
        let killed = List.length(blasts) - List.length(w#blasts);
        let noises = List.repeat(killed, SoundCmd.InvaderDies);
        { bullets = bullets, invaders = invaders, score = score, blasts = blasts,
          sounds = List.append(noises, w#sounds) | w }
    }

    ///
    /// Bombs meet the player.
    ///
    /// A hit costs one life, clears the bombs on screen, leaves wreckage, and freezes the
    /// game for a beat -- being blown up should be something you watch, not something you
    /// only notice from the life counter.
    ///
    def resolveBombs(w: World): World = {
        let player = { x = w#playerX, y = Rules.playerY() };
        let hit = List.exists(b -> Collide.overlaps(b, Rules.bombSize(), player, Rules.playerSize()), w#bombs);
        if (not hit) w
        else if (w#shield > 0)
            // The shield takes it. The bombs on screen are still cleared, so a shielded hit
            // buys breathing room as well as a life.
            emit(SoundCmd.ShieldBlock, { bombs = Nil | w })
        else {
            let wreck = { pos = player, ticksLeft = Rules.playerBlastTicks(), kind = BlastKind.PlayerBlast };
            emit(SoundCmd.PlayerDies,
                 { lives = w#lives - 1,
                   bombs = Nil,
                   blasts = wreck :: w#blasts,
                   pause = Rules.deathPauseTicks() | w })
        }
    }

    /// Half the mystery ship's width -- how far off-screen it spawns and despawns.
    def mysteryMargin(): Float32 = Rules.mysterySize()#x / 2.0f32 + 2.0f32

    ///
    /// Flies the mystery ship across, or counts down to the next one.
    ///
    def moveMystery(w: World): World = match w#mystery {
        case Some(m) => {
            let x = m#x + m#dir * Rules.mysterySpeed();
            if (x < -mysteryMargin() or x > Rules.fieldWidth() + mysteryMargin())
                { mystery = None | w }
            else { mystery = Some({ x = x | m }) | w }
        }
        case None =>
            // Once the formation is nearly gone the saucer stops coming: the last few
            // invaders move fast enough that a bonus overhead is a distraction, not a
            // reward. The timer holds rather than counting down, so nothing is banked.
            if (Vector.count(inv -> inv#alive, w#invaders) <= Rules.mysteryMinInvaders()) w
            else if (w#mysteryTimer > 1) { mysteryTimer = w#mysteryTimer - 1 | w }
            else {
                let (fromLeft, afterSide) = Rng.chance(2, w#rng);
                let (jitter, next) = Rng.nextInt32Below(Rules.mysterySpread(), afterSide);
                let dir = if (fromLeft) 1.0f32 else -1.0f32;
                let x = if (fromLeft) -mysteryMargin() else Rules.fieldWidth() + mysteryMargin();
                emit(SoundCmd.MysteryAppears,
                     { mystery = Some({ x = x, dir = dir }),
                       mysteryTimer = Rules.mysteryInterval() + jitter,
                       rng = next | w })
            }
    }

    ///
    /// Bullets meet the mystery ship.
    ///
    /// Runs after the invaders have been resolved: the ship flies above the formation, so a
    /// bullet has already had its chance at everything below it.
    ///
    def resolveMystery(w: World): World = match w#mystery {
        case None => w
        case Some(m) => {
            let pos = { x = m#x, y = Rules.mysteryY() };
            let hits = b -> Collide.overlaps(b, Rules.bulletSize(), pos, Rules.mysterySize());
            if (not List.exists(hits, w#bullets)) w
            else {
                let (points, next) = Rules.mysteryScoreFrom(w#rng);
                let blast = { pos = pos, ticksLeft = Rules.invaderBlastTicks(), kind = BlastKind.InvaderBlast };
                // The bonus is not only points: it also raises the cannon's shield.
                emit(SoundCmd.MysteryDies,
                     { mystery = None,
                       bullets = List.filter(b -> not hits(b), w#bullets),
                       score = w#score + points,
                       blasts = blast :: w#blasts,
                       shield = Rules.shieldTicks(),
                       rng = next | w })
            }
        }
    }

    ///
    /// Awards an extra life each time the score passes the next threshold.
    ///
    /// Loops rather than awarding once, because a single tick could cross two thresholds --
    /// shooting the mystery ship for 300 while already near the line, say -- and skipping
    /// one would be a silent loss.
    ///
    def awardBonusLife(w: World): World =
        if (w#score < w#nextBonusAt) w
        else {
            let raised = { nextBonusAt = w#nextBonusAt + Rules.bonusLifeScore() | w };
            if (w#lives >= Rules.maxLives())
                // The threshold still advances, so a capped player does not get a fresh
                // award on every subsequent point.
                awardBonusLife(raised)
            else awardBonusLife(emit(SoundCmd.ExtraLife, { lives = raised#lives + 1 | raised }))
        }

    /// Counts the shield down. It runs on wall time, not on hits.
    def ageShield(w: World): World =
        { shield = Int32.max(0, w#shield - 1) | w }

    ///
    /// Ages every blast by a tick and drops the ones that have burnt out.
    ///
    def ageBlasts(w: World): World =
        { blasts = w#blasts
            |> List.map(b -> { ticksLeft = b#ticksLeft - 1 | b })
            |> List.filter(b -> b#ticksLeft > 0) | w }

    /// Whether any living invader has reached the player's line.
    def invasionComplete(invaders: Vector[Invader]): Bool =
        Vector.exists(inv -> inv#alive and inv#pos#y >= Rules.invasionLine(), invaders)

    ///
    /// Shots meet the bunkers, before anything else can be hit.
    ///
    /// Order matters: this runs after the shots have moved but before they are checked
    /// against invaders and the player, so a bunker genuinely stops a shot rather than
    /// merely being drawn in its way.
    ///
    def resolveBunkers(w: World): World = {
        let (afterBullets, bullets) = Bunkers.absorbAll(w#bunkers, w#bullets, Rules.bulletSize());
        let (afterBombs, bombs) = Bunkers.absorbAll(afterBullets, w#bombs, Rules.bombSize());
        { bunkers = Bunkers.erode(afterBombs, w#invaders), bullets = bullets, bombs = bombs | w }
    }

    /// The hi-score is the best score seen so far.
    def trackHiScore(w: World): World =
        if (w#score > w#hiScore) { hiScore = w#score | w } else w

    ///
    /// Decides whether the formation is cleared, or the game is lost.
    ///
    /// Clearing is not winning: it starts a pause, after which a harder level begins.
    ///
    def checkEnd(w: World): World =
        if (not Vector.exists(inv -> inv#alive, w#invaders))
            { phase = Phase.Cleared, pause = Rules.levelPauseTicks(), bullets = Nil, bombs = Nil | w }
        else if (w#lives <= 0 or invasionComplete(w#invaders)) { phase = Phase.Lost | w }
        else w

    ///
    /// The next level: a fresh formation and fresh bunkers, marching faster and dropping
    /// more bombs. Score, lives and the generator carry over.
    ///
    def nextLevel(w: World): World =
        { phase = Phase.Playing,
          level = w#level + 1,
          pause = 0,
          invaders = formation(),
          bunkers = Bunkers.initial(),
          bullets = Nil,
          bombs = Nil,
          marchDir = 1.0f32,
          cooldown = 0,
          blasts = Nil,
          mystery = None,
          mysteryTimer = Rules.mysteryInterval(),
          marchNote = 0,
          marchedSince = 0.0f32,
          playerX = Rules.fieldWidth() / 2.0f32 | w }

    ///
    /// An exact, comparable rendering of a world.
    ///
    /// Flix records do not derive `Eq`, and comparing worlds is what the replay tests do, so
    /// the game provides this instead. It is deliberately exact rather than rounded -- two
    /// runs of the same code on the same machine produce bit-identical floats, and IEEE
    /// arithmetic is deterministic across machines too, so there is nothing to be gained by
    /// blurring it. A digest also gives a readable diff when a replay does drift.
    ///
    pub def digest(w: World): String = {
        let header = "${w#phase}|t=${w#tick}|x=${w#playerX}|s=${w#score}|l=${w#lives}"
            + "|d=${w#marchDir}|c=${w#cooldown}|h=${w#hiScore}|v=${w#level}|p=${w#pause}"
            + "|g=${w#shield}|n=${w#nextBonusAt}|r=${w#rng}";
        let shots = List.foldLeft((acc, b) -> acc + "|b(${b#x},${b#y})", "", w#bullets);
        let drops = List.foldLeft((acc, b) -> acc + "|m(${b#x},${b#y})", "", w#bombs);
        let formation = Vector.foldLeft((acc, inv) ->
            acc + (if (inv#alive) "|i(${inv#pos#x},${inv#pos#y})" else "|."), "", w#invaders);
        let shelters = Vector.foldLeft((acc, bunker) ->
            acc + "|k${Bunkers.remaining(bunker)}", "", w#bunkers);
        let debris = List.foldLeft((acc, b) ->
            acc + "|e(${b#kind},${b#pos#x},${b#pos#y},${b#ticksLeft})", "", w#blasts);
        let ufo = match w#mystery {
            case None => "|u-${w#mysteryTimer}"
            case Some(m) => "|u(${m#x},${m#dir})"
        };
        let heard = List.foldLeft((acc, c) -> acc + "|s${c}", "", w#sounds);
        header + shots + drops + formation + shelters + debris + ufo + heard
    }

    // -- the step ---------------------------------------------------------------------

    ///
    /// Advances the game by exactly one logical tick.
    ///
    /// Pure. Given the same world and the same input, always the same result.
    ///
    pub def step(world: World, input: Snapshot): World = {
        // Sounds describe the tick just taken, so each step starts from silence.
        let w = { sounds = Nil | world };
        match w#phase {
        case Phase.Playing =>
            // Everything freezes while the cannon burns, except the wreckage itself.
            if (w#pause > 0)
                w |> ageBlasts |> (n -> { pause = n#pause - 1, tick = n#tick + 1 | n })
            else
            w
                |> movePlayer(input)
                |> fire(input)
                |> moveBullets
                |> moveBombs
                |> marchInvaders
                |> moveMystery
                |> invaderFire
                // Ages before anything can grant a shield, so a shield lasts exactly its
                // full duration rather than losing its first tick to the grant itself.
                |> ageShield
                |> resolveBunkers
                |> resolveBullets
                |> resolveMystery
                |> resolveBombs
                |> awardBonusLife
                |> ageBlasts
                |> trackHiScore
                |> checkEnd
                |> (next -> { tick = next#tick + 1 | next })

        case Phase.Cleared =>
            // A beat to see the field cleared, then the next level.
            if (w#pause > 1) { pause = w#pause - 1 | w } else nextLevel(w)

        case Phase.Lost =>
            // Enter starts a new game. Nothing else happens once it is over, so a lost world
            // is stable no matter how many steps run. The hi-score outlives the game, the
            // way an arcade cabinet's does.
            if (Set.memberOf(Key.Enter, input#pressed)) { hiScore = w#hiScore | initial(w#seed) }
            else w
        }
    }

}
