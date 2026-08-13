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
    def freshCells(): Vector[Bool] = {
        let totalCells = Rules.bunkerColumns() * Rules.bunkerRows();
        let shapes = shape();
        Vector.range(0, totalCells) |> Vector.map(index -> {
            let column = Int32.remainder(index, Rules.bunkerColumns());
            let row = index / Rules.bunkerColumns();
            match Vector.nth(row, shapes) {
                case Some(line) =>
                    if (column < String.length(line)) String.charAt(column, line) == '#' else false
                case None => false
            }
        })
    }

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
        let bCell = Rules.bunkerCell();
        let cx = bunker#origin#x + (Int32.toFloat32(column) + 0.5f32) * bCell;
        let cy = bunker#origin#y + (Int32.toFloat32(row) + 0.5f32) * bCell;
        { x = cx, y = cy }
    }

    ///
    /// The size of a single bunker cell block as a 2D vector.
    ///
    pub def cellSize(): Vec2 = { x = Rules.bunkerCell(), y = Rules.bunkerCell() }

    /// The whole bunker's footprint, used to reject distant shots cheaply.
    def bounds(bunker: Bunker): (Vec2, Vec2) = {
        let bCell = Rules.bunkerCell();
        let width = Int32.toFloat32(Rules.bunkerColumns()) * bCell;
        let height = Int32.toFloat32(Rules.bunkerRows()) * bCell;
        let pos = { x = bunker#origin#x + width / 2.0f32,
                    y = bunker#origin#y + height / 2.0f32 };
        let size = { x = width, y = height };
        (pos, size)
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
        let bCols = Rules.bunkerColumns();
        let bRows = Rules.bunkerRows();
        let scanRow = (acc, row) -> {
            let scanned = Vector.foldLeft((scan, col) ->
                let idx = row * bCols + col;
                if (Vector.get(idx, bunker#cells))
                    match scan#runStart {
                        case None => { runStart = Some(col) | scan }
                        case Some(_) => scan
                    }
                else
                    match scan#runStart {
                        case None => scan
                        case Some(startCol) =>
                            let runItem = (row, startCol, col - startCol);
                            { runs = runItem :: scan#runs, runStart = None }
                    }, { runs = Nil, runStart = None }, Vector.range(0, bCols));
            let closedRuns = closeRun(row, bCols, scanned#runStart, scanned#runs);
            List.append(closedRuns, acc)
        };
        List.foldLeft(scanRow, Nil, List.range(0, bRows))
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
        let inReach = column -> {
            let centre =
                bunker#origin#x + (Int32.toFloat32(column) + 0.5f32) * Rules.bunkerCell();
            Float32.abs(centre - x) < reach
        };
        Vector.exists(column -> inReach(column) and standingInColumn(bunker, column),
                      Vector.range(0, Rules.bunkerColumns()))
    }

    /// Whether any block is left in one column of a bunker.
    def standingInColumn(bunker: Bunker, column: Int32): Bool =
        Vector.exists(row ->
            Vector.nth(row * Rules.bunkerColumns() + column, bunker#cells)
                |> Option.getWithDefault(false),
            Vector.range(0, Rules.bunkerRows()))

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
                    else standingInColumn(bunker, column)
            }
        }, bunkers)

    ///
    /// The number of intact, surviving blocks in a single bunker.
    ///
    pub def remaining(bunker: Bunker): Int32 =
        Vector.count(alive -> alive, bunker#cells)

    ///
    /// The total number of intact, surviving blocks across all bunkers in the vector.
    ///
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
        let nearer = (best, index) ->
            if (not struckAt(bunker, index, pos, size)) best
            else {
                let distance = distanceSquared(cellCentre(bunker, index), pos);
                match best {
                    // `<=` keeps the earlier block when two are equidistant, so the answer
                    // does not depend on which way the vector happens to be walked.
                    case Some((_, best2)) if best2 <= distance => best
                    case _ => Some((index, distance))
                }
            };
        if (not Collide.overlaps(aPos = pos, aSize = size, bPos = centre, bSize = footprint)) None
        else
            Vector.foldLeft(nearer, None, cellIndices(bunker)) |> Option.map(fst)
    }

    /// The indices of a bunker's blocks. Every search here is over these rather than over the
    /// cells themselves, because placing a block needs its index.
    def cellIndices(bunker: Bunker): Vector[Int32] =
        Vector.range(0, Vector.length(bunker#cells))

    /// Whether the block at `index` is still standing and overlaps the given box.
    def struckAt(bunker: Bunker, index: Int32, pos: Vec2, size: Vec2): Bool =
        Vector.get(index, bunker#cells)
            and Collide.overlaps(aPos = pos, aSize = size,
                                 bPos = cellCentre(bunker, index), bSize = cellSize())

    def distanceSquared(a: Vec2, b: Vec2): Float32 = {
        let dx = a#x - b#x;
        let dy = a#y - b#y;
        dx * dx + dy * dy
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
    /// `Vector.exists` short-circuits, so the early exit survives the move away from a
    /// hand-written scan; the cost is the index vector `cellIndices` builds per call.
    ///
    def touches(bunker: Bunker, pos: Vec2, size: Vec2): Bool = {
        // Same footprint rejection `contact` opens with, and for the same reason.
        let (centre, footprint) = bounds(bunker);
        Collide.overlaps(aPos = pos, aSize = size, bPos = centre, bSize = footprint)
            and Vector.exists(index -> struckAt(bunker, index, pos, size), cellIndices(bunker))
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
    /// `findMap` stops at the first bunker the shot meets, which is what keeps one shot from
    /// damaging two shelters standing in a line.
    pub def absorb(bunkers: Vector[Bunker], pos: Vec2, size: Vec2, crater: Float32)
        : (Vector[Bunker], Bool) = {
        let struck = which -> {
            let b = Vector.get(which, bunkers);
            contact(b, pos, size) |> Option.map(cell -> (which, cell))
        };
        let bRange = Vector.range(0, Vector.length(bunkers));
        match Vector.findMap(struck, bRange) {
            case None => (bunkers, false)
            case Some((which, cell)) => {
                let bunker = Vector.get(which, bunkers);
                let hitPos = cellCentre(bunker, cell);
                let damagedBunker = damage(bunker, hitPos, crater);
                let updatedBunkers = Vector.update(which, damagedBunker, bunkers);
                (updatedBunkers, true)
            }
        }
    }

    ///
    /// Offers a whole list of bombs to the bunkers, which carry their own crater size.
    ///
    /// Separate from `absorbAll` rather than generalising it: the crater is a property of the
    /// individual bomb here, not of the batch, and threading a per-item function through the
    /// batch version would make the common case -- bullets, all identical -- read worse to
    /// buy nothing.
    ///
    pub def absorbBombs(bunkers: Vector[Bunker], bombs: List[Bomb])
        : (Vector[Bunker], List[Bomb]) = {
        let pass = List.foldLeft((acc, bomb) -> {
            let pos = { x = bomb#x, y = bomb#y };
            let crater = Rules.bombCraterFor(bomb#kind);
            let (damaged, wasHit) = absorb(acc#bunkers, pos, Rules.bombSize(), crater);
            let nextKept = if (wasHit) acc#kept else bomb :: acc#kept;
            { bunkers = damaged, kept = nextKept }
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
    pub def absorbAll(bunkers: Vector[Bunker], shots: List[Vec2],
                      size: Vec2, crater: Float32)
        : (Vector[Bunker], List[Vec2]) = {
        let initAcc = { bunkers = bunkers, kept = (Nil: List[Vec2]) };
        let pass = List.foldLeft((acc, shot) -> {
            let (damaged, wasHit) = absorb(acc#bunkers, shot, size, crater);
            let nextKept = if (wasHit) acc#kept else shot :: acc#kept;
            { bunkers = damaged, kept = nextKept }
        }, initAcc, shots);
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
