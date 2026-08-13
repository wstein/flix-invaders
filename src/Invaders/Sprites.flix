///
/// Pixel art, as data.
///
/// A sprite is written out as rows of text -- `#` for a lit pixel, anything else for empty --
/// so the artwork is legible in the source and can be edited without a drawing tool. There
/// are no image files anywhere in this project.
///
/// Each row is collapsed into horizontal runs of lit pixels, and drawing emits one rectangle
/// per run rather than one per pixel -- roughly a quarter of the draw calls. The runs are
/// computed once, by `Sprite.of`, and stored: parsing the text on every frame for every
/// invader was enough to halve the frame rate.
///
pub enum Sprite({
    width = Int32,
    height = Int32,
    rows = Vector[String],
    runs = List[(Int32, Int32, Int32)]
})

mod Sprite {

    /// Marks a lit pixel.
    def lit(): Char = '#'

    ///
    /// Builds a sprite from rows of text. The width is the longest row.
    ///
    pub def of(rows: Vector[String]): Sprite = {
        let findMaxW = (widest, row) ->
            Int32.max(widest, String.length(row));
        let maxW = Vector.foldLeft(findMaxW, 0, rows);
        let h = Vector.length(rows);
        let parsedRuns = parse(rows);
        Sprite.Sprite({ width = maxW, height = h, rows = rows, runs = parsedRuns })
    }

    /// The sprite's width in cells -- the longest row.
    pub def width(sprite: Sprite): Int32 = match sprite {
        case Sprite.Sprite(r) => r#width
    }

    /// The sprite's height in cells.
    pub def height(sprite: Sprite): Int32 = match sprite {
        case Sprite.Sprite(r) => r#height
    }

    /// The rows of text the sprite was built from.
    pub def rows(sprite: Sprite): Vector[String] = match sprite {
        case Sprite.Sprite(r) => r#rows
    }

    /// Closes off a run that was in progress, if any.
    def close(y: Int32, x: Int32,
              start: Option[Int32], acc: List[(Int32, Int32, Int32)])
        : List[(Int32, Int32, Int32)] =
        match start {
            case None => acc
            case Some(startX) =>
                let len = x - startX;
                (y, startX, len) :: acc
        }

    ///
    /// The horizontal runs of lit pixels in one row, as `(row, startColumn, length)`.
    ///
    def rowRuns(y: Int32,
                cells: List[Char]): List[(Int32, Int32, Int32)] = {
        let initScan = { column = 0, start = (None: Option[Int32]), runs = Nil };
        let stepScan = (scan, cell) ->
            if (cell == lit())
                let nextCol = scan#column + 1;
                let startCol = Option.getWithDefault(scan#column, scan#start);
                { column = nextCol, start = Some(startCol) | scan }
            else {
                let nextCol = scan#column + 1;
                let closedRuns = close(y, scan#column, scan#start, scan#runs);
                { column = nextCol, start = None, runs = closedRuns | scan }
            };
        let scanned = List.foldLeft(stepScan, initScan, cells);
        let finalRuns = close(y, scanned#column, scanned#start, scanned#runs);
        List.reverse(finalRuns)
    }

    /// Collapses every row into runs. Called once per sprite, by `of`.
    def parse(rows: Vector[String]): List[(Int32, Int32, Int32)] =
        Vector.toList(rows)
            |> List.mapWithIndex((y, row) -> rowRuns(y, String.toList(row)))
            |> List.flatten

    ///
    /// Every lit run in the sprite, as `(row, startColumn, length)`, top row first.
    ///
    pub def runs(sprite: Sprite): List[(Int32, Int32, Int32)] = match sprite {
        case Sprite.Sprite(r) => r#runs
    }

    ///
    /// The number of lit pixels. Handy for tests; not used when drawing.
    ///
    pub def litPixels(sprite: Sprite): Int32 =
        List.foldLeft((total, segment) -> {
            let (_, _, length) = segment;
            total + length
        }, 0, runs(sprite))

    ///
    /// Draws a sprite centred on `centre`, stretched independently in each axis.
    ///
    /// Separate axes so a shape can be made wide without also becoming tall -- which is what
    /// a flying saucer wants and a square pixel does not give you.
    ///
    /// The two scales are named: they are both `Float32`, and swapping them silently
    /// transposes the sprite.
    pub def drawScaled(sprite: Sprite, centre: Vec2,
                       scaleX: {scaleX = Float32}, scaleY: {scaleY = Float32}
    ): Unit \ Canvas = {
        let sx = scaleX#scaleX;
        let sy = scaleY#scaleY;
        let left = centre#x - Int32.toFloat32(width(sprite)) * sx / 2.0f32;
        let top = centre#y - Int32.toFloat32(height(sprite)) * sy / 2.0f32;
        List.forEach(segment -> {
            let (y, x, length) = segment;
            Canvas.rect(left + Int32.toFloat32(x) * sx,
                        top + Int32.toFloat32(y) * sy,
                        Int32.toFloat32(length) * sx,
                        sy)
        }, runs(sprite))
    }

    ///
    /// Draws a sprite centred on `centre`, with each sprite pixel `scale` screen pixels wide.
    ///
    pub def draw(sprite: Sprite, centre: Vec2, scale: Float32): Unit \ Canvas =
        drawScaled(sprite, centre, scaleX = scale, scaleY = scale)

}

///
/// The artwork.
///
/// Each invader has two frames. Alternating between them as the formation marches is what
/// makes them look like they are walking -- the original does exactly this, and it is the
/// whole animation budget of the game.
///
mod Sprites {

    /// Top row invader (squid), animation frame A.
    pub def squidA(): Sprite = Sprite.of(Vector#{
        "...##...",
        "..####..",
        ".######.",
        "##.##.##",
        "########",
        "..#..#..",
        ".#.##.#.",
        "#.#..#.#"
    })

    /// Top row invader (squid), animation frame B.
    pub def squidB(): Sprite = Sprite.of(Vector#{
        "...##...",
        "..####..",
        ".######.",
        "##.##.##",
        "########",
        ".#.##.#.",
        "#......#",
        ".#....#."
    })

    /// Middle row invader (crab), animation frame A.
    pub def crabA(): Sprite = Sprite.of(Vector#{
        "..#.....#..",
        "...#...#...",
        "..#######..",
        ".##.###.##.",
        "###########",
        "#.#######.#",
        "#.#.....#.#",
        "...##.##..."
    })

