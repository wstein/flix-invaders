///
/// What one benchmarked game came to.
///
/// `ticks` is here so every other number can be turned into a rate. Totals on their own are
/// what made three separate measurements in this project's history say the opposite of the
/// truth: a change that ends games sooner posts fewer deaths and fewer row drops while being
/// strictly worse, and the totals look like an improvement.
///
pub type alias Outcome = {
    seed = Int64,
    level = Int32,
    score = Int32,
    lives = Int32,
    deaths = Int32,
    kills = Int32,
    drops = Int32,
    ticks = Int32,
    invaded = Bool
}

///
/// Measuring the computer player.
///
/// The demo bot carries a dozen interacting constants -- how wide a bomb has to pass to count
/// as a threat, what standing in cover costs, how long it holds one judgement, when it stops
/// tidying the flanks -- and none of them can be reasoned about reliably in isolation.
/// Widening the threat corridor from 30px to 60px cut deaths sixfold, which no amount of
/// reading the code would have suggested. A more sophisticated dodge, which predicted where
/// the cannon would be when each bomb landed, measured *worse* at every tuning.
///
/// So the constants get measured, not argued about, and this is what does the measuring. Run
/// it with `bin/bench`.
///
/// Everything here is pure except printing. `Game.step` is a pure function and the bot is a
/// pure function of the world and its own hand, so a benchmark is an ordinary fold and its
/// results are exactly reproducible.
///
mod Bench {

    ///
    /// The seeds a run reports on.
    ///
    /// Fixed, and more of them than feels necessary. Bomb luck moves a single seed by two
    /// whole levels, so a change measured on three seeds is measuring noise -- and the
    /// temptation, having got a pleasing number, is to stop.
    ///
    pub def seeds(): List[Int64] =
        2026i64 :: 7i64 :: 99i64 :: 1234i64 :: 555i64 ::
        31i64 :: 17i64 :: 404i64 :: 88i64 :: 5i64 :: Nil

    ///
    /// How long a game may run before it is cut short.
    ///
    /// Generous: a good game ends on its own in well under this, and a benchmark that stops
    /// games itself is measuring its own budget.
    ///
    pub def budget(): Int32 = 30000

