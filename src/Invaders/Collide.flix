///
/// Axis-aligned rectangle overlap.
///
/// Deliberately ordinary code rather than anything clever. Collision runs on every entity
/// pair on every step, so it stays a plain pure function -- a Datalog formulation would be a
/// nice exercise for a discrete problem like formation adjacency, but it is the wrong tool
/// for a hot per-frame loop.
///
mod Collide {

    ///
    /// Whether two rectangles overlap.
    ///
    /// Positions are centres, not corners, which is how everything in the game is stored and
    /// drawn. Touching exactly at the edge does *not* count as a hit: the comparison is
    /// strict, so a bullet grazing an invader's boundary passes by. Picking one convention
    /// and testing it matters more than which one it is.
    ///
    /// All four arguments are named. They are structurally identical `Vec2`s, so a
    /// transposed pair would compile, type-check, and silently change collision.
    pub def overlaps(aPos: {aPos = Vec2}, aSize: {aSize = Vec2},
                     bPos: {bPos = Vec2}, bSize: {bSize = Vec2}): Bool = {
        let dx = Float32.abs(aPos#aPos#x - bPos#bPos#x);
        let dy = Float32.abs(aPos#aPos#y - bPos#bPos#y);
        let halfWidths = (aSize#aSize#x + bSize#bSize#x) / 2.0f32;
        let halfHeights = (aSize#aSize#y + bSize#bSize#y) / 2.0f32;
        dx < halfWidths and dy < halfHeights
    }

}
