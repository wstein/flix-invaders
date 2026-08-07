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
/// - `cooldown` is the ticks remaining before the player may fire again.
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
    bombs = List[Vec2],
    invaders = Vector[Invader],
    bunkers = Vector[Bunker],
    marchDir = Float32,
    cooldown = Int32,
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

    /// Ticks between shots. Without this, holding fire fills the screen.
    pub def fireCooldown(): Int32 = 12

    pub def bombSize(): Vec2 = { x = 6.0f32, y = 14.0f32 }
    pub def bombSpeed(): Float32 = 3.0f32

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
    /// The march speed for a given number of survivors on a given level.
    ///
    pub def marchSpeedFor(living: Int32, level: Int32): Float32 = {
        let total = Int32.toFloat32(totalInvaders());
        let cleared = (total - Int32.toFloat32(Int32.max(0, living))) / total;
        let thinning = 1.0f32 + thinningSpeedUp() * cleared;
        let steps = Int32.toFloat32(Int32.max(0, level - 1));
        let byLevel = Float32.min(maxLevelSpeedFactor(), Float32.pow(base = levelGrowth(), steps));
        baseMarchSpeed() * byLevel * thinning
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