    def alive(w: World): Int32 = Vector.count(inv -> inv#alive, w#invaders)

    ///
    /// Plays one whole game and reports what happened.
    ///
    /// The stopping condition is the same for every run -- the game ends, or the budget does.
    /// Nothing is allowed to stop early on a condition that a change under test could itself
    /// affect. Stopping at "level 2 reached" is how a measurement of bunker damage once
    /// reported every bunker perfectly intact: levels reset the bunkers, so the probe was
    /// sampling the state immediately after the reset.
    ///
    pub def one(seed: Int64): Outcome = Sound.runWithNoOp(() -> {
        def loop(left, w, hand, deaths, kills, drops, ticks) =
            if (left <= 0 or w#phase == Phase.Lost)
                { seed = seed, level = w#level, score = w#score, lives = w#lives,
                  deaths = deaths, kills = kills, drops = drops, ticks = ticks,
                  invaded = invasionReached(w) }
            else {
                let (input, next) = Demo.imperfect(w, hand);
                let stepped = Game.step(w, input);
                loop(left - 1, stepped, next,
                     deaths + (if (stepped#lives < w#lives) 1 else 0),
                     kills + (alive(w) - alive(stepped)),
                     drops + (if (stepped#marchDir != w#marchDir) 1 else 0),
                     ticks + 1)
            };
        loop(budget(), Game.initial(seed), Demo.fresh(seed), 0, 0, 0, 0)
    })

    /// Whether the formation reached the cannon's line, as opposed to the lives running out.
    def invasionReached(w: World): Bool =
        Vector.exists(inv -> inv#alive and inv#pos#y >= Rules.invasionLine(), w#invaders)

    pub def all(): List[Outcome] = List.map(one, seeds())

    // -- reading the results ----------------------------------------------------------------
    //
    // Pure arithmetic on the outcomes, and the part worth testing: getting a rate wrong is how
    // a measurement lies convincingly.

    /// Mean level, in tenths, so it can be reported without floating point.
    pub def meanLevelTenths(runs: List[Outcome]): Int32 =
        if (List.isEmpty(runs)) 0
        else (List.foldLeft((total, r) -> total + r#level, 0, runs) * 10) / List.length(runs)

    pub def worstLevel(runs: List[Outcome]): Int32 =
        List.foldLeft((worst, r) -> Int32.min(worst, r#level), Int32.maxValue(), runs)

    pub def bestLevel(runs: List[Outcome]): Int32 =
        List.foldLeft((best, r) -> Int32.max(best, r#level), 0, runs)

    pub def totalTicks(runs: List[Outcome]): Int32 =
        List.foldLeft((total, r) -> total + r#ticks, 0, runs)

    ///
    /// A count per thousand ticks of play, in tenths.
    ///
    /// Always compare rates. Two configurations that end their games at different times cannot
    /// be compared on totals, and the difference in when they end is usually the very thing
    /// being measured.
    ///
    /// Tenths because whole numbers are not enough resolution for the rarest event that
    /// matters: deaths run at well under one per thousand ticks, so rounding to units reports
    /// the good bot and the bad bot alike as zero.
    ///
    pub def rateTenths(count: Int32, ticks: Int32): Int32 =
        if (ticks <= 0) 0 else (count * 10000) / ticks

    /// A tenths value as `X.Y`.
    pub def showTenths(tenths: Int32): String =
        "${tenths / 10}.${Int32.remainder(tenths, 10)}"

    pub def deaths(runs: List[Outcome]): Int32 =
        List.foldLeft((total, r) -> total + r#deaths, 0, runs)

    pub def kills(runs: List[Outcome]): Int32 =
        List.foldLeft((total, r) -> total + r#kills, 0, runs)

    pub def drops(runs: List[Outcome]): Int32 =
        List.foldLeft((total, r) -> total + r#drops, 0, runs)

    /// How many games ended with the formation landing rather than the lives running out.
    pub def invasions(runs: List[Outcome]): Int32 =
        List.count(r -> r#invaded, runs)

    /// How many games hit the budget instead of finishing, which invalidates the run.
    pub def unfinished(runs: List[Outcome]): Int32 =
        List.count(r -> r#ticks >= budget(), runs)

    // -- reporting --------------------------------------------------------------------------

    def pad(text: String, width: Int32): String = {
        let missing = width - String.length(text);
        if (missing <= 0) text
        else List.foldLeft((acc, _) -> acc + " ", "", List.range(0, missing)) + text
    }

    def row(r: Outcome): String =
        pad("${r#seed}", 6) + pad("${r#level}", 7) + pad("${r#score}", 8) +
        pad("${r#lives}", 7) + pad("${r#deaths}", 8) + pad("${r#kills}", 7) +
        pad("${r#ticks}", 8) + "  " + (if (r#invaded) "invaded" else "out of lives")

    ///
    /// Runs every seed and prints the table.
    ///
    pub def main(): Unit \ IO = {
        let runs = all();
        let ticks = totalTicks(runs);

        println("Bot benchmark -- ${List.length(seeds())} seeds, budget ${budget()} ticks");
        println("");
        println(pad("seed", 6) + pad("level", 7) + pad("score", 8) + pad("lives", 7)
              + pad("deaths", 8) + pad("kills", 7) + pad("ticks", 8) + "  ended by");
        List.forEach(r -> println(row(r)), runs);
        println("");

        println("  mean level      ${showTenths(meanLevelTenths(runs))}"
              + "   (worst ${worstLevel(runs)}, best ${bestLevel(runs)})");
        println("  deaths          ${deaths(runs)} = ${showTenths(rateTenths(deaths(runs), ticks))} per 1000 ticks");
        println("  kills           ${kills(runs)} = ${showTenths(rateTenths(kills(runs), ticks))} per 1000 ticks");
        println("  row drops       ${drops(runs)} = ${showTenths(rateTenths(drops(runs), ticks))} per 1000 ticks");
        println("  ended by        ${invasions(runs)} invaded, "
              + "${List.length(runs) - invasions(runs)} out of lives");

        // A game still running when the budget expired has not been measured, it has been
        // interrupted, and every rate above is then a rate of something else.
        let cut = unfinished(runs);
        if (cut > 0)
            println("  WARNING         ${cut} game(s) hit the budget and were cut short; "
                  + "raise budget() before trusting these numbers")
        else ()
    }

}
