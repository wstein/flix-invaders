///
/// The state of a game of Invaders.
///
/// Everything here is plain immutable data, including the random number generator. A `World`
/// plus a list of input snapshots completely determines every world that follows, which is
/// what the replay tests rely on.
///

/// A point, or a size, depending on context.
pub type alias Vec2 = { x = Float32, y = Float32 }

/// One invader in the formation. Dead ones keep their slot so the grid never reshuffles.
pub type alias Invader = { pos = Vec2, alive = Bool }

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
///
pub type alias World = {
    phase = Phase,
    tick = Int32,
    playerX = Float32,
    bullets = List[Vec2],
    bombs = List[Vec2],
    invaders = Vector[Invader],
    marchDir = Float32,
    cooldown = Int32,
    score = Int32,
    lives = Int32,
    rng = Rng,
    seed = Int64
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

    pub def playerSize(): Vec2 = { x = 44.0f32, y = 14.0f32 }
    pub def playerY(): Float32 = 436.0f32
    pub def playerSpeed(): Float32 = 4.0f32
    pub def startingLives(): Int32 = 3

    pub def bulletSize(): Vec2 = { x = 4.0f32, y = 12.0f32 }
    pub def bulletSpeed(): Float32 = 7.0f32

    /// Ticks between shots. Without this, holding fire fills the screen.
    pub def fireCooldown(): Int32 = 18

    pub def bombSize(): Vec2 = { x = 6.0f32, y = 12.0f32 }
    pub def bombSpeed(): Float32 = 3.0f32

    /// One in this many steps, some invader drops a bomb.
    pub def bombChance(): Int32 = 45

    pub def invaderSize(): Vec2 = { x = 32.0f32, y = 20.0f32 }
    pub def columns(): Int32 = 6
    pub def rows(): Int32 = 4
    pub def columnSpacing(): Float32 = 74.0f32
    pub def rowSpacing(): Float32 = 46.0f32
    pub def formationLeft(): Float32 = 80.0f32
    pub def formationTop(): Float32 = 70.0f32

    pub def marchSpeed(): Float32 = 0.8f32

    /// How far the formation drops each time it reaches a wall.
    pub def marchDrop(): Float32 = 24.0f32

    /// Invaders reaching this line end the game.
    pub def invasionLine(): Float32 = playerY() - invaderSize()#y

    pub def pointsPerInvader(): Int32 = 10

    pub def totalInvaders(): Int32 = columns() * rows()

}
