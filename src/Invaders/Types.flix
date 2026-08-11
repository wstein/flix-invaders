///
/// The state of a game of Invaders.
///
/// Everything here is plain immutable data, including the random number generator. A `World`
/// plus a list of input snapshots completely determines every world that follows, which is
/// what the replay tests rely on.
///

/// A point, or a size, depending on context.
pub type alias Vec2 = { x = Float32, y = Float32 }

/// The three kinds of invader, worth different points -- as in the original.
pub enum InvaderKind with Eq, ToString {
    case Squid
    case Crab
    case Octopus
}

///
/// A defensive bunker: a grid of small blocks, each of which is either still there or shot
/// away. `origin` is the top-left corner of the block grid.
///
pub type alias Bunker = { origin = Vec2, cells = Vector[Bool] }

///
/// The mystery ship, while one is on screen. `dir` is -1.0 or 1.0.
///
pub type alias Mystery = { x = Float32, dir = Float32 }

/// What blew up. The two look different and last for different lengths of time.
pub enum BlastKind with Eq, ToString {
    case InvaderBlast
    case PlayerBlast
}

///
/// A short-lived explosion. `ticksLeft` counts down to zero, at which point it is dropped.
///
pub type alias Blast = { pos = Vec2, ticksLeft = Int32, kind = BlastKind }

/// One invader in the formation. Dead ones keep their slot so the grid never reshuffles.
pub type alias Invader = { pos = Vec2, alive = Bool, kind = InvaderKind, row = Int32 }

///
/// The three kinds of bomb the invaders drop, as in the original: "slow straight ones, fast
/// straight ones and wiggly ones which are the most powerful".
///
/// "Most powerful" is not more lethal -- any bomb that reaches the cannon kills it. It is the
/// shelters that tell the three apart: the wiggler tears a wider hole, so a formation dropping
/// them strips your cover faster than one dropping daggers.
///
pub enum BombKind with Eq, ToString {
    case Slow
    case Fast
    case Wiggly
}

///
/// A falling bomb. `age` counts ticks since it was dropped, and drives the wiggler's sway --
/// keeping the phase on the bomb rather than deriving it from the world clock is what lets two
/// wigglers dropped at different moments sway out of step, and what keeps `step` a pure
/// function of its argument.
///
pub type alias Bomb = { x = Float32, y = Float32, kind = BombKind, age = Int32 }

///
/// What the game is currently doing.
///
/// There is no winning. Clearing the formation puts the game in `Cleared` for a moment and
/// then starts a harder level, exactly as the arcade original does -- the only ending is
/// losing.
///
pub enum Phase with Eq, ToString {
    case Playing
    case Cleared
    case Lost
}

///
/// The whole game state.
///
/// - `playerX` is the player's x position; its y never changes.
/// - `bullets` travel up and are fired by the player; `bombs` travel down and are dropped by
///   the invaders.
/// - `marchDir` is which way the formation is marching, `-1.0` or `1.0`.
/// - `rng` is threaded through every step rather than drawn from a global source.
/// - `seed` is kept so that restarting rebuilds exactly the same starting position.
/// - `hiScore` survives a restart, the way an arcade cabinet's does.
/// - `level` counts from 1 and drives the difficulty curve.
/// - `pause` is ticks remaining in a non-playing phase, used for the between-levels beat.
/// - `shield` is ticks of invulnerability remaining, earned by shooting the mystery ship.
/// - `nextBonusAt` is the score at which the next extra life is awarded.
/// - `marchNote` and `marchedSince` drive the bassline: notes are spaced by *distance*
///   marched, not by time, so the tempo tracks the formation's speed for free.
///
pub type alias World = {
    phase = Phase,
    tick = Int32,
    playerX = Float32,
    bullets = List[Vec2],
    bombs = List[Bomb],
    invaders = Vector[Invader],
    bunkers = Vector[Bunker],
    marchDir = Float32,
    score = Int32,
    lives = Int32,
    rng = Rng,
    seed = Int64,
    hiScore = Int32,
    level = Int32,
    pause = Int32,
    blasts = List[Blast],
    mystery = Option[Mystery],
    mysteryTimer = Int32,
    shield = Int32,
    nextBonusAt = Int32,
    marchNote = Int32,
    marchedSince = Float32
}

