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
              alive = true }
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
          marchDir = 1.0f32,
          cooldown = 0,
          score = 0,
          lives = Rules.startingLives(),
          rng = Rng.fromSeed(seed),
          seed = seed }

    def clampTo(lo: Float32, hi: Float32, v: Float32): Float32 =
        if (v < lo) lo else if (v > hi) hi else v

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
            { bullets = muzzle :: w#bullets, cooldown = Rules.fireCooldown() | w }
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
                let stepX = w#marchDir * Rules.marchSpeed();
                let hitsWall = (lo + stepX) < half or (hi + stepX) > (Rules.fieldWidth() - half);
                if (hitsWall)
                    { marchDir = -w#marchDir,
                      invaders = Vector.map(inv -> { pos = { y = inv#pos#y + Rules.marchDrop() | inv#pos } | inv },
                                            w#invaders) | w }
                else
                    { invaders = Vector.map(inv -> { pos = { x = inv#pos#x + stepX | inv#pos } | inv },
                                            w#invaders) | w }
            }
        }
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
        let (drops, afterChance) = Rng.chance(Rules.bombChance(), w#rng);
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
        def loop(remaining, invaders, kept, score) = match remaining {
            case Nil => (List.reverse(kept), invaders, score)
            case bullet :: rest => match hitIndex(bullet, invaders) {
                case None => loop(rest, invaders, bullet :: kept, score)
                case Some(i) => {
                    let struck = { alive = false | Vector.get(i, invaders) };
                    loop(rest, Vector.update(i, struck, invaders), kept, score + Rules.pointsPerInvader())
                }
            }
        };
        let (bullets, invaders, score) = loop(w#bullets, w#invaders, Nil, w#score);
        { bullets = bullets, invaders = invaders, score = score | w }
    }

    /// Bombs meet the player. A hit costs one life and clears the bombs on screen.
    def resolveBombs(w: World): World = {
        let player = { x = w#playerX, y = Rules.playerY() };
        let hit = List.exists(b -> Collide.overlaps(b, Rules.bombSize(), player, Rules.playerSize()), w#bombs);
        if (not hit) w
        else { lives = w#lives - 1, bombs = Nil | w }
    }

    /// Whether any living invader has reached the player's line.
    def invasionComplete(invaders: Vector[Invader]): Bool =
        Vector.exists(inv -> inv#alive and inv#pos#y >= Rules.invasionLine(), invaders)

    /// Decides whether the game is over, and how.
    def checkEnd(w: World): World =
        if (not Vector.exists(inv -> inv#alive, w#invaders)) { phase = Phase.Won | w }
        else if (w#lives <= 0 or invasionComplete(w#invaders)) { phase = Phase.Lost | w }
        else w

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
            + "|d=${w#marchDir}|c=${w#cooldown}|r=${w#rng}";
        let shots = List.foldLeft((acc, b) -> acc + "|b(${b#x},${b#y})", "", w#bullets);
        let drops = List.foldLeft((acc, b) -> acc + "|m(${b#x},${b#y})", "", w#bombs);
        let formation = Vector.foldLeft((acc, inv) ->
            acc + (if (inv#alive) "|i(${inv#pos#x},${inv#pos#y})" else "|."), "", w#invaders);
        header + shots + drops + formation
    }

    // -- the step ---------------------------------------------------------------------

    ///
    /// Advances the game by exactly one logical tick.
    ///
    /// Pure. Given the same world and the same input, always the same result.
    ///
    pub def step(w: World, input: Snapshot): World = match w#phase {
        case Phase.Playing =>
            w
                |> movePlayer(input)
                |> fire(input)
                |> moveBullets
                |> moveBombs
                |> marchInvaders
                |> invaderFire
                |> resolveBullets
                |> resolveBombs
                |> checkEnd
                |> (next -> { tick = next#tick + 1 | next })

        case _ =>
            // Enter starts a new game. Nothing else happens once it is over, so a finished
            // world is stable no matter how many steps run.
            if (Set.memberOf(Key.Enter, input#pressed)) initial(w#seed) else w
    }

}
