///
/// A moving picture: state, time, and input, but still no game.
///
/// This is the step up from `Still`. Four balls of different sizes bounce around a box and
/// off each other. The whole simulation is the pure function `step`, which the runtime calls
/// exactly 60 times a second regardless of how fast the display is -- so the balls move at
/// the same speed on every machine.
///
/// Collisions are elastic and mass-weighted: mass goes with area, so the big ball shoves the
/// small one aside while barely changing course. `test/TestAnimation.flix` checks that both
/// momentum and kinetic energy come out unchanged, which is a far sharper test than looking
/// at it.
///
/// Read `step` and note what is *not* there: no clock, no frame counter, no window. It takes
/// a world and an input snapshot and returns the next world. That is the whole idea the game
/// is built on, and it is why these sketches can be tested without a display.
///
/// Run it:   bin/sketch animation
///
/// Try this: change `gravity` from 0 to something small like 0.15 and watch the balls fall,
/// or add a fourth lane in `makeBalls`.
///
/// A ball: position, velocity, size, colour. All data.
pub type alias Ball = {
    x = Float32,
    y = Float32,
    dx = Float32,
    dy = Float32,
    radius = Float32,
    tint = Color
}

/// The bouncing world: the balls plus the sideways nudge currently being applied.
pub type alias Bouncing = {
    balls = List[Ball],
    nudge = Float32
}

mod Animation {

    pub def fieldWidthPx(): Int32 = 640
    pub def fieldHeightPx(): Int32 = 480

    pub def fieldWidth(): Float32 = Int32.toFloat32(fieldWidthPx())
    pub def fieldHeight(): Float32 = Int32.toFloat32(fieldHeightPx())

    /// Constant downward acceleration. Set this to something like 0.15 to add gravity.
    def gravity(): Float32 = 0.0f32

    /// How hard the arrow keys push the balls sideways.
    def nudgeStrength(): Float32 = 0.35f32

    def palette(): Vector[Color] =
        Vector#{Palette.coral(), Palette.mint(), Palette.sun(), Palette.azure()}

    ///
    /// Builds `count` balls from `seed`.
    ///
    /// Pure, and identical for the same seed -- the generator is threaded through rather
    /// than being drawn from a global source.
    ///
    def makeBalls(count: Int32, index: Int32, rng: Rng): List[Ball] =
        if (index >= count) Nil
        else {
            let (jitterX, r1) = Rng.nextInt32Below(60, rng);
            let (py, r2) = Rng.nextInt32Below(200, r1);
            let (vx, r3) = Rng.nextInt32Below(7, r2);
            let (vy, r4) = Rng.nextInt32Below(7, r3);
            let tint = Vector.get(Int32.remainder(index, Vector.length(palette())), palette());
            // Four lanes 160px apart, jittered by at most 30 either way, so adjacent balls
            // start at least 100px apart -- comfortably more than the 66px the largest
            // neighbouring pair of radii sums to.
            let lane = 80.0f32 + Int32.toFloat32(index) * 160.0f32;
            let ball = {
                x = lane + Int32.toFloat32(jitterX) - 30.0f32,
                y = 120.0f32 + Int32.toFloat32(py),
                dx = Int32.toFloat32(vx - 3) + 1.5f32,
                dy = Int32.toFloat32(vy - 3) + 1.5f32,
                radius = 18.0f32 + Int32.toFloat32(index) * 6.0f32,
                tint = tint
            };
            ball :: makeBalls(count, index + 1, r4)
        }

    pub def initial(seed: Int64): Bouncing =
        { balls = makeBalls(4, 0, Rng.fromSeed(seed)), nudge = 0.0f32 }

    ///
    /// Reflects a ball off the walls and moves it one step.
    ///
    /// The reflection flips the velocity *and* clamps the position back inside, so a ball
    /// that overshoots in one step cannot get stuck outside the wall flipping every frame.
    ///
    def advanceBall(nudge: Float32, b: Ball): Ball = {
        let dx = b#dx + nudge;
        let dy = b#dy + gravity();
        let x = b#x + dx;
        let y = b#y + dy;

        let minX = b#radius;
        let maxX = fieldWidth() - b#radius;
        let minY = b#radius;
        let maxY = fieldHeight() - b#radius;

        let (finalX, finalDx) =
            if (x < minX) (minX, Float32.abs(dx))
            else if (x > maxX) (maxX, -Float32.abs(dx))
            else (x, dx);

        let (finalY, finalDy) =
            if (y < minY) (minY, Float32.abs(dy))
            else if (y > maxY) (maxY, -Float32.abs(dy))
            else (y, dy);

        { x = finalX, y = finalY, dx = finalDx, dy = finalDy | b }
    }

    def sqrtOf(x: Float32): Float32 = Float32.pow(base = x, 0.5f32)

    def clampTo(lo: Float32, hi: Float32, v: Float32): Float32 =
        if (v < lo) lo else if (v > hi) hi else v

