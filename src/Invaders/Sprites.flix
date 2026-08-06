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
pub type alias Sprite = {
    width = Int32,
    height = Int32,
    rows = Vector[String],
    runs = List[(Int32, Int32, Int32)]
}

mod Sprite {

    /// Marks a lit pixel.
    def lit(): Char = '#'

    ///
    /// Builds a sprite from rows of text. The width is the longest row.
    ///
    pub def of(rows: Vector[String]): Sprite =
        { width = Vector.foldLeft((widest, row) -> Int32.max(widest, String.length(row)), 0, rows),
          height = Vector.length(rows),
          rows = rows,
          runs = parse(rows) }

    /// Closes off a run that was in progress, if any.
    def close(y: Int32, x: Int32, start: Option[Int32], acc: List[(Int32, Int32, Int32)]): List[(Int32, Int32, Int32)] =
        match start {
            case None => acc
            case Some(startX) => (y, startX, x - startX) :: acc
        }

    ///
    /// The horizontal runs of lit pixels in one row, as `(row, startColumn, length)`.
    ///
    def rowRuns(y: Int32, cells: List[Char]): List[(Int32, Int32, Int32)] = {
        def go(x, start, acc, rest) = match rest {
            case Nil => close(y, x, start, acc)
            case cell :: more =>
                if (cell == lit())
                    go(x + 1, (match start {
                        case None => Some(x)
                        case some => some
                    }), acc, more)
                else
                    go(x + 1, None, close(y, x, start, acc), more)
        };
        List.reverse(go(0, None, Nil, cells))
    }

    /// Collapses every row into runs. Called once per sprite, by `of`.
    def parse(rows: Vector[String]): List[(Int32, Int32, Int32)] =
        Vector.toList(rows)
            |> List.mapWithIndex((y, row) -> rowRuns(y, String.toList(row)))
            |> List.flatten

    ///
    /// Every lit run in the sprite, as `(row, startColumn, length)`, top row first.
    ///
    pub def runs(sprite: Sprite): List[(Int32, Int32, Int32)] = sprite#runs

    ///
    /// The number of lit pixels. Handy for tests; not used when drawing.
    ///
    pub def litPixels(sprite: Sprite): Int32 =
        List.foldLeft((total, segment) -> {
            let (_, _, length) = segment;
            total + length
        }, 0, runs(sprite))

    ///
    /// Draws a sprite centred on `centre`, with each sprite pixel `scale` screen pixels wide.
    ///
    pub def draw(sprite: Sprite, centre: Vec2, scale: Float32): Unit \ Canvas = {
        let left = centre#x - Int32.toFloat32(sprite#width) * scale / 2.0f32;
        let top = centre#y - Int32.toFloat32(sprite#height) * scale / 2.0f32;
        List.forEach(segment -> {
            let (y, x, length) = segment;
            Canvas.rect(left + Int32.toFloat32(x) * scale,
                        top + Int32.toFloat32(y) * scale,
                        Int32.toFloat32(length) * scale,
                        scale)
        }, runs(sprite))
    }

}

///
/// The artwork.
///
/// Each invader has two frames. Alternating between them as the formation marches is what
/// makes them look like they are walking -- the original does exactly this, and it is the
/// whole animation budget of the game.
///
mod Sprites {

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

    pub def bullet(): Sprite = Sprite.of(Vector#{
        "#",
        "#",
        "#",
        "#",
        "#",
        "#"
    })

    /// The invaders' bomb, which tumbles as it falls.
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
