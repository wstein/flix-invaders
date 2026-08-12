///
/// The four bunkers the player shelters behind.
///
/// A bunker is a grid of small blocks. Anything that hits one -- a bullet on its way up, a
/// bomb on its way down, or an invader that has marched far enough -- destroys the blocks
/// near the impact and is itself stopped. Blocks never come back, so the bunkers erode over
/// a game exactly as they do in the original.
///
/// All of this is pure. Damage is a function from a bunker and an impact point to a new
/// bunker.
///
mod Bunkers {

    ///
    /// The undamaged shape: an arch, so the cannon can shelter underneath and still shoot
    /// out through the top.
    ///
    def shape(): Vector[String] = Vector#{
        "...######...",
        "..########..",
        ".##########.",
        "############",
        "############",
        "####....####",
        "###......###",
        "###......###"
    }

    ///
    /// The blocks of an undamaged bunker, row by row.
    ///
    def freshCells(): Vector[Bool] =
        Vector.range(0, Rules.bunkerColumns() * Rules.bunkerRows()) |> Vector.map(index -> {
            let column = Int32.remainder(index, Rules.bunkerColumns());
            let row = index / Rules.bunkerColumns();
            match Vector.nth(row, shape()) {
                case Some(line) =>
                    if (column < String.length(line)) String.charAt(column, line) == '#' else false
                case None => false
            }
        })

    ///
    /// Four undamaged bunkers, evenly spaced.
    ///
    pub def initial(): Vector[Bunker] =
        Vector.range(0, Rules.bunkerCount()) |> Vector.map(index ->
            { origin = { x = Rules.bunkerLeft(index), y = Rules.bunkerTop() },
              cells = freshCells() })

    /// The centre of one block, in screen coordinates.
    pub def cellCentre(bunker: Bunker, index: Int32): Vec2 = {
        let column = Int32.remainder(index, Rules.bunkerColumns());
        let row = index / Rules.bunkerColumns();
        { x = bunker#origin#x + (Int32.toFloat32(column) + 0.5f32) * Rules.bunkerCell(),
          y = bunker#origin#y + (Int32.toFloat32(row) + 0.5f32) * Rules.bunkerCell() }
    }

    pub def cellSize(): Vec2 = { x = Rules.bunkerCell(), y = Rules.bunkerCell() }

    /// The whole bunker's footprint, used to reject distant shots cheaply.
    def bounds(bunker: Bunker): (Vec2, Vec2) = {
        let width = Int32.toFloat32(Rules.bunkerColumns()) * Rules.bunkerCell();
        let height = Int32.toFloat32(Rules.bunkerRows()) * Rules.bunkerCell();
        ({ x = bunker#origin#x + width / 2.0f32, y = bunker#origin#y + height / 2.0f32 },
         { x = width, y = height })
    }

    def closeRun(row: Int32, col: Int32, start: Option[Int32],
                 acc: List[(Int32, Int32, Int32)]): List[(Int32, Int32, Int32)] =
        match start {
            case None => acc
            case Some(startCol) => (row, startCol, col - startCol) :: acc
        }

    ///
    /// The surviving blocks, collapsed into horizontal runs as `(row, startColumn, length)`.
    ///
    /// The same trick the sprites use, for the same reason: an intact bunker is 96 blocks
    /// but only about a dozen runs, and drawing it a block at a time was costing real frame
    /// rate once there were four of them on screen.
    ///
    pub def runs(bunker: Bunker): List[(Int32, Int32, Int32)] = {
        def scanRow(row, col, start, acc) =
            if (col >= Rules.bunkerColumns()) closeRun(row, col, start, acc)
            else if (Vector.get(row * Rules.bunkerColumns() + col, bunker#cells))
                scanRow(row, col + 1, (match start {
                    case None => Some(col)
                    case some => some
                }), acc)
            else scanRow(row, col + 1, None, closeRun(row, col, start, acc));
        def eachRow(row, acc) =
            if (row >= Rules.bunkerRows()) acc
            else eachRow(row + 1, scanRow(row, 0, None, acc));
        List.reverse(eachRow(0, Nil))
    }

    ///
    /// Whether a shot of width `width`, fired from `x`, would meet a bunker on its way up.
    ///
    /// The rules do not care -- carving a slit through your own bunker is legal, and in the
    /// arcade original it is a tactic -- but a player who is not doing it deliberately is
    /// destroying their own cover and wasting the shot. This is the question to ask before
    /// pulling the trigger.
    ///
    /// This asks the question of the *same extent* `contact` uses, and so gives the same
    /// answer by construction. Two narrower versions were wrong in opposite directions, and
    /// both cost real play:
    ///
    /// - Sampling only the centre (`blocks`) misses the block beside the shot, because a
    ///   bullet is four pixels wide and so is a block. The bot cleared itself a slit, declared
    ///   the way open, and demolished its own cover from below -- one shot in seven struck a
    ///   bunker the guard had called clear.
    /// - Sampling the two edges as well over-corrects. `Collide.overlaps` is strict, so a
    ///   bullet centred on a block column does *not* touch the next column -- but the right
    ///   edge lands exactly on that column's boundary and floors into it. A perfectly drilled
    ///   channel then reads as blocked, which makes camping impossible to aim for.
    ///
    /// Sampling points cannot express a strict overlap at all, so this does not sample.
    ///
    pub def obstructs(bunkers: Vector[Bunker], x: Float32, width: Float32): Bool =
        Vector.exists(bunker -> meets(bunker, x, width), bunkers)

    ///
    /// Whether any standing block of `bunker` lies in the path of a shot of `width` at `x`.
    ///
    /// Scans columns rather than cells: a shot rising through a bunker meets every row of the
    /// columns it overlaps, so which row is irrelevant to the question and only the horizontal
    /// extent matters. The comparison is the x half of `Collide.overlaps`, strict included.
    ///
    def meets(bunker: Bunker, x: Float32, width: Float32): Bool = {
        let reach = (width + Rules.bunkerCell()) / 2.0f32;
        def standing(column) =
            Vector.exists(row ->
                Vector.nth(row * Rules.bunkerColumns() + column, bunker#cells)
                    |> Option.getWithDefault(false),
                Vector.range(0, Rules.bunkerRows()));
        def scan(column) =
            if (column >= Rules.bunkerColumns()) false
            else {
                let centre =
                    bunker#origin#x + (Int32.toFloat32(column) + 0.5f32) * Rules.bunkerCell();
                if (Float32.abs(centre - x) < reach and standing(column)) true
                else scan(column + 1)
            };
        scan(0)
    }

    ///
    /// Whether any standing block sits directly above the single point `x`.
    ///
    /// A point is not what gets fired, so this is rarely the question a caller wants -- see
    /// `obstructs`, which asks it of a whole bullet.
    ///
    pub def blocks(bunkers: Vector[Bunker], x: Float32): Bool =
        Vector.exists(bunker -> {
            let offset = (x - bunker#origin#x) / Rules.bunkerCell();
            match Float32.tryToInt32(Float32.floor(offset)) {
                case None => false
                case Some(column) =>
                    if (column < 0 or column >= Rules.bunkerColumns()) false
                    else Vector.exists(row ->
                        Vector.nth(row * Rules.bunkerColumns() + column, bunker#cells)
                            |> Option.getWithDefault(false),
                        Vector.range(0, Rules.bunkerRows()))
            }
        }, bunkers)

    pub def remaining(bunker: Bunker): Int32 =
        Vector.count(alive -> alive, bunker#cells)

    pub def totalRemaining(bunkers: Vector[Bunker]): Int32 =
        Vector.foldLeft((total, bunker) -> total + remaining(bunker), 0, bunkers)

    ///
    /// The surviving block this box strikes, if any: the one whose centre is nearest.
    ///
    /// Returning the block rather than just "yes" matters. A shot is up to twelve pixels
    /// tall, so it can overlap a block whose centre is further away than the blast radius.
    /// Centring the crater on the shot in that case destroys nothing while still consuming
    /// the shot -- the bunker silently eats bullets. Centring it on the block that was
    /// actually struck cannot.
    ///
    def contact(bunker: Bunker, pos: Vec2, size: Vec2): Option[Int32] = {
        // Reject on the whole footprint first; most shots are nowhere near a bunker, and
        // this turns a scan of 96 blocks into one comparison.
        let (centre, footprint) = bounds(bunker);
        def nearer(best, i) = {
            let c = cellCentre(bunker, i);
            let dx = c#x - pos#x;
            let dy = c#y - pos#y;
            let distance = dx * dx + dy * dy;
            match best {
                case Some((_, bestDistance)) if bestDistance <= distance => best
                case _ => Some((i, distance))
            }
        };
        def scan(i, best) =
            if (i >= Vector.length(bunker#cells)) best
            else if (Vector.get(i, bunker#cells)
                     and Collide.overlaps(aPos = pos, aSize = size,
                                          bPos = cellCentre(bunker, i), bSize = cellSize()))
                scan(i + 1, nearer(best, i))
            else scan(i + 1, best);
        if (not Collide.overlaps(aPos = pos, aSize = size, bPos = centre, bSize = footprint)) None
        else match scan(0, None) {
            case None => None
            case Some((index, _)) => Some(index)
        }
    }

    ///
    /// Whether anything of `bunker` still overlaps the given box.
    ///
    /// Asks the same question as `contact` and stops at the first answer. `contact` cannot:
    /// it has to see every overlapping block to return the *nearest*, which is what centres a
    /// crater correctly, and a caller that only wants "yes" pays for all 96 cells to throw the
    /// index away. `erode` asks this of every living invader against every bunker on every
    /// tick once the formation is that low, so the difference is not academic.
    ///
    /// A recursion rather than `Vector.exists`, which would want a `Vector.range` of indices
    /// built per call: the cell's index is needed to place it, and the point here is to stop
    /// allocating, not to start.
    ///
    def touches(bunker: Bunker, pos: Vec2, size: Vec2): Bool = {
        // Same footprint rejection `contact` opens with, and for the same reason.
        let (centre, footprint) = bounds(bunker);
        def scan(i) =
            if (i >= Vector.length(bunker#cells)) false
            else if (Vector.get(i, bunker#cells)
                     and Collide.overlaps(aPos = pos, aSize = size,
                                          bPos = cellCentre(bunker, i), bSize = cellSize()))
                true
            else scan(i + 1);
        Collide.overlaps(aPos = pos, aSize = size, bPos = centre, bSize = footprint) and scan(0)
    }

    ///
    /// Removes every block within `radius` of `at`.
    ///
    pub def damage(bunker: Bunker, at: Vec2, radius: Float32): Bunker = {
        let cells = Vector.mapWithIndex((index, alive) ->
            if (not alive) false
            else {
                let centre = cellCentre(bunker, index);
                let dx = centre#x - at#x;
                let dy = centre#y - at#y;
                (dx * dx + dy * dy) > radius * radius
            }, bunker#cells);
        { cells = cells | bunker }
    }

    ///
    /// Offers one shot to the bunkers.
    ///
    /// Returns the bunkers after any damage, and whether the shot was absorbed. An absorbed
    /// shot is removed by the caller, which is what makes a bunker actually protect the
    /// player rather than merely look like it does.
    ///
    pub def absorb(bunkers: Vector[Bunker], pos: Vec2, size: Vec2, crater: Float32): (Vector[Bunker], Bool) = {
        def loop(i, acc) =
            if (i >= Vector.length(acc)) (acc, false)
            else {
                let bunker = Vector.get(i, acc);
                match contact(bunker, pos, size) {
                    case None => loop(i + 1, acc)
                    case Some(index) => {
                        // The crater is centred on the block that was struck, so an absorbed
                        // shot always destroys at least that block.
                        let at = cellCentre(bunker, index);
                        (Vector.update(i, damage(bunker, at, crater), acc), true)
                    }
                }
            };
        loop(0, bunkers)
    }

    ///
    /// Offers a whole list of bombs to the bunkers, which carry their own crater size.
    ///
    /// Separate from `absorbAll` rather than generalising it: the crater is a property of the
    /// individual bomb here, not of the batch, and threading a per-item function through the
    /// batch version would make the common case -- bullets, all identical -- read worse to
    /// buy nothing.
    ///
    pub def absorbBombs(bunkers: Vector[Bunker], bombs: List[Bomb]): (Vector[Bunker], List[Bomb]) = {
        let pass = List.foldLeft((acc, bomb) -> {
            let (damaged, wasHit) =
                absorb(acc#bunkers, { x = bomb#x, y = bomb#y }, Rules.bombSize(),
                       Rules.bombCraterFor(bomb#kind));
            { bunkers = damaged, kept = if (wasHit) acc#kept else bomb :: acc#kept }
        }, { bunkers = bunkers, kept = (Nil: List[Bomb]) }, bombs);
        (pass#bunkers, List.reverse(pass#kept))
    }

    ///
    /// Offers a whole list of shots to the bunkers.
    ///
    /// Returns the damaged bunkers and the shots that got through, in the order they arrived.
    /// One shot damages at most one bunker: `absorb` stops at the first it makes contact with,
    /// so a bullet cannot bore through two shelters standing in a line.
    ///
    pub def absorbAll(bunkers: Vector[Bunker], shots: List[Vec2], size: Vec2, crater: Float32): (Vector[Bunker], List[Vec2]) = {
        let pass = List.foldLeft((acc, shot) -> {
            let (damaged, wasHit) = absorb(acc#bunkers, shot, size, crater);
            { bunkers = damaged, kept = if (wasHit) acc#kept else shot :: acc#kept }
        }, { bunkers = bunkers, kept = (Nil: List[Vec2]) }, shots);
        (pass#bunkers, List.reverse(pass#kept))
    }

    ///
    /// Invaders grind away any bunker they march into.
    ///
    /// Guarded by the formation's lowest point, so for most of a game this costs one
    /// comparison rather than a scan of every block against every invader.
    ///
    pub def erode(bunkers: Vector[Bunker], invaders: Vector[Invader]): Vector[Bunker] = {
        let lowest = Vector.foldLeft((low, inv) ->
            if (inv#alive)
                Float32.max(low, inv#pos#y)
            else
                low,
            0.0f32, invaders);
        if (lowest + Rules.invaderSize()#y / 2.0f32 < Rules.bunkerTop())
            bunkers
        else
            Vector.map(bunker ->
                Vector.foldLeft((acc, inv) ->
                    if (not inv#alive) acc
                    else if (not touches(acc, inv#pos, Rules.invaderSize())) acc
                    else damage(acc, inv#pos, Rules.invaderSize()#x / 2.0f32),
                    bunker, invaders),
                bunkers)
    }

}
