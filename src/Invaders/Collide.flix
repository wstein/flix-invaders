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
    pub def overlaps(aPos: Vec2, aSize: Vec2, bPos: Vec2, bSize: Vec2): Bool = {
        let dx = Float32.abs(aPos#x - bPos#x);
        let dy = Float32.abs(aPos#y - bPos#y);
        let halfWidths = (aSize#x + bSize#x) / 2.0f32;
        let halfHeights = (aSize#y + bSize#y) / 2.0f32;
        dx < halfWidths and dy < halfHeights
    }

}
