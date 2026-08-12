///
/// Reading and writing the demo player's numbers.
///
/// Laid out like `Scores`, and for the same reason: deciding *what* a tuning is stays pure and
/// needs no handler to test, and only `load` and `save` touch a filesystem.
///
/// The file is JSON because it is meant to be edited by hand as well as by `bin/bench
/// --recalc`. Every field is optional on the way in and falls back to the shipped default, so
/// a file naming one parameter is a valid file -- which is what you want when trying a single
/// change, and it means a config written by an older build still loads.
///
/// `stragglers` is the one number that is *not* in the file, in either direction. It decides
/// whether the bot finishes off a flank column at all, and switching it off is worth about
/// half a level -- so a search that is allowed to write it turns it off, and a config carrying
/// that then silently removes the behaviour from the game. It did exactly that once: the demo
/// went back to leaving the formation at full width, and the cause was a stale config rather
/// than any code. Tuned numbers live in the file; decisions about how the demo behaves live in
/// `Demo.defaults`, where changing them is a visible edit. Ignoring the key on the way in also
/// means the configs already written with it recover on their own.
///
mod Tuning {

    use Util.Json.Json

    def fileName(): String = "tuning.json"

    // -- rendering ---------------------------------------------------------------------------

    ///
    /// The tuning as JSON, in a fixed and readable order.
    ///
    /// Hand-rendered rather than built through `Json`, so the file keeps the grouping a reader
    /// needs -- aim, attention, movement, danger, targeting -- instead of the alphabetical key
    /// order a `Map` would impose.
    ///
    def aimGroup(t: Tuning): List[String] =
        "  \"aimJitter\":        ${t#aimJitter}," ::
        "  \"judgeFor\":         ${t#judgeFor}," ::
        "  \"judgeSpread\":      ${t#judgeSpread}," :: Nil

    def lapseGroup(t: Tuning): List[String] =
        "  \"lapseOneIn\":       ${t#lapseOneIn}," ::
        "  \"lapseFor\":         ${t#lapseFor}," ::
        "  \"lapseSpread\":      ${t#lapseSpread}," :: Nil

    def movementGroup(t: Tuning): List[String] =
        "  \"startAt\":          ${t#startAt}," ::
        "  \"reverseAt\":        ${t#reverseAt}," :: Nil

    def dangerGroup(t: Tuning): List[String] =
        "  \"dangerWidth\":      ${t#dangerWidth}," ::
        "  \"selfPreservation\": ${t#selfPreservation}," ::
        "  \"urgency\":          ${t#urgency}," ::
        "  \"shelterRelief\":    ${t#shelterRelief}," ::
        "  \"blockedCost\":      ${t#blockedCost}," :: Nil

    def targetGroup(t: Tuning): List[String] =
        "  \"calm\":             ${t#calm}," ::
        "  \"finishFlank\":      ${t#finishFlank}," ::
        "  \"narrowTo\":         ${t#narrowTo}," ::
        "  \"narrowing\":        ${t#narrowing}," ::
        "  \"fireWindow\":       ${t#fireWindow}," ::
        "  \"imminence\":        ${t#imminence}" :: Nil

    /// Encodes a Tuning configuration record into formatted JSON text.
    pub def encode(t: Tuning): String =
        String.unlines("{" :: (aimGroup(t) ::: "" :: lapseGroup(t) ::: "" :: movementGroup(t) ::: "" :: dangerGroup(t) ::: "" :: targetGroup(t)) ::: "}" :: Nil)

    // -- reading -----------------------------------------------------------------------------

    /// The fields of a JSON object, or `None` if it is not one.
    def fields(text: String): Option[Map[String, Json]] =
        match Util.Json.parse(text) {
            case Ok(Json.JObject(members)) => Some(members)
            case _ => None
        }

    /// A numeric field, or `fallback` when it is absent or not a number.
    def number(members: Map[String, Json], key: String, fallback: Float32): Float32 =
        match Map.get(key, members) {
            case Some(Json.JNumber(value)) => Option.getWithDefault(fallback, BigDecimal.tryToFloat32(value))
            case _ => fallback
        }

    def whole(members: Map[String, Json], key: String, fallback: Int32): Int32 =
        match Map.get(key, members) {
            case Some(Json.JNumber(value)) => Option.getWithDefault(fallback, BigDecimal.tryToInt32(value))
            case _ => fallback
        }

