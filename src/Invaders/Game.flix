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
    def formation(level: Int32): Vector[Invader] =
        Vector.range(0, Rules.totalInvaders()) |> Vector.map(index -> {
            let column = Int32.remainder(index, Rules.columns());
            let row = index / Rules.columns();
            let fx = Rules.formationLeft() + Int32.toFloat32(column) * Rules.columnSpacing();
            let fy = Rules.formationTopFor(level) + Int32.toFloat32(row) * Rules.rowSpacing();
            { pos = { x = fx, y = fy },
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
          invaders = formation(1),
          bunkers = Bunkers.initial(),
          marchDir = 1.0f32,
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
          marchNote = 0,
          shotsFired = 0,
          marchedSince = 0.0f32 }

    def clampTo(lo: Float32, hi: Float32, v: Float32): Float32 =
        if (v < lo) lo else if (v > hi) hi else v

    /// Plays `cmd` and returns `w` unchanged, so it drops into a pipeline stage.
    def emit(cmd: SoundCmd, w: World): World \ Sound = { Sound.play(cmd); w }

    // -- pipeline stages --------------------------------------------------------------

    /// Left and right move the player, who cannot leave the field.
    def movePlayer(input: Snapshot, w: World): World = {
        let left = if (Set.memberOf(Key.Left, input#held)) -Rules.playerSpeed() else 0.0f32;
        let right = if (Set.memberOf(Key.Right, input#held)) Rules.playerSpeed() else 0.0f32;
        let half = Rules.playerSize()#x / 2.0f32;
        { playerX = clampTo(half, Rules.fieldWidth() - half, w#playerX + left + right) | w }
    }

    ///
    /// Space fires, if the previous shot has cleared the screen.
    ///
    /// There is no timer: the rate of fire is whatever the last shot's flight allows, which
    /// is the original's rule and the reason accuracy matters. Holding the key down refires
    /// the instant the screen is clear, so nothing is lost by holding it.
    ///
    def fire(input: Snapshot, w: World): World \ Sound =
        if (List.length(w#bullets) >= Rules.shotsAloft()) w
        else if (not Set.memberOf(Key.Space, input#held)) w
        else {
            let muzzle = { x = w#playerX, y = Rules.playerY() - Rules.playerSize()#y };
            emit(SoundCmd.Shoot,
                 { bullets = muzzle :: w#bullets, shotsFired = w#shotsFired + 1 | w })
        }

    /// Bullets rise and are dropped when they leave the top of the field.
    def moveBullets(w: World): World =
        { bullets = w#bullets
            |> List.map(b -> { y = b#y - Rules.bulletSpeed() | b })
            |> List.filter(b -> b#y > -Rules.bulletSize()#y) | w }

    ///
    /// Bombs fall and are dropped when they leave the bottom of the field.
    ///
    /// Each kind falls at its own speed, and the wiggler also sways: its horizontal step
    /// reverses every `bombWiggleTicks`, which is a triangle wave written as a sign flip.
    /// The sway is clamped to the field so a wiggler dropped by an invader at the wall
    /// cannot walk off the edge and fall where nothing can be hit.
    ///
    def moveBombs(w: World): World = {
        let half = Rules.bombSize()#x / 2.0f32;
        let sway = b ->
            if (b#kind != BombKind.Wiggly) 0.0f32
            else if (Int32.remainder(b#age / Rules.bombWiggleTicks(), 2) == 0)
                Rules.bombWiggleSpeed()
            else -Rules.bombWiggleSpeed();
        { bombs = w#bombs
            |> List.map(b ->
                { x = clampTo(half, Rules.fieldWidth() - half, b#x + sway(b)),
                  y = b#y + Rules.bombSpeedFor(b#kind),
                  age = b#age + 1 | b })
            |> List.filter(b -> b#y < Rules.fieldHeight() + Rules.bombSize()#y) | w }
    }

    /// The x of the leftmost and rightmost living invader, if any are left.
    def liveBounds(invaders: Vector[Invader]): Option[(Float32, Float32)] = {
        let updateBound = (acc, inv) ->
            if (not inv#alive)
                acc
            else match acc {
                case None => Some((inv#pos#x, inv#pos#x))
                case Some((lo, hi)) =>
                    Some((Float32.min(lo, inv#pos#x), Float32.max(hi, inv#pos#x)))
            };
        Vector.foldLeft(updateBound, None, invaders)
    }

    ///
    /// The formation marches sideways, and drops a row when it reaches a wall.
    ///
    /// The bounds come from the *living* invaders only, so clearing a whole outer column
    /// lets the rest march further, exactly as the arcade original does.
    ///
    def marchInvaders(w: World): World \ Sound = {
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
                    let updatedInvaders = Vector.map(inv -> {
                        pos = { y = inv#pos#y + Rules.marchDrop() | inv#pos } | inv
                    }, sounded#invaders);
                    { marchDir = -sounded#marchDir, invaders = updatedInvaders | sounded }
                else
                    let updatedInvaders = Vector.map(inv -> {
                        pos = { x = inv#pos#x + stepX | inv#pos } | inv
                    }, sounded#invaders);
                    { invaders = updatedInvaders | sounded }
            }
        }
    }

    ///
    /// Advances the marching bassline by `distance`, sounding a note when one is due.
    ///
    def beat(distance: Float32, w: World): World \ Sound = {
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
            if (not inv#alive)
                acc
            else {
                let covered = List.exists(other ->
                    other#pos#x == inv#pos#x and other#pos#y > inv#pos#y, acc);
                if (covered)
                    acc
                else
                    inv :: List.filter(other -> other#pos#x != inv#pos#x, acc)
            },
            Nil, invaders)

    def placeBomb(inv: Invader, rng: Rng, w: World): World = {
        let (kind, afterKind) = Rules.bombKindFrom(rng);
        let bomb = { x = inv#pos#x,
                     y = inv#pos#y + Rules.invaderSize()#y,
                     kind = kind,
                     age = 0 };
        { bombs = bomb :: w#bombs, rng = afterKind | w }
    }

    ///
    /// Helper to spawn a bomb when chance succeeds.
    ///
    def spawnBomb(candidates: List[Invader], rng: Rng, w: World): World = {
        let count = List.length(candidates);
        if (count == 0) { rng = rng | w }
        else {
            let (pick, afterPick) = Rng.nextInt32Below(count, rng);
            match List.nth(pick, candidates) {
                case None => { rng = afterPick | w }
                case Some(inv) => placeBomb(inv, afterPick, w)
            }
        }
    }

    ///
    /// Occasionally, one of them drops a bomb.
    ///
    /// The cap is checked before the die is rolled, so a formation already at three bombs
    /// does not silently consume randomness -- which would make the generator's position
    /// depend on how crowded the screen was, and two replays of the same input diverge.
    ///
    def invaderFire(w: World): World =
        if (List.length(w#bombs) >= Rules.maxBombs()) w
        else {
            let (drops, afterChance) = Rng.chance(Rules.bombChanceFor(w#level), w#rng);
            if (not drops) { rng = afterChance | w }
            else spawnBomb(bombers(w#invaders), afterChance, w)
        }

    ///
    /// What one pass over the bombs carries.
    ///
    /// A named record rather than a tuple, so that the fold below reads as what it does to
    /// each field instead of as three values kept in the right order by hand. `kept` is
    /// newest-first, as an accumulated list is, and reversed once at the end.
    ///
    type alias ShotPass = { bullets = List[Vec2], rng = Rng, kept = List[Bomb] }

    ///
    /// One bomb against the shots still in flight.
    ///
    def meetBomb(pass: ShotPass, bomb: Bomb): ShotPass = {
        let struck = b -> Collide.overlaps(aPos = b, aSize = Rules.bulletSize(),
                                           bPos = { x = bomb#x, y = bomb#y },
                                           bSize = Rules.bombSize());
        if (not List.exists(struck, pass#bullets)) { kept = bomb :: pass#kept | pass }
        else {
            // The shot is spent either way; only the bomb's fate is a die roll.
            let (survives, next) = Rng.chance(Rules.bombSurvivesShot(), pass#rng);
            { bullets = List.filter(b -> not struck(b), pass#bullets),
              rng = next,
              kept = if (survives) bomb :: pass#kept else pass#kept }
        }
    }

    ///
    /// Shots meet bombs in mid-air.
    ///
    /// Asymmetric, as in the original: the cannon's shot is always spent, the bomb usually
    /// but not always dies with it. Runs after the bunkers have had their say, so a shot
    /// already absorbed by a shelter cannot also knock a bomb down on its way through.
    ///
    /// Folded bomb-first rather than bullet-first so that one shot cannot clear two bombs:
    /// each bullet is removed the moment it meets anything.
    ///
    def resolveShotsMeetBombs(w: World): World = {
        let initPass = {
            bullets = w#bullets,
            rng = w#rng,
            kept = Nil
        };
        let pass = List.foldLeft(meetBomb, initPass, w#bombs);
        { bombs = List.reverse(pass#kept),
          bullets = pass#bullets,
          rng = pass#rng | w }
    }

    /// The index of the first living invader this bullet hits.
    def hitIndex(bullet: Vec2, invaders: Vector[Invader]): Option[Int32] =
        Vector.findIndexOfLeft(inv ->
            inv#alive and Collide.overlaps(aPos = bullet, aSize = Rules.bulletSize(),
                                           bPos = inv#pos, bSize = Rules.invaderSize()),
            invaders)

    ///
    /// What one pass over the bullets carries: the shots that missed, and what the hits did.
    ///
    type alias BulletPass = { kept = List[Vec2],
                              invaders = Vector[Invader],
                              score = Int32,
                              blasts = List[Blast] }

    ///
    /// One bullet against the formation.
    ///
    /// A bullet that hits is gone -- it is not added to `kept` -- which is what stops one shot
    /// clearing two invaders: the fold never offers it to a second one.
    ///
    def meetInvader(pass: BulletPass, bullet: Vec2): BulletPass =
        match hitIndex(bullet, pass#invaders) {
            case None => { kept = bullet :: pass#kept | pass }
            case Some(i) => {
                let hit = Vector.get(i, pass#invaders);
                let struck = { alive = false | hit };
                let blast = { pos = hit#pos,
                              ticksLeft = Rules.invaderBlastTicks(),
                              kind = BlastKind.InvaderBlast };
                { invaders = Vector.update(i, struck, pass#invaders),
                  score = pass#score + Rules.pointsFor(hit#kind),
                  blasts = blast :: pass#blasts | pass }
            }
        }

    ///
    /// Bullets meet invaders.
    ///
    /// A bullet is spent on the first invader it hits, so one shot can never clear two.
    ///
    def resolveBullets(w: World): World \ Sound = {
        let start = { kept = Nil, invaders = w#invaders, score = w#score, blasts = w#blasts };
        let pass = List.foldLeft(meetInvader, start, w#bullets);
        let killed = List.length(pass#blasts) - List.length(w#blasts);
        // One noise per kill: two bullets landing in one tick must be heard twice.
        List.forEach(_ -> Sound.play(SoundCmd.InvaderDies), List.range(0, killed));
        { bullets = List.reverse(pass#kept), invaders = pass#invaders,
          score = pass#score, blasts = pass#blasts | w }
    }

    ///
    /// Bombs meet the player.
    ///
    /// A hit costs one life, clears the bombs on screen, leaves wreckage, and freezes the
    /// game for a beat -- being blown up should be something you watch, not something you
    /// only notice from the life counter.
    ///
    def resolveBombs(w: World): World \ Sound = {
        let player = { x = w#playerX, y = Rules.playerY() };
        let overlapsPlayer = b ->
            Collide.overlaps(aPos = { x = b#x, y = b#y },
                             aSize = Rules.bombSize(),
                             bPos = player, bSize = Rules.playerSize());
        let hit = List.exists(overlapsPlayer, w#bombs);
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

    def stepActiveMystery(m: Mystery, w: World): World = {
        let x = m#x + m#dir * Rules.mysterySpeed();
        if (x < -mysteryMargin() or x > Rules.fieldWidth() + mysteryMargin())
            { mystery = None | w }
        else { mystery = Some({ x = x | m }) | w }
    }

    ///
    /// Whether the formation has been thinned past the point where a saucer is welcome.
    ///
    /// See `Rules.mysteryMinInvaders`: the last few invaders race, and a bonus dangled then
    /// arrives at the worst possible moment.
    ///
    def formationTooThin(w: World): Bool =
        Vector.count(inv -> inv#alive, w#invaders) <= Rules.mysteryMinInvaders()

    ///
    /// Where a saucer entering from one side starts, and which way it then flies.
    ///
    /// One answer rather than two: the x and the direction are the same decision, and asking
    /// the same question twice is how they drift apart into a ship flying off its own edge.
    /// It starts a margin clear of the screen so it slides in rather than appearing whole.
    ///
    def mysteryEntry(fromLeft: Bool): Mystery =
        if (fromLeft) { x = -mysteryMargin(), dir = 1.0f32 }
        else { x = Rules.fieldWidth() + mysteryMargin(), dir = -1.0f32 }

    ///
    /// Launches a saucer from a randomly chosen side and sets the wait for the next one.
    ///
    /// The generator is threaded through both draws and returned in the world, so the whole
    /// sequence -- side, then jitter -- replays exactly from the same seed.
    ///
    def launchMystery(w: World): World \ Sound = {
        let (fromLeft, afterSide) = Rng.chance(2, w#rng);
        let (jitter, next) = Rng.nextInt32Below(Rules.mysterySpread(), afterSide);
        emit(SoundCmd.MysteryAppears,
             { mystery = Some(mysteryEntry(fromLeft)),
               mysteryTimer = Rules.mysteryInterval() + jitter,
               rng = next | w })
    }

    ///
    /// Counts down to the next saucer, and launches it when the count runs out.
    ///
    def spawnMystery(w: World): World \ Sound =
        if (formationTooThin(w)) w
        else if (w#mysteryTimer > 1) { mysteryTimer = w#mysteryTimer - 1 | w }
        else launchMystery(w)

    ///
    /// Flies the mystery ship across, or counts down to the next one.
    ///
    def moveMystery(w: World): World \ Sound = match w#mystery {
        case Some(m) => stepActiveMystery(m, w)
        case None    => spawnMystery(w)
    }

    ///
    /// Bullets meet the mystery ship.
    ///
    /// Runs after the invaders have been resolved: the ship flies above the formation, so a
    /// bullet has already had its chance at everything below it.
    ///
    def resolveMystery(w: World): World \ Sound = match w#mystery {
        case None => w
        case Some(m) => {
            let pos = { x = m#x, y = Rules.mysteryY() };
            let hits = b -> Collide.overlaps(aPos = b, aSize = Rules.bulletSize(),
                                             bPos = pos, bSize = Rules.mysterySize());
            if (not List.exists(hits, w#bullets)) w
            else {
                let points = Rules.mysteryScoreFor(w#shotsFired);
                let blast = { pos = pos,
                              ticksLeft = Rules.invaderBlastTicks(),
                              kind = BlastKind.InvaderBlast };
                // The bonus is not only points: it also raises the cannon's shield.
                emit(SoundCmd.MysteryDies,
                     { mystery = None,
                       bullets = List.filter(b -> not hits(b), w#bullets),
                       score = w#score + points,
                       blasts = blast :: w#blasts,
                       shield = Rules.shieldTicks() | w })
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
    def awardBonusLife(w: World): World \ Sound =
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
        let (afterBullets, bullets) =
            Bunkers.absorbAll(w#bunkers, w#bullets, Rules.bulletSize(), Rules.bulletCrater());
        let (afterBombs, bombs) = Bunkers.absorbBombs(afterBullets, w#bombs);
        let finalBunkers = Bunkers.erode(afterBombs, w#invaders);
        { bunkers = finalBunkers, bullets = bullets, bombs = bombs | w }
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
            { phase = Phase.Cleared,
              pause = Rules.levelPauseTicks(),
              bullets = Nil, bombs = Nil | w }
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
          // Each wave starts lower than the last until the cycle resets, so a later wave is
          // not merely faster -- it is shorter.
          invaders = formation(w#level + 1),
          bunkers = Bunkers.initial(),
          bullets = Nil,
          bombs = Nil,
          marchDir = 1.0f32,
          blasts = Nil,
          mystery = None,
          mysteryTimer = Rules.mysteryInterval(),
          marchNote = 0,
          // The shot counter is per board, as the saucer's value is.
          shotsFired = 0,
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
        let h1 = "${w#phase}|t=${w#tick}|x=${w#playerX}|s=${w#score}|l=${w#lives}";
        let h2 = "|d=${w#marchDir}|h=${w#hiScore}|v=${w#level}|p=${w#pause}";
        let h3 = "|g=${w#shield}|n=${w#nextBonusAt}|f=${w#shotsFired}|r=${w#rng}";
        let header = h1 + h2 + h3;
        let shots = List.foldLeft((acc, b) -> acc + "|b(${b#x},${b#y})", "", w#bullets);
        let drops = List.foldLeft((acc, b) ->
            acc + "|m(${b#kind},${b#x},${b#y},${b#age})", "", w#bombs);
        let formation = Vector.foldLeft((acc, inv) ->
            let entry = if (inv#alive) "|i(${inv#pos#x},${inv#pos#y})" else "|.";
            acc + entry, "", w#invaders);
        let shelters = Vector.foldLeft((acc, bunker) ->
            let entry = "|k${Bunkers.remaining(bunker)}";
            acc + entry, "", w#bunkers);
        let debris = List.foldLeft((acc, b) ->
            let entry = "|e(${b#kind},${b#pos#x},${b#pos#y},${b#ticksLeft})";
            acc + entry, "", w#blasts);
        let ufo = match w#mystery {
            case None => "|u-${w#mysteryTimer}"
            case Some(m) => "|u(${m#x},${m#dir})"
        };
        header + shots + drops + formation + shelters + debris + ufo
    }

    // -- the step ---------------------------------------------------------------------

    def stepPlaying(w: World, input: Snapshot): World \ Sound =
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
                |> resolveShotsMeetBombs
                |> resolveBullets
                |> resolveMystery
                |> resolveBombs
                |> awardBonusLife
                |> ageBlasts
                |> trackHiScore
                |> checkEnd
                |> (next -> { tick = next#tick + 1 | next })

    ///
    /// Advances the game by exactly one logical tick.
    ///
    /// Pure. Given the same world and the same input, always the same result.
    ///
    pub def step(w: World, input: Snapshot): World \ Sound = {
        match w#phase {
        case Phase.Playing => stepPlaying(w, input)

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
