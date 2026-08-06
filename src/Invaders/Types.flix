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

/// One invader in the formation. Dead ones keep their slot so the grid never reshuffles.
pub type alias Invader = { pos = Vec2, alive = Bool, kind = InvaderKind, row = Int32 }

/// How the game ends, or that it has not.
pub enum Phase with Eq, ToString {
    case Playing
    case Won
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
    hiScore = Int32
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
    pub def fireCooldown(): Int32 = 18

    pub def bombSize(): Vec2 = { x = 6.0f32, y = 14.0f32 }
    pub def bombSpeed(): Float32 = 3.0f32

    /// One in this many steps, some invader drops a bomb.
    pub def bombChance(): Int32 = 45

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
    pub def blastRadius(): Float32 = 6.0f32

    pub def marchSpeed(): Float32 = 0.8f32

    /// How far the formation drops each time it reaches a wall.
    pub def marchDrop(): Float32 = 24.0f32

    /// Invaders reaching this line end the game.
    pub def invasionLine(): Float32 = playerY() - invaderSize()#y

    pub def totalInvaders(): Int32 = columns() * rows()

}