    /// Keeps a ball inside the field without touching its velocity.
    def clampToField(b: Ball): Ball =
        { x = clampTo(b#radius, fieldWidth() - b#radius, b#x),
          y = clampTo(b#radius, fieldHeight() - b#radius, b#y) | b }

    ///
    /// The mass of a ball.
    ///
    /// These are discs, not spheres, so mass goes with area -- the radius squared. The
    /// largest ball is a bit under three times the mass of the smallest, which is enough
    /// for the difference to be obvious: the big one barely deviates while the small one is
    /// sent flying.
    ///
    def mass(b: Ball): Float32 = b#radius * b#radius

    ///
    /// Resolves an elastic collision between two balls.
    ///
    /// Two things happen, and both are needed. The balls are pushed apart along the line
    /// between their centres so they cannot overlap, and an impulse is applied along that
    /// line. Velocity perpendicular to the line is untouched, so a glancing blow deflects
    /// rather than stopping the balls dead.
    ///
    /// Both parts are weighted by mass. The impulse is
    /// `-2 * closing / (1/ma + 1/mb)`, the standard result for a perfectly elastic
    /// collision, which conserves both momentum and kinetic energy; and the separation
    /// moves each ball by the *other* one's share of the total mass, so the lighter ball
    /// gives way. With equal masses this reduces to simply exchanging the normal
    /// components of the two velocities.
    ///
    /// Balls that overlap but are already moving apart are only separated. Without that
    /// check a pair can get stuck, flipping their velocities every step and vibrating in
    /// place instead of parting.
    ///
    def resolvePair(a: Ball, b: Ball): (Ball, Ball) = {
        let dx = b#x - a#x;
        let dy = b#y - a#y;
        let distanceSquared = dx * dx + dy * dy;
        let touching = a#radius + b#radius;
        if (distanceSquared >= touching * touching or distanceSquared <= 0.0f32) (a, b)
        else {
            let distance = sqrtOf(distanceSquared);
            let nx = dx / distance;
            let ny = dy / distance;

            let massA = mass(a);
            let massB = mass(b);
            let total = massA + massB;

            // Separate them, the lighter ball giving way by the larger share.
            let overlap = touching - distance;
            let shareA = overlap * (massB / total);
            let shareB = overlap * (massA / total);
            let a1 = { x = a#x - nx * shareA, y = a#y - ny * shareA | a };
            let b1 = { x = b#x + nx * shareB, y = b#y + ny * shareB | b };

            // Closing speed along the normal. Negative means they are approaching.
            let closing = (b#dx - a#dx) * nx + (b#dy - a#dy) * ny;
            if (closing >= 0.0f32) (a1, b1)
            else {
                let impulse = -2.0f32 * closing / (1.0f32 / massA + 1.0f32 / massB);
                ({ dx = a1#dx - impulse / massA * nx, dy = a1#dy - impulse / massA * ny | a1 },
                 { dx = b1#dx + impulse / massB * nx, dy = b1#dy + impulse / massB * ny | b1 })
            }
        }
    }

    ///
    /// Resolves every pair once per step.
    ///
    def resolveCollisions(balls: Vector[Ball]): Vector[Ball] = {
        let count = Vector.length(balls);
        def inner(i, j, acc) =
            if (j >= count) acc
            else {
                let (a, b) = resolvePair(Vector.get(i, acc), Vector.get(j, acc));
                inner(i, j + 1, Vector.update(j, b, Vector.update(i, a, acc)))
            };
        def outer(i, acc) =
            if (i >= count) acc
            else outer(i + 1, inner(i, i + 1, acc));
        outer(0, balls)
    }

    ///
    /// One logical tick. Pure: no clock, no window, no `IO`.
    ///
    pub def step(world: Bouncing, snapshot: Snapshot): Bouncing = {
        let left = if (Set.memberOf(Key.Left, snapshot#held)) -nudgeStrength() else 0.0f32;
        let right = if (Set.memberOf(Key.Right, snapshot#held)) nudgeStrength() else 0.0f32;
        let nudge = left + right;
        let moved = List.map(advanceBall(nudge), world#balls);
        let bounced = resolveCollisions(List.toVector(moved));
        { balls = List.map(clampToField, Vector.toList(bounced)), nudge = nudge }
    }

    ///
    /// Describes the frame. Uses only `Canvas`, so a test can record it without a display.
    ///
    pub def view(world: Bouncing): Unit \ Canvas = {
        Canvas.clear(Palette.background());
        List.forEach(b -> {
            Canvas.fill(b#tint);
            Canvas.ellipse(b#x, b#y, b#radius * 2.0f32, b#radius * 2.0f32)
        }, world#balls);
        Canvas.fill(Palette.dim());
        Canvas.textSize(13.0f32);
        Canvas.text("left/right arrows nudge the balls -- they bounce off each other too",
            24.0f32, fieldHeight() - 28.0f32)
    }

    pub def main(): Unit \ IO = {
        let limit = Sketch.maxFramesFromEnv();
        Sketch.start(
            { title = "Animation",
              width = fieldWidthPx(),
              height = fieldHeightPx(),
              seed = 2026i64,
              hz = 60,
              maxFrames = limit, fontPath = None },
            initial,
            step,
            view)
    }

}
