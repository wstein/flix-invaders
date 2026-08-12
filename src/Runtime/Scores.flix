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
    pub def places(): Int32 = 12

    /// How many characters an entry's name may have.
    pub def nameLength(): Int32 = 3

    def separator(): String = "|"

    /// An empty high score table with no entries.
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

    /// Parses a list of lines from disk into a ranked high score table.
    pub def parse(lines: List[String]): List[Entry] =
        lines |> List.filterMap(parseLine) |> ranked

    /// Renders a list of high score entries into serializable line strings.
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

    /// Inserts a new high score entry into the table and returns the re-ranked list.
    pub def insert(entry: Entry, entries: List[Entry]): List[Entry] =
        ranked(entry :: entries)

    /// Returns the highest score value currently in the high score table, or 0 if empty.
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

    // -- where the table lives ------------------------------------------------------------
    //
    // Everything above this line is arithmetic on data. Everything below touches a real
    // filesystem, and is called from `main` alone.

    def folder(): String = "flix-invaders"

    def fileName(): String = "scores.txt"

    ///
    /// Where the table is kept: the file, and the directory that must exist to hold it.
    ///
    /// Both, rather than just the file, because saving has to create the directory on a first
    /// run. Carrying the directory alongside is honest about what was built; recovering it by
    /// hunting for the last separator in the path would be guesswork about a string we
    /// assembled ourselves.
    ///
    pub type alias Location = { dir = String, file = String }

    ///
    /// Where the table lives, by the XDG convention.
    ///
    /// `$XDG_CONFIG_HOME/flix-invaders` when that is set, otherwise
    /// `~/.config/flix-invaders`. `None` on a machine with neither -- there is nowhere
    /// sensible to put it, and inventing somewhere is worse than going without.
    ///
    pub def location(): Option[Location] \ Sys.Env = {
        let separator = Sys.Env.getFileSeparator();
        let configured =
            Sys.Env.getVar("XDG_CONFIG_HOME") |> Option.filter(dir -> not String.isEmpty(dir));
        let fallback =
            Sys.Env.getUserHomeDirectory() |> Option.map(home -> "${home}${separator}.config");
        Option.withDefault(default = fallback, configured)
            |> Option.map(base -> {
                let dir = "${base}${separator}${folder()}";
                { dir = dir, file = "${dir}${separator}${fileName()}" }
            })
    }

    ///
    /// Reads the table, or an empty one if there is not a file yet.
    ///
    /// A missing file is the ordinary first run and yields `Ok(Nil)`. Every other error is
    /// returned rather than swallowed: a table you have no permission to read is not the same
    /// as no scores, and quietly treating it as one would let the next save overwrite
    /// somebody's table with nothing.
    ///
    pub def load(at: Location): Result[IoError, List[Entry]] \ Fs.FileRead =
        match Fs.FileRead.readLines(at#file) {
            case Ok(lines) => Ok(parse(lines))
            case Err(IoError.IoError(IoError.ErrorKind.NotFound, _)) => Ok(Nil)
            case Err(other) => Err(other)
        }

    ///
    /// Writes the table, creating the directory if this is the first run.
    ///
    /// `mkDirs` is content when the directory already exists, so there is no existence check
    /// here -- one would be redundant, and racy besides.
    ///
    pub def save(at: Location, entries: List[Entry]): Result[IoError, Unit] \ Fs.FileWrite =
        Fs.FileWrite.mkDirs(at#dir)
            |> Result.flatMap(_ -> Fs.FileWrite.writeLines(lines = render(ranked(entries)), at#file))

}