///
/// The numbers that define the game.
///
/// Collected in one place so the rules can be read without hunting through `Game`, and so
/// the tests can refer to them rather than repeating magic numbers.
///
mod Rules {

    pub def fieldWidth(): Float32 = 640.0f32
    pub def fieldHeight(): Float32 = 480.0f32

    /// Matches the cannon sprite at `spriteScale` x 3: 13 x 8 pixels.
    pub def playerSize(): Vec2 = { x = 39.0f32, y = 24.0f32 }
    pub def playerY(): Float32 = 436.0f32
    pub def playerSpeed(): Float32 = 4.0f32
    pub def startingLives(): Int32 = 3

    pub def bulletSize(): Vec2 = { x = 4.0f32, y = 12.0f32 }

    /// Screen pixels per sprite pixel.
    pub def spriteScale(): Float32 = 2.0f32

    pub def cannonScale(): Float32 = 3.0f32
    pub def bulletSpeed(): Float32 = 7.0f32

    ///
    /// How many of the cannon's shots may be in the air at once.
    ///
    /// One, as in the original: "only 1 laser shot on screen at any one time". This is the
    /// rule the whole game is balanced around, and it was the largest divergence here. A
    /// twelve-tick cooldown let five shots fly at once, which made a miss cost twelve ticks;
    /// under this rule a miss costs the bullet's whole flight to the top of the screen --
    /// about sixty-eight -- so aiming is suddenly worth more than volume.
    ///
    /// It is a constant rather than an inlined check so the tests and the demo bot can say
    /// what they depend on.
    ///
    pub def shotsAloft(): Int32 = 1