    ///
    /// Reads a tuning, filling anything missing from `base`.
    ///
    /// Only malformed *JSON* is an error. A field that is absent, or present with the wrong
    /// kind of value, quietly takes the default: this file is a set of overrides, and a typo in
    /// one number should cost you that number rather than the whole run.
    ///
    pub def decode(base: Tuning, text: String): Result[String, Tuning] =
        match fields(text) {
            case None => Err("not a JSON object")
            case Some(members) => Ok({
                aimJitter = whole(members, "aimJitter", base#aimJitter),
                judgeFor = whole(members, "judgeFor", base#judgeFor),
                judgeSpread = whole(members, "judgeSpread", base#judgeSpread),
                lapseOneIn = whole(members, "lapseOneIn", base#lapseOneIn),
                lapseFor = whole(members, "lapseFor", base#lapseFor),
                lapseSpread = whole(members, "lapseSpread", base#lapseSpread),
                startAt = number(members, "startAt", base#startAt),
                reverseAt = number(members, "reverseAt", base#reverseAt),
                dangerWidth = number(members, "dangerWidth", base#dangerWidth),
                selfPreservation = number(members, "selfPreservation", base#selfPreservation),
                urgency = number(members, "urgency", base#urgency),
                shelterRelief = number(members, "shelterRelief", base#shelterRelief),
                blockedCost = number(members, "blockedCost", base#blockedCost),
                calm = number(members, "calm", base#calm),
                // Not read from the file, and not written to it. See below.
                stragglers = base#stragglers,
                finishFlank = number(members, "finishFlank", base#finishFlank),
                narrowTo = number(members, "narrowTo", base#narrowTo),
                narrowing = number(members, "narrowing", base#narrowing),
                fireWindow = number(members, "fireWindow", base#fireWindow),
                imminence = number(members, "imminence", base#imminence)
            })
        }

    ///
    /// A tuning with every number forced into a range the bot can actually use.
    ///
    /// A hand-edited file, or a search that wandered, can otherwise produce a bot that never
    /// fires or never moves. Clamping is quieter than refusing: the file stays editable and the
    /// game still starts.
    ///
    def within(low: Int32, high: Int32, value: Int32): Int32 =
        Int32.max(low, Int32.min(high, value))

    def withinF(low: Float32, high: Float32, value: Float32): Float32 =
        Float32.max(low, Float32.min(high, value))

    /// Clamps all values of a Tuning record to their legal bounds to prevent unplayable state.
    pub def sane(t: Tuning): Tuning = {
        aimJitter = within(0, 60, t#aimJitter),
        judgeFor = within(1, 300, t#judgeFor),
        judgeSpread = within(1, 300, t#judgeSpread),
        lapseOneIn = within(1, 100000, t#lapseOneIn),
        lapseFor = within(0, 120, t#lapseFor),
        lapseSpread = within(1, 120, t#lapseSpread),
        startAt = withinF(0.1f32, 60.0f32, t#startAt),
        reverseAt = withinF(0.1f32, 120.0f32, t#reverseAt),
        dangerWidth = withinF(1.0f32, 320.0f32, t#dangerWidth),
        selfPreservation = withinF(0.0f32, 200.0f32, t#selfPreservation),
        urgency = withinF(1.0f32, 2000.0f32, t#urgency),
        shelterRelief = withinF(0.0f32, 1.0f32, t#shelterRelief),
        blockedCost = withinF(0.0f32, 100.0f32, t#blockedCost),
        calm = withinF(0.0f32, 1.0f32, t#calm),
        stragglers = within(0, 6, t#stragglers),
        finishFlank = withinF(0.0f32, 20.0f32, t#finishFlank),
        narrowTo = withinF(0.0f32, 1.0f32, t#narrowTo),
        narrowing = withinF(0.0f32, 20.0f32, t#narrowing),
        // Below 1 the bot may only take shots the geometry guarantees, which measures far
        // worse; above 20 the window covers the field and it fires at empty sky.
        fireWindow = withinF(1.0f32, 20.0f32, t#fireWindow),
        // At 0 the bot ignores how far down a target has come, which is the one thing that
        // ends games.
        imminence = withinF(0.1f32, 40.0f32, t#imminence)
    }

    // -- where it lives ------------------------------------------------------------------------

    /// The default path, beside the high scores.
    pub def path(): Option[String] \ Sys.Env =
        Option.map(at -> "${at#dir}${Sys.Env.getFileSeparator()}${fileName()}", Scores.location())

    ///
    /// Reads the tuning at `file`, or the shipped defaults if there is not one yet.
    ///
    pub def load(file: String): Result[String, Tuning] \ Fs.FileRead =
        match Fs.FileRead.read(file) {
            case Ok(text) => Result.map(sane, decode(Demo.defaults(), text))
            case Err(IoError.IoError(IoError.ErrorKind.NotFound, _)) => Ok(Demo.defaults())
            case Err(other) => Err("${other}")
        }

    /// Serializes and writes a Tuning configuration record to disk at the specified path.
    pub def save(file: String, dir: String, t: Tuning): Result[String, Unit] \ Fs.FileWrite =
        Fs.FileWrite.mkDirs(dir)
            |> Result.flatMap(_ -> Fs.FileWrite.write(str = encode(t), file))
            |> Result.mapErr(why -> "${why}")

}