    /// Middle row invader (crab), animation frame B.
    pub def crabB(): Sprite = Sprite.of(Vector#{
        "..#.....#..",
        "#..#...#..#",
        "#.#######.#",
        "###.###.###",
        "###########",
        ".#########.",
        "..#.....#..",
        ".#.......#."
    })

    /// Bottom row invader (octopus), animation frame A.
    pub def octopusA(): Sprite = Sprite.of(Vector#{
        "....####....",
        ".##########.",
        "############",
        "###..##..###",
        "############",
        "...##..##...",
        "..##.##.##..",
        ".##......##."
    })

    /// Bottom row invader (octopus), animation frame B.
    pub def octopusB(): Sprite = Sprite.of(Vector#{
        "....####....",
        ".##########.",
        "############",
        "###..##..###",
        "############",
        "..##.##.##..",
        ".##......##.",
        "..##....##.."
    })

    /// Player defense cannon sprite.
    pub def cannon(): Sprite = Sprite.of(Vector#{
        "......#......",
        ".....###.....",
        ".....###.....",
        ".###########.",
        "#############",
        "#############",
        "#############",
        "#############"
    })

    /// Single laser bullet fired by player cannon.
    pub def bullet(): Sprite = Sprite.of(Vector#{
        "#",
        "#",
        "#",
        "#",
        "#",
        "#"
    })

    /// The invaders' bomb, which tumbles as it falls. The common, slow one.
    pub def bomb(): Sprite = Sprite.of(Vector#{
        ".#.",
        "..#",
        ".#.",
        "#..",
        ".#.",
        "..#",
        ".#."
    })

    ///
    /// The fast bomb: a dagger, drawn straight so its speed reads as purpose.
    ///
    /// The three bombs have to be told apart at a glance while the screen is busy, and the
    /// only channels available are shape and motion -- they are all one colour. A vertical
    /// bar against the tumbler's zigzag is the largest difference two three-pixel-wide
    /// sprites can carry.
    ///
    pub def bombFast(): Sprite = Sprite.of(Vector#{
        ".#.",
        ".#.",
        ".#.",
        ".#.",
        ".#.",
        "###",
        ".#."
    })

    /// The wiggler: a wide zigzag, the one that tears the biggest hole in a shelter.
    pub def bombWiggly(): Sprite = Sprite.of(Vector#{
        "#..",
        ".#.",
        "..#",
        ".#.",
        "#..",
        ".#.",
        "..#"
    })

    /// The sprite for a bomb of the given kind.
    pub def bombFor(kind: BombKind): Sprite = match kind {
        case BombKind.Slow => bomb()
        case BombKind.Fast => bombFast()
        case BombKind.Wiggly => bombWiggly()
    }

    ///
    /// The mystery ship that crosses the top of the screen.
    ///
    pub def mystery(): Sprite = Sprite.of(Vector#{
        ".....######.....",
        "...##########...",
        "..############..",
        ".##.##.##.##.##.",
        "################",
        "..###..##..###..",
        "...##......##..."
    })

    ///
    /// The starburst an invader leaves behind.
    ///
    pub def invaderBlast(): Sprite = Sprite.of(Vector#{
        "....#...#....",
        "#...#...#...#",
        ".#.#.....#.#.",
        "..#..###..#..",
        "###..###..###",
        "..#..###..#..",
        ".#.#.....#.#.",
        "#...#...#...#"
    })

    ///
    /// The cannon coming apart, in two frames so the debris flickers.
    ///
    pub def playerBlastA(): Sprite = Sprite.of(Vector#{
        "..#.#...#.#..",
        "#...#.#.#...#",
        ".#.#..#..#.#.",
        "#..####.##..#",
        ".###########.",
        "#############",
        ".#.#######.#.",
        "#.#.#####.#.#"
    })

    /// Explosion artwork for player destruction, frame B.
    pub def playerBlastB(): Sprite = Sprite.of(Vector#{
        "#.#...#...#.#",
        "..#.#...#.#..",
        "#..#..#..#..#",
        ".#.##.#.##.#.",
        "#.#########.#",
        ".###########.",
        "#.#.#####.#.#",
        ".#.#.###.#.#."
    })

    ///
    /// The frame for a blast, given how many ticks of it are left.
    ///
    pub def forBlast(kind: BlastKind, ticksLeft: Int32): Sprite = match kind {
        case BlastKind.InvaderBlast => invaderBlast()
        case BlastKind.PlayerBlast =>
            if (Int32.remainder(ticksLeft / 6, 2) == 0) playerBlastA() else playerBlastB()
    }

    ///
    /// The frame for an invader of `kind`, alternating on `frame`.
    ///
    pub def forKind(kind: InvaderKind, frame: Int32): Sprite = {
        let first = Int32.remainder(frame, 2) == 0;
        match kind {
            case InvaderKind.Squid => if (first) squidA() else squidB()
            case InvaderKind.Crab => if (first) crabA() else crabB()
            case InvaderKind.Octopus => if (first) octopusA() else octopusB()
        }
    }

}