    ///
    /// Ticks a missed shot spends in the air, and therefore the slowest the cannon can fire.
    ///
    /// With one shot allowed on screen, the rate of fire is no longer a constant: it is the
    /// flight time of the last shot. A hit near the formation returns the cannon quickly; a
    /// miss costs the whole climb. This is the worst case, which is what the difficulty
    /// tests need to reason about.
    ///
    pub def shotFlightTicks(): Int32 =
        Float32.tryToInt32(
            Float32.ceil((playerY() - playerSize()#y + bulletSize()#y) / bulletSpeed()))
            |> Option.getWithDefault(1)

    pub def bombSize(): Vec2 = { x = 6.0f32, y = 14.0f32 }

    ///
    /// How many bombs the formation may have in the air at once.
    ///
    /// Three, as in the original. Without a cap the drop chance is the only thing bounding
    /// the bomb count, so a high level does not merely get busier -- it eventually becomes a
    /// solid curtain no cannon can cross. `bombChanceFor` was floored to hold that off, which
    /// treated the symptom; this is the rule the original actually has, and it makes the
    /// per-level rate mean something again, because a faster drop rate now buys *sooner*
    /// bombs rather than *more* of them.
    ///
    pub def maxBombs(): Int32 = 3

    /// A freshly dropped bomb. One place knows that a new bomb starts at age zero.
    pub def bombAt(pos: Vec2, kind: BombKind): Bomb =
        { x = pos#x, y = pos#y, kind = kind, age = 0 }

    ///
    /// One in this many bombs survives being shot.
    ///
    /// The original's rule, and a strange-sounding one until you play it: "the player's shot
    /// is always destroyed but the invader's missile occasionally survives". The asymmetry is
    /// the point. Shooting a bomb down is never free -- it costs the shot outright, and under
    /// the one-shot rule that is the whole flight -- and it is not even reliable, so clearing
    /// a path is a gamble rather than a technique.
    ///
    /// One in four keeps it a real risk without making the attempt pointless.
    ///
    pub def bombSurvivesShot(): Int32 = 4

    /// The speed a bomb of each kind falls at.
    ///
    /// The slow one is the old single speed, so the game a player already knows is the middle
    /// of the new range rather than the bottom of it. The dagger is fast enough to punish
    /// standing still and the wiggler is slower than either, which is what makes its sideways
    /// sweep readable instead of a blur.
    pub def bombSpeedFor(kind: BombKind): Float32 = match kind {
        case BombKind.Slow => 3.0f32
        case BombKind.Fast => 5.0f32
        case BombKind.Wiggly => 2.4f32
    }

    /// One in this many steps, some invader drops a bomb.
    ///
    /// The base rate at which a column drops a bomb, as a one-in-N chance per tick.
    ///
    /// Raised by half from 90 because the game was ending the wrong way. Every one of ten
    /// benchmarked games finished with the formation landing, and every one of them still had
    /// three to five spare cannons: bombs almost never killed anybody, so lives were
    /// decoration and the only real clock was the descent.
    ///
    pub def bombChance(): Int32 = 60

    /// One hit box for every kind, so a squid is no harder to hit than an octopus.
    pub def invaderSize(): Vec2 = { x = 24.0f32, y = 16.0f32 }

    pub def columns(): Int32 = 11
    pub def rows(): Int32 = 5
    pub def columnSpacing(): Float32 = 40.0f32
    pub def rowSpacing(): Float32 = 32.0f32
    pub def formationLeft(): Float32 = 120.0f32
    pub def formationTop(): Float32 = 96.0f32

    /// The y of the formation's lowest row at spawn -- the furthest a *hit* ever has to fly.
    pub def formationBottom(): Float32 =
        formationTop() + Int32.toFloat32(rows() - 1) * rowSpacing()

    ///
    /// Which kind sits in each row: squid at the top, then two rows of crabs, then two of
    /// octopuses. The ones worth most are hardest to reach.
    ///
    pub def kindForRow(row: Int32): InvaderKind =
        if (row <= 0) InvaderKind.Squid
        else if (row <= 2) InvaderKind.Crab
        else InvaderKind.Octopus

    pub def pointsFor(kind: InvaderKind): Int32 = match kind {
        case InvaderKind.Squid => 30
        case InvaderKind.Crab => 20
        case InvaderKind.Octopus => 10
    }

    /// The green line the cannon stands on.
    pub def groundY(): Float32 = 458.0f32

    // -- bunkers ---------------------------------------------------------------------

    /// One block of a bunker, in screen pixels.
    pub def bunkerCell(): Float32 = 4.0f32

    pub def bunkerColumns(): Int32 = 12
    pub def bunkerRows(): Int32 = 8
    pub def bunkerCount(): Int32 = 4
    pub def bunkerTop(): Float32 = 366.0f32

    /// The x of the left edge of bunker `index`.
    pub def bunkerLeft(index: Int32): Float32 = {
        let width = Int32.toFloat32(bunkerColumns()) * bunkerCell();
        let margin = 64.0f32;
        let span = fieldWidth() - 2.0f32 * margin - width;
        margin + span * Int32.toFloat32(index) / Int32.toFloat32(bunkerCount() - 1)
    }

    ///
    /// How far the damage from one hit spreads, in screen pixels.
    ///
    /// A single block per hit looks like a pinprick; a small crater reads as damage.
    ///
    ///
    /// The crater the cannon's own shot leaves in a bunker.
    ///
    /// Narrow on purpose -- narrower than a bomb is wide. That is what makes the arcade's
    /// oldest trick work: drill a slit through your shelter, then stand in it and shoot out
    /// while their bombs still break on the blocks either side. A wider crater cannot do it,
    /// because the hole you make is then a hole they can drop through.
    ///
    pub def bulletCrater(): Float32 = 2.0f32

    ///
    /// The crater an invader's bomb leaves.
    ///
    /// Much bigger, and deliberately not symmetric with the cannon's. The enemy erodes your
    /// shelter faster than you can carve it, so camping is a tactic with a clock on it rather
    /// than a place to live.
    ///
    pub def bombCrater(): Float32 = 6.0f32

    ///
    /// The crater each kind of bomb leaves, which is where "most powerful" actually lives.
    ///
    /// Any bomb that reaches the cannon kills it, so the three cannot differ in lethality
    /// without inventing a health bar the original never had. They differ in what they do to
    /// your cover, which is the resource the game is really about: a wiggler takes half again
    /// what a dagger does, so which kind is falling changes how long a shelter lasts.
    ///
    pub def bombCraterFor(kind: BombKind): Float32 = match kind {
        case BombKind.Slow => bombCrater()
        case BombKind.Fast => bombCrater()
        case BombKind.Wiggly => bombCrater() * 1.5f32
    }

    ///
    /// How far a wiggler sways from its column, and how long each half-sweep lasts.
    ///
    /// The sway is a triangle wave rather than a sine: it needs no trigonometry, no phase
    /// stored beyond the bomb's own age, and -- because the horizontal step is constant --
    /// it cannot tunnel through a bunker column the way an accelerating sweep could.
    ///
    /// Kept under half a bunker's width so a wiggler that starts over cover stays over it.
    ///
    pub def bombWiggleSpeed(): Float32 = 1.1f32

    pub def bombWiggleTicks(): Int32 = 14

    ///
    /// Which kind of bomb an invader drops.
    ///
    /// Weighted by the shape of the original's threat rather than uniformly: the plain slow
    /// bomb is the common case and the two that change the player's plan are rarer, so
    /// meeting a wiggler is an event rather than a third of the traffic.
    ///
    pub def bombKindFrom(rng: Rng): (BombKind, Rng) = {
        let (roll, next) = Rng.nextInt32Below(8, rng);
        let kind =
            if (roll < 4) BombKind.Slow
            else if (roll < 6) BombKind.Fast
            else BombKind.Wiggly;
        (kind, next)
    }

    /// The formation's speed on level 1 with every invader still alive.
    pub def baseMarchSpeed(): Float32 = 0.65f32

    ///
    /// How much faster the last invader moves than a full formation.
    ///
    /// The original achieved this by accident -- the hardware redrew one invader per frame,
    /// so fewer invaders meant a faster sweep. Here it is deliberate, but the feel is the
    /// same: the closing moments of a level are frantic.
    ///
    def thinningSpeedUp(): Float32 = 2.0f32

    ///
    /// How much faster each level starts than the one before.
    ///
    /// Compounding rather than linear, so the difficulty keeps biting in an endless game --
    /// a flat increment stops mattering once the level number is large. Capped, because
    /// past a certain speed the formation crosses the screen faster than a bullet can reach
    /// it and no amount of skill helps.
    ///
    def levelGrowth(): Float32 = 1.22f32

    def maxLevelSpeedFactor(): Float32 = 4.0f32

    ///
    /// The fastest the formation may ever march, as a fraction of the cannon's own speed.
    ///
    /// This is the cap the level growth above was supposed to be, and was not: that one bounds
    /// only the per-level factor, and the thinning multiplier is applied *after* it, so the
    /// real ceiling was 0.65 x 4.0 x 3.0 = 7.8 px/tick against a cannon that does 4.0.
    ///
    /// What breaks is not overtaking, it is *closing*. A cannon gaining half a pixel a tick on
    /// a receding target is as much use as one that cannot gain at all, and the shot rate
    /// tracks the closing speed all the way down. Measured over the endgame of each level, at
    /// eight invaders or fewer, before this cap existed:
    ///
    /// | level | march | closing | shots/1000 ticks | kills/1000 |
    /// |---|---|---|---|---|
    /// | 1 | 1.85 | 2.15 | 48 | 31 |
    /// | 2 | 2.27 | 1.73 | 40 | 29 |
    /// | 3 | 2.76 | 1.24 | 31 | 24 |
    /// | 4 | 3.37 | 0.63 | 19 | 16 |
    /// | 5 | 4.03 | -0.03 | 17 | 12 |
    ///
    /// So the collapse begins at level 4, not at level 5 where the formation finally overtakes
    /// the cannon -- and a cap set just under the cannon's speed would have fixed the wrong
    /// end. Three quarters leaves levels one to three untouched, their endgames being 1.85,
    /// 2.27 and 2.76, and restores level 4 to 30 shots and 25 kills per 1000 ticks. Over sixty
    /// seeds the demo goes from mean level 4.9 to 5.5 and from 43.0 ticks per kill to 36.4.
    ///
    /// No bot-side rule fixes this, and three were tried. Waiting for the formation rather than
    /// chasing it improves every local figure -- walking falls from 3.66 px/tick to 0.86, shots
    /// rise, deaths fall -- and still loses levels, because the descent does not wait either.
    /// Chasing also walks the cannon towards the wall the formation is about to turn at, which
    /// shortens the wait for the return sweep, so it was never as pointless as it looked.
    ///
    /// The cost is that from level 4 onwards every *endgame* saturates here, so the compounding
    /// growth stops separating the late levels once a formation has thinned out. What still
    /// rises with the level is the speed of a full formation -- 1.18 at level 4 against 2.60 at
    /// level 8 -- and the bomb rate. That is the trade: a late game that is hard because it is
    /// quick and thick with bombs, rather than one that is impossible because the geometry
    /// forbids a hit.
    ///
    pub def maxMarchSpeed(): Float32 = maxMarchFactor() * playerSpeed()

    def maxMarchFactor(): Float32 = 0.75f32

    ///
    /// The march speed for a given number of survivors on a given level.
    ///
    pub def marchSpeedFor(living: Int32, level: Int32): Float32 = {
        let total = Int32.toFloat32(totalInvaders());
        let cleared = (total - Int32.toFloat32(Int32.max(0, living))) / total;
        let thinning = 1.0f32 + thinningSpeedUp() * cleared;
        let steps = Int32.toFloat32(Int32.max(0, level - 1));
        let byLevel = Float32.min(maxLevelSpeedFactor(), Float32.pow(base = levelGrowth(), steps));
        Float32.min(maxMarchSpeed(), baseMarchSpeed() * byLevel * thinning)
    }

    ///
    /// Bombs get more frequent with each level. This is a one-in-N chance, so smaller is
    /// more dangerous; it is floored so a high level cannot turn into a solid wall of bombs.
    ///
    /// The per-level step and the floor are scaled with the base, so raising the rate keeps
    /// the shape of the curve instead of steepening it.
    pub def bombChanceFor(level: Int32): Int32 =
        Int32.max(minBombChance(), bombChance() - (level - 1) * levelBombStep())

    def levelBombStep(): Int32 = 3

    def minBombChance(): Int32 = 10

    /// How long the game pauses between clearing a formation and the next one appearing.
    ///
    /// The simulation's tick rate, which `Sketch.start` is configured to match.
    ///
    /// Here so that durations meant in seconds can say so. `shieldTicks` at 600 is ten
    /// seconds of immunity and `deathPauseTicks` at 54 is a beat under a second, but neither
    /// reads that way as a bare number.
    ///
    pub def ticksPerSecond(): Int32 = 60

    /// How many numbers the between-levels countdown shows.
    pub def countdownSteps(): Int32 = 3

    ///
    /// The pause between clearing a formation and the next one arriving.
    ///
    /// Exactly one second per counted number, so the countdown on screen is a real countdown
    /// rather than a decoration that happens to reach one at about the right time. Derived
    /// rather than written out, so the two cannot drift apart.
    ///
    pub def levelPauseTicks(): Int32 = countdownSteps() * ticksPerSecond()

    ///
    /// The beat between one player's game ending and the next player's starting.
    ///
    /// The same length and the same count as the pause between waves, because it is the same
    /// idea: a moment to notice what happened and get a hand back on the controls. Handing
    /// straight over meant the incoming player's first life began while they were still
    /// reading the last one's score.
    ///
    pub def handoverTicks(): Int32 = countdownSteps() * ticksPerSecond()

    ///
    /// How long GAME OVER is held before the cabinet moves on.
    ///
    /// Long enough to read and take in, short enough not to be waiting for it. Without a beat
    /// here a player's game ended on one frame and the next player's count started on the
    /// next, so nobody ever saw how their own game finished.
    ///
    pub def gameOverTicks(): Int32 = 2 * ticksPerSecond()

    // -- the mystery ship -------------------------------------------------------------

    /// The saucer is stretched horizontally: three times the width, unchanged height.
    pub def mysteryScaleX(): Float32 = 3.0f32
    pub def mysteryScaleY(): Float32 = 2.0f32

    ///
    /// The saucer's hit box, derived from the sprite and the scales it is drawn at.
    ///
    /// Computed rather than written down: a hard-coded size silently stops matching the
    /// moment a scale changes, which is exactly what happened -- the hit box stayed at the
    /// old 96px while the sprite shrank to 48, so the saucer could be hit from well outside
    /// itself.
    ///
    pub def mysterySize(): Vec2 =
        { x = Int32.toFloat32(Sprite.width(Sprites.mystery())) * mysteryScaleX(),
          y = Int32.toFloat32(Sprite.height(Sprites.mystery())) * mysteryScaleY() }

    /// High enough to be clear of the formation's starting row.
    pub def mysteryY(): Float32 = 70.0f32

    pub def mysterySpeed(): Float32 = 1.6f32

    ///
    /// Ticks between appearances, plus up to `mysterySpread` more.
    ///
    /// Short enough that a saucer turns up two or three times in a level rather than once at
    /// the very end, and jittered so it does not arrive on the same beat every time.
    ///
    pub def mysteryInterval(): Int32 = 700

    pub def mysterySpread(): Int32 = 320

    ///
    /// The saucer stops coming once the formation is this thin.
    ///
    /// The original does the same. Without it the bonus turns up exactly when the last few
    /// invaders are racing across the screen and there is no attention to spare for it --
    /// which is the worst possible moment to dangle a reward.
    ///
    pub def mysteryMinInvaders(): Int32 = 8

    ///
    ///
    /// Score needed for an extra life.
    ///
    /// The original awarded one bonus ship at a threshold set by a dip switch. This game
    /// never ends, so a single award would stop mattering by the third level; instead the
    /// bonus repeats at every multiple, capped so lives cannot be farmed indefinitely.
    ///
    pub def bonusLifeScore(): Int32 = 2500

    pub def maxLives(): Int32 = 6

    ///
    /// How long the shield earned from the mystery ship lasts.
    ///
    /// Long enough to be worth chasing the bonus for, short enough that you cannot bank it
    /// and stop paying attention.
    ///
    pub def shieldTicks(): Int32 = 600

    /// The shield starts flashing this long before it fails, as a warning.
    pub def shieldWarningTicks(): Int32 = 150

    ///
    /// What the mystery ship is worth.
    ///
    /// The original's value depended on how many shots you had fired, which players
    /// eventually reverse-engineered into a way to score 300 every time. Here it is simply
    /// drawn from the table, which keeps it a genuine bonus rather than a memorised trick.
    ///
    pub def mysteryScores(): Vector[Int32] = Vector#{50, 100, 150, 300}

    pub def mysteryScoreFrom(rng: Rng): (Int32, Rng) = {
        let (pick, next) = Rng.nextInt32Below(Vector.length(mysteryScores()), rng);
        (Vector.get(pick, mysteryScores()), next)
    }

    ///
    /// How far the formation marches between notes of the bassline.
    ///
    /// Spacing the notes by distance rather than by time is what makes the music accelerate
    /// with the invaders without any extra bookkeeping.
    ///
    pub def marchNoteDistance(): Float32 = 12.0f32

    /// How long an invader's starburst stays on screen.
    pub def invaderBlastTicks(): Int32 = 18

    /// How long the cannon's wreckage stays on screen.
    pub def playerBlastTicks(): Int32 = 66

    ///
    /// How long everything freezes when the player is hit.
    ///
    /// A beat shorter than the wreckage lasts, so the cannon is back before the debris has
    /// quite faded and the restart does not feel abrupt.
    ///
    pub def deathPauseTicks(): Int32 = 54

    /// How far the formation drops each time it reaches a wall.
    pub def marchDrop(): Float32 = 20.0f32

    /// Invaders reaching this line end the game.
    pub def invasionLine(): Float32 = playerY() - invaderSize()#y

    pub def totalInvaders(): Int32 = columns() * rows()

}
