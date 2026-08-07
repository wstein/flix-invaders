///
/// One line of the high-score table.
///
pub type alias Entry = { name = String, score = Int32, level = Int32 }

///
/// The high-score table.
///
/// Everything in this module that decides *what* the table contains is pure and needs no
/// handler at all -- parsing, rendering, ordering and qualification are ordinary functions
/// with ordinary tests. Only `load` and `save` touch a filesystem, and they are called from
/// `main` alone.
///
mod Scores {

    /// How many places the table keeps.
    pub def places(): Int32 = 8

    /// How many characters an entry's name may have.
    pub def nameLength(): Int32 = 3

    def separator(): String = "|"

    pub def empty(): List[Entry] = Nil

    ///
    /// Reads one line of the stored format, `NAME|SCORE|LEVEL`.
    ///
    /// A line that does not parse is dropped rather than fatal: a truncated or
    /// hand-edited file should cost you the table, not the game.
    ///
    pub def parseLine(line: String): Option[Entry] =
        match String.splitOn(substr = separator(), line) {
            case name :: score :: level :: Nil =>
                match (Int32.fromString(String.trim(score)), Int32.fromString(String.trim(level))) {
                    case (Some(s), Some(l)) =>
                        Some({ name = clean(String.trim(name)), score = s, level = l })
                    case _ => None
                }
            case _ => None
        }

    pub def parse(lines: List[String]): List[Entry] =
        lines |> List.filterMap(parseLine) |> ranked

    pub def render(entries: List[Entry]): List[String] =
        List.map(e -> "${e#name}${separator()}${e#score}${separator()}${e#level}", entries)

    ///
    /// Sorted best first and capped at `places`.
    ///
    pub def ranked(entries: List[Entry]): List[Entry] =
        entries |> List.sortBy(e -> -e#score) |> List.take(places())

    ///
    /// Whether `score` earns a place.
    ///
    /// A zero never qualifies, however empty the table -- there is no dignity in immortalising
    /// a game you did not play.
    ///
    pub def qualifies(score: Int32, entries: List[Entry]): Bool =
        if (score <= 0) false
        else if (List.length(entries) < places()) true
        else List.exists(e -> score > e#score, entries)

    pub def insert(entry: Entry, entries: List[Entry]): List[Entry] =
        ranked(entry :: entries)

    pub def best(entries: List[Entry]): Int32 =
        List.foldLeft((top, e) -> Int32.max(top, e#score), 0, entries)

    ///
    /// Keeps only the characters the cabinet can display, padded to a fixed width.
    ///
    /// Initials are typed from `keyCode`, which only ever yields A-Z and 0-9, but a file can
    /// contain anything, so this is applied on the way in as well as on the way out.
    ///
    pub def clean(raw: String): String = {
        let kept = raw
            |> String.toList
            |> List.filter(allowed)
            |> List.take(nameLength());
        List.foldLeft((acc, c) -> acc + "${c}", "", kept)
    }

    def allowed(c: Char): Bool =
        (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')

    /// Pads a name out to the full width so the table lines up.
    pub def padded(name: String): String = {
        let missing = nameLength() - String.length(name);
        if (missing <= 0) name
        else name + List.foldLeft((acc, _) -> acc + " ", "", List.range(0, missing))
    }

}
