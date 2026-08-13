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
    invaded = Bool,
    endgame = Endgame
}

/// The bot's movement and progress while eight or fewer invaders remain in a formation.
pub type alias Endgame = { pixels = Float32, ticks = Int32, kills = Int32 }

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
/// The measurement itself is pure: `one` discharges `Game.step`'s `Sound` effect with
/// `Sound.runWithNoOp`, and the bot is a pure function of the world and its own hand. Given a
/// tuning and its fixed seeds, the benchmark is an ordinary fold with reproducible results.
///
mod Bench {

    use Util.GetOpt.{ArgDescr, ArgOrder, OptionDescr, getOpt1, usageInfo}

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
    /// Sixty seeds, for deciding rather than for iterating.
    ///
    /// Ten games separate things that differ by a level. They do not separate things that
    /// differ by a third of one, which is the size of every honest improvement this bot has
    /// had -- and on the ten above, the narrowing rule scores 4.6 against a 4.9 baseline while
    /// on these it scores 4.95 against 4.52. A change adopted on ten seeds was adopted on a
    /// coin toss.
    ///
    /// Two families rather than one long run of a single multiplier, so a result cannot be an
    /// artifact of how the seeds were generated. They are deliberately not the ten above: the
    /// recorded figures in `docs/ARCHITECTURE.md` are on those, and a sample that quietly
    /// changed underneath them would make every number in that file incomparable.
    ///
    pub def wideSeeds(): List[Int64] = {
        let thirty = List.range(1, 31);
        let scaled = factor -> List.map(n -> Int32.toInt64(n) * factor, thirty);
        let firstHalf = scaled(7919i64);
        let secondHalf = scaled(104729i64);
        firstHalf ::: secondHalf
    }

    ///
    /// How long a game may run before it is cut short.
    ///
    /// Generous: a good game ends on its own in well under this, and a benchmark that stops
    /// games itself is measuring its own budget.
    ///
    pub def budget(): Int32 = 30000

    def alive(w: World): Int32 = Vector.count(inv -> inv#alive, w#invaders)

    def emptyEndgame(): Endgame = { pixels = 0.0f32, ticks = 0, kills = 0 }

    ///
    /// A tick the bot can act on, with eight or fewer invaders left.
    ///
    /// All three figures are gated on the same condition, so they describe one regime. Counting
    /// ticks more loosely -- during the death pause, or through the three-second wait after a
    /// formation is cleared -- swept in frozen time when no kill was possible: 6120 of 21161,
    /// 29%, which reported 72 ticks per kill where live play costs 51. Worse than inflated, it
    /// was *confounded*, because a change that clears more levels buys more frozen ticks and
    /// looks slower for it.
    ///
    def activelyInEndgame(w: World): Bool =
        w#phase == Phase.Playing and w#pause == 0 and alive(w) <= 8

    def observeEndgame(before: World, after: World, endgame: Endgame): Endgame =
        if (not activelyInEndgame(before)) endgame
        else
            { pixels = endgame#pixels + Float32.abs(after#playerX - before#playerX),
              ticks = endgame#ticks + 1,
              // A cleared formation is restored to 55, which would read as negative kills.
              kills = endgame#kills + Int32.max(0, alive(before) - alive(after)) }

    type alias BenchAccumulator = { deaths = Int32,
                                    kills = Int32,
                                    drops = Int32,
                                    ticks = Int32,
                                    endgame = Endgame }

    ///
    /// One run in progress: the ticks left in its budget, the world, the bot's hand, and the
    /// figures gathered so far.
    ///
    type alias BenchState = { left = Int32, world = World, hand = Hand, acc = BenchAccumulator }

    ///
    /// One tick of a run: the bot decides, the world steps, and the figures take note.
    ///
    /// Kills and row drops are counted only while the level does not change, because a cleared
    /// formation is replaced wholesale -- counting across that boundary reads the restock as
    /// fifty-five invaders coming back to life.
    ///
    def stepBench(tuning: Tuning, st: BenchState): BenchState \ Sound = {
        let w = st#world;
        let acc = st#acc;
        let (input, nextHand) = Demo.imperfect(tuning, w, st#hand);
        let stepped = Game.step(w, input);
        let sameLevel = stepped#level == w#level;
        let nextAcc = {
            deaths = acc#deaths + (if (stepped#lives < w#lives) 1 else 0),
            kills = acc#kills + (if (sameLevel) alive(w) - alive(stepped) else 0),
            drops = acc#drops + (if (sameLevel and stepped#marchDir != w#marchDir) 1 else 0),
            ticks = acc#ticks + 1,
            endgame = observeEndgame(w, stepped, acc#endgame)
        };
        { left = st#left - 1, world = stepped, hand = nextHand, acc = nextAcc }
    }

    ///
    /// Plays one whole game and reports what happened.
    ///
    /// The stopping condition is the same for every run -- the game ends, or the budget does.
    /// Nothing is allowed to stop early on a condition that a change under test could itself
    /// affect. Stopping at "level 2 reached" is how a measurement of bunker damage once
    /// reported every bunker perfectly intact: levels reset the bunkers, so the probe was
    /// sampling the state immediately after the reset.
    ///
    /// A run that ends on the budget is reported as unfinished rather than as a result: it was
    /// interrupted, not measured. See `unfinished`.
    ///
    pub def one(tuning: Tuning, seed: Int64): Outcome = Sound.runWithNoOp(() -> {
        // A recursion rather than a fold over the budget: this stops when the *game* ends,
        // which is usually a third of the way in. Folding `budget()` steps would keep calling
        // a no-op stage for the remaining twenty thousand ticks of every run.
        def loop(st: BenchState) = {
            let done = st#left <= 0 or st#world#phase == Phase.Lost;
            if (done) {
                let endg = st#acc#endgame;
                let reached = invasionReached(st#world);
                let w = st#world;
                let a = st#acc;
                { seed = seed, level = w#level, score = w#score,
                  lives = w#lives, deaths = a#deaths, kills = a#kills,
                  drops = a#drops, ticks = a#ticks,
                  invaded = reached, endgame = endg }
            } else
                loop(stepBench(tuning, st))
        };
        let initAcc = { deaths = 0,
                        kills = 0,
                        drops = 0,
                        ticks = 0,
                        endgame = emptyEndgame() };
        loop({ left = budget(),
               world = Game.initial(seed),
               hand = Demo.fresh(seed),
               acc = initAcc })
    })

    /// Whether the formation reached the cannon's line, as opposed to the lives running out.
    def invasionReached(w: World): Bool =
        let landed = inv -> inv#alive and inv#pos#y >= Rules.invasionLine();
        Vector.exists(landed, w#invaders)

    /// Runs the benchmark across the standard set of test seeds.
    pub def all(tuning: Tuning): List[Outcome] = allOn(seeds(), tuning)

    /// Runs the benchmark across the given list of test seeds.
    pub def allOn(which: List[Int64], tuning: Tuning): List[Outcome] =
        let runner = one(tuning);
        List.map(runner, which)

    // -- reading the results ----------------------------------------------------------------
    //
    // Pure arithmetic on the outcomes, and the part worth testing: getting a rate wrong is how
    // a measurement lies convincingly.

    /// Mean level, in tenths, so it can be reported without floating point.
    pub def meanLevelTenths(runs: List[Outcome]): Int32 =
        if (List.isEmpty(runs))
            0
        else {
            let totalLevel = List.foldLeft((total, r) -> total + r#level, 0, runs);
            (totalLevel * 10) / List.length(runs)
        }

    /// Returns the lowest level reached across all benchmark runs.
    pub def worstLevel(runs: List[Outcome]): Int32 = {
        let startWorst = Int32.maxValue();
        List.foldLeft((worst, r) -> Int32.min(worst, r#level), startWorst, runs)
    }

    /// Returns the highest level reached across all benchmark runs.
    pub def bestLevel(runs: List[Outcome]): Int32 =
        List.foldLeft((best, r) -> Int32.max(best, r#level), 0, runs)

    /// Returns the total ticks elapsed across all benchmark runs.
    pub def totalTicks(runs: List[Outcome]): Int32 =
        List.foldLeft((total, r) -> total + r#ticks, 0, runs)

    ///
    /// A count per ten thousand ticks of play, in tenths.
    ///
    /// Always compare rates. Two configurations that end their games at different times cannot
    /// be compared on totals, and the difference in when they end is usually the very thing
    /// being measured.
    ///
    /// Per ten thousand rather than per thousand, and in tenths, because of the rarest event
    /// that matters. Deaths run at about four across seventy-eight thousand ticks; per thousand
    /// in tenths that prints as 0.0, which is what a bot dying twenty-four times also printed
    /// before it was fixed. A scale that cannot show the improvement it was built to detect is
    /// no better than no scale.
    ///
    ///
    /// `count` per 10 000 ticks, in tenths.
    ///
    /// Widened to `Int64` for the multiplication, which is not defensive: `count * 100000`
    /// leaves `Int32` above 21 474, and a sixty-seed run of the shipped bot reports 24 871
    /// kills. It printed as `-277.-8` per 10 000 ticks -- visibly broken, which was luck. An
    /// overflow a little smaller would have printed a plausible number instead.
    ///
    pub def rateTenths(count: Int32, ticks: Int32): Int32 =
        if (ticks <= 0) 0
        else {
            let wide = Int32.toInt64(count) * 100000i64 / Int32.toInt64(ticks);
            match Int64.tryToInt32(wide) {
                case Some(rate) => rate
                case None       => Int32.maxValue()
            }
        }

    /// A tenths value as `X.Y`.
    pub def showTenths(tenths: Int32): String =
        "${tenths / 10}.${Int32.remainder(tenths, 10)}"

    /// Returns total player deaths across all benchmark runs.
    pub def deaths(runs: List[Outcome]): Int32 =
        List.foldLeft((total, r) -> total + r#deaths, 0, runs)

    /// Returns total invader kills across all benchmark runs.
    pub def kills(runs: List[Outcome]): Int32 =
        List.foldLeft((total, r) -> total + r#kills, 0, runs)

    /// Returns total row drops across all benchmark runs.
    pub def drops(runs: List[Outcome]): Int32 =
        List.foldLeft((total, r) -> total + r#drops, 0, runs)

    /// Aggregates endgame statistics across all benchmark runs.
    pub def endgame(runs: List[Outcome]): Endgame =
        List.foldLeft((total, r) ->
            { pixels = total#pixels + r#endgame#pixels,
              ticks = total#ticks + r#endgame#ticks,
              kills = total#kills + r#endgame#kills }, emptyEndgame(), runs)

    ///
    /// How far the cannon walked, and how long it took, per invader killed in the endgame.
    ///
    /// The pair is the point. A change that makes the bot walk less is only an improvement if
    /// it does not take longer to kill: down-weighting hard-to-reach targets once cut pixels
    /// per kill from 139 to 130 while raising ticks per kill from 72 to 76, and was rejected
    /// on exactly that reading. Both are rates, so neither can be flattered by a shorter game.
    ///
    /// Nought when nothing was killed, which is the honest answer to a ratio with no
    /// denominator -- an infinity here would sort as the best run ever measured.
    ///
    pub def pixelsPerKill(endgame: Endgame): Float32 =
        if (endgame#kills <= 0) 0.0f32
        else endgame#pixels / Int32.toFloat32(endgame#kills)

    /// The other half of the pair above.
    pub def ticksPerKill(endgame: Endgame): Float32 =
        if (endgame#kills <= 0) 0.0f32
        else Int32.toFloat32(endgame#ticks) / Int32.toFloat32(endgame#kills)

    /// How many games ended with the formation landing rather than the lives running out.
    pub def invasions(runs: List[Outcome]): Int32 =
        List.count(r -> r#invaded, runs)

    /// How many games hit the budget instead of finishing, which invalidates the run.
    pub def unfinished(runs: List[Outcome]): Int32 =
        List.count(r -> r#ticks >= budget(), runs)

    // -- judging one tuning ------------------------------------------------------------------

    ///
    /// A single number for a tuning, so candidates can be ranked.
    ///
    /// Mean level dominates, because clearing formations is what the game is. The worst seed
    /// breaks ties, and it earns its place: more than one tuning has lifted the mean while
    /// dropping a seed two levels, and a demo that collapses one game in six looks broken
    /// rather than fallible. Deaths break the remaining ties -- of two tunings that reach the
    /// same levels, prefer the one that is not being hit.
    ///
    pub def merit(runs: List[Outcome]): Int32 = {
        let ticks = totalTicks(runs);
        meanLevelTenths(runs) * 1000
            + worstLevel(runs) * 100
            - rateTenths(deaths(runs), ticks)
    }

    ///
    /// The merit of a tuning over the standard seeds, which is what the search maximises.
    ///
    /// Always the same seeds, so two tunings are compared on the same games rather than on
    /// their luck. `bin/bench --wide` then plays a set that shares no seed with this one, and
    /// that is what a claim has to survive: a win here alone may only mean the tuning has been
    /// fitted to these ten games.
    ///
    pub def score(tuning: Tuning): Int32 = merit(all(tuning))

    def tryKnob(current: (Tuning, Int32),
                adjust: List[Tuning -> Tuning]): (Tuning, Int32) = {
        let (curT, curS) = current;
        let candidates = List.map(f -> Tuning.sane(f(curT)), adjust);
        List.foldLeft((inner, candidate) -> {
            let (held, heldScore) = inner;
            let trial = score(candidate);
            if (trial > heldScore) (candidate, trial) else (held, heldScore)
        }, (curT, curS), candidates)
    }

    ///
    /// Improves one parameter at a time, keeping any change that scores better.
    ///
    /// Coordinate descent rather than anything cleverer, because the expensive part is playing
    /// the games and the surface is not smooth enough for gradients to mean much. Each
    /// parameter is offered a few multiples of its current value; the best wins and the search
    /// moves on carrying that improvement.
    ///
    /// Bounded and deterministic: the same build searches the same way every time, so a
    /// `--recalc` can be repeated and checked.
    ///
    pub def recalc(rounds: Int32, start: Tuning): (Tuning, Int32) \ IO = {
        def sweep(remaining, best, bestScore) =
            if (remaining <= 0) (best, bestScore)
            else {
                let (improved, improvedScore) = List.foldLeft(tryKnob, (best, bestScore), knobs());
                println("  round ${rounds - remaining + 1}: merit ${improvedScore}"
                      + (if (improvedScore > bestScore) "" else "  (no improvement)"));
                if (improvedScore <= bestScore) (best, bestScore)
                else sweep(remaining - 1, improved, improvedScore)
            };
        sweep(rounds, start, score(start))
    }

    /// Scales a float field up and down, and leaves it alone.
    def spread(): List[Float32] = 0.6f32 :: 0.8f32 :: 1.25f32 :: 1.6f32 :: Nil

    def bumps(): List[Int32] = -2 :: -1 :: 1 :: 2 :: Nil

    def scaled(value: Float32, by: Float32): Float32 = value * by

    ///
    /// The neighbours of a tuning, one parameter at a time.
    ///
    /// Grouped per parameter so the search stays coordinate-wise: each inner list is the set of
    /// alternatives for a single field, and the best of them is adopted before the next field
    /// is considered.
    ///
    def knobs(): List[List[Tuning -> Tuning]] =
        List.map(by -> ((t: Tuning) ->
            let dw = scaled(t#dangerWidth, by);
            { dangerWidth = dw | t }), spread()) ::
        List.map(by -> ((t: Tuning) ->
            let sp = scaled(t#selfPreservation, by);
            { selfPreservation = sp | t }), spread()) ::
        List.map(by -> ((t: Tuning) ->
            let u = scaled(t#urgency, by);
            { urgency = u | t }), spread()) ::
        List.map(by -> ((t: Tuning) ->
            let bc = scaled(t#blockedCost, by);
            { blockedCost = bc | t }), spread()) ::
        List.map(by -> ((t: Tuning) ->
            let sr = scaled(t#shelterRelief, by);
            { shelterRelief = sr | t }), spread()) ::
        List.map(by -> ((t: Tuning) ->
            let c = scaled(t#calm, by);
            { calm = c | t }), spread()) ::
        List.map(by -> ((t: Tuning) ->
            let ff = scaled(t#finishFlank, by);
            { finishFlank = ff | t }), spread()) ::
        List.map(by -> ((t: Tuning) ->
            let sa = scaled(t#startAt, by);
            { startAt = sa | t }), spread()) ::
        List.map(by -> ((t: Tuning) ->
            let ra = scaled(t#reverseAt, by);
            { reverseAt = ra | t }), spread()) ::
        List.map(n -> ((t: Tuning) ->
            { aimJitter = t#aimJitter + n | t }), bumps()) ::
        List.map(n -> ((t: Tuning) ->
            { judgeFor = t#judgeFor + n * 4 | t }), bumps()) ::
        List.map(n -> ((t: Tuning) ->
            { lapseFor = t#lapseFor + n | t }), bumps()) :: Nil

    // -- reporting --------------------------------------------------------------------------

    def pad(text: String, width: Int32): String = {
        let missing = width - String.length(text);
        if (missing <= 0)
            text
        else {
            let addSpace = (acc, _) -> acc + " ";
        let spaces = List.foldLeft(addSpace, "", List.range(0, missing));
            spaces + text
        }
    }

    def row(r: Outcome): String = {
        let status = if (r#invaded) "invaded" else "out of lives";
        let c1 = pad("${r#seed}", 6);
        let c2 = pad("${r#level}", 7);
        let c3 = pad("${r#score}", 8);
        let c4 = pad("${r#lives}", 7);
        let c5 = pad("${r#deaths}", 8);
        let c6 = pad("${r#kills}", 7);
        let c7 = pad("${r#ticks}", 8);
        c1 + c2 + c3 + c4 + c5 + c6 + c7 + "  " + status
    }

    def report(runs: List[Outcome]): Unit \ IO = {
        let ticks = totalTicks(runs);
        let h1 = pad("seed", 6) + pad("level", 7) + pad("score", 8);
        let h2 = pad("lives", 7) + pad("deaths", 8) + pad("kills", 7);
        let h3 = pad("ticks", 8) + "  ended by";
        let header = h1 + h2 + h3;
        println(header);
        List.forEach(r -> println(row(r)), runs);
        println("");
        let meanMsg = "  mean level      ${showTenths(meanLevelTenths(runs))}"
              + "   (worst ${worstLevel(runs)}, best ${bestLevel(runs)})";
        println(meanMsg);
        let dRate = showTenths(rateTenths(deaths(runs), ticks));
        println("  deaths          ${deaths(runs)} = ${dRate} per 10000 ticks");
        let kRate = showTenths(rateTenths(kills(runs), ticks));
        println("  kills           ${kills(runs)} = ${kRate} per 10000 ticks");
        let rRate = showTenths(rateTenths(drops(runs), ticks));
        println("  row drops       ${drops(runs)} = ${rRate} per 10000 ticks");
        let endg = endgame(runs);
        let egMsg = "  <=8 invaders    ${pixelsPerKill(endg)} px/kill, "
            + "${ticksPerKill(endg)} ticks/kill"
              + " (${endg#pixels} px, ${endg#ticks} ticks, ${endg#kills} kills)";
        println(egMsg);
        let endedMsg = "  ended by        ${invasions(runs)} invaded, "
              + "${List.length(runs) - invasions(runs)} out of lives";
        println(endedMsg);

        let cut = unfinished(runs);
        if (cut > 0) {
            let warnMsg = "  WARNING         ${cut} game(s) hit the budget and were cut short; "
                  + "raise budget() before trusting these numbers";
            println(warnMsg)
        } else
            ()
    }

    // -- the command line --------------------------------------------------------------------

    ///
    /// What the user asked for.
    ///
    pub enum Flag with Eq, ToString {
        case Help
        case Recalc(Int32)
        case Config(String)
        case Defaults
        case Wide
    }

    def defaultRounds(): Int32 = 3

    ///
    /// The options, in the shape `Util.GetOpt` wants.
    ///
    /// `--recalc` takes its round count optionally, so `--recalc` and `--recalc 5` both work
    /// and neither swallows a following flag.
    ///
    def switches(): List[OptionDescr[Flag]] = {
        let helpOpt = { optionIds = 'h' :: Nil,
                        optionNames = "help" :: Nil,
                        argDescriptor = ArgDescr.NoArg(Flag.Help),
                        explanation = "print this message" };
        let parseRounds = givenOpt -> {
            let n = givenOpt
                |> Option.flatMap(Int32.fromString)
                |> Option.getWithDefault(defaultRounds());
            Some(Flag.Recalc(n))
        };
        let recalcOpt = { optionIds = 'r' :: Nil,
                          optionNames = "recalc" :: Nil,
                          argDescriptor = ArgDescr.OptArg(parseRounds, "ROUNDS"),
                          explanation = "search for a better tuning "
                              + "(default ${defaultRounds()} rounds) and save it if it wins" };
        let configOpt = { optionIds = 'c' :: Nil,
                          optionNames = "config" :: Nil,
                          argDescriptor =
                              ArgDescr.ReqArg(given -> Some(Flag.Config(given)), "PATH"),
                          explanation = "use PATH instead of the file beside the high scores" };
        let defaultsOpt = { optionIds = 'd' :: Nil,
                            optionNames = "defaults" :: Nil,
                            argDescriptor = ArgDescr.NoArg(Flag.Defaults),
                            explanation = "ignore any config and use the tuning compiled in" };
        let wideOpt = { optionIds = 'w' :: Nil,
                        optionNames = "wide" :: Nil,
                        argDescriptor = ArgDescr.NoArg(Flag.Wide),
                        explanation = "play ${List.length(wideSeeds())} seeds "
                            + "instead of ${List.length(seeds())}; "
                            + "slower, and the only sample that can settle a close call" };
        helpOpt :: recalcOpt :: configOpt :: defaultsOpt :: wideOpt :: Nil
    }

    def usage(): String =
        usageInfo("usage: bin/bench [options]", switches())

    /// The rounds asked for, if `--recalc` was given at all.
    def roundsIn(flags: List[Flag]): Option[Int32] =
        List.findMap(flag -> match flag {
            case Flag.Recalc(n) => Some(n)
            case _ => None
        }, flags)

    def configIn(flags: List[Flag]): Option[String] =
        List.findMap(flag -> match flag {
            case Flag.Config(path) => Some(path)
            case _ => None
        }, flags)

    /// The directory a path lives in, for creating it before a write.
    def parentOf(file: String): String \ Sys.Env = {
        let separator = Sys.Env.getFileSeparator();
        match List.reverse(String.splitOn(substr = separator, file)) {
            case _ :: rest => String.intercalate(separator, List.reverse(rest))
            case Nil => "."
        }
    }

    def runSearch(configFile: Option[String], stored: Tuning, rounds: Int32)
        : Unit \ { Fs.FileWrite, Sys.Env, IO } = {
        let before = score(stored);
        let seedsCount = List.length(seeds());
        println("Searching from merit ${before} over at most ${rounds} round(s).");
        println("Each round plays ${seedsCount} games per candidate; this takes a while.");
        let (found, foundScore) = recalc(rounds, stored);
        println("");
        report(all(found));
        println("");
        if (foundScore <= before)
            println("No improvement found; the config is unchanged.")
        else
            writeTuning(configFile, found)
    }

    def runBenchOptions(flags: List[Flag], configFile: Option[String])
        : Unit \ { Fs.FileRead, Fs.FileWrite, Sys.Env, IO } = {
        let stored = startingTuning(flags, configFile);
        println(provenance(flags, configFile));
        match roundsIn(flags) {
            case None =>
                let playing = if (List.memberOf(Flag.Wide, flags)) wideSeeds() else seeds();
                println("Bot benchmark -- ${List.length(playing)} seeds, budget ${budget()} ticks");
                println("");
                report(allOn(playing, stored))
            case Some(rounds) =>
                runSearch(configFile, stored, rounds)
        }
    }

    ///
    /// Measures the demo player, and optionally searches for better numbers.
    ///
    pub def main(): Unit \ { Fs.FileRead, Fs.FileWrite, Sys.Env, IO } = {
        let parsed = getOpt1(ArgOrder.Permute, switches(), Sys.Env.getArgs());
        let hasErrors = not List.isEmpty(parsed#errors) or not List.isEmpty(parsed#unknowns);
        if (hasErrors) {
            List.forEach(e -> println("bench: ${e}"), List.append(parsed#errors, parsed#unknowns));
            println(usage())
        } else if (List.memberOf(Flag.Help, parsed#options))
            println(usage())
        else {
            let flags = parsed#options;
            let configFile = match configIn(flags) {
                case Some(given) => Some(given)
                case None => Tuning.path()
            };
            runBenchOptions(flags, configFile)
        }
    }

    ///
    /// Where the numbers being measured came from.
    ///
    /// Said out loud on every run, because the alternative was silence. `bin/bench` picks up
    /// `~/.config/flix-invaders/tuning.json` if it exists, so a config left behind by an
    /// earlier `--recalc` quietly becomes the thing every later run measures -- and a
    /// comparison against a `--defaults` run then differs in every field rather than the one
    /// under test. That happened, and the numbers it produced ranked a change backwards.
    ///
    def provenance(flags: List[Flag], configFile: Option[String]): String =
        if (List.memberOf(Flag.Defaults, flags)) "Tuning: the compiled-in defaults (--defaults)."
        else match configFile {
            case None => "Tuning: the compiled-in defaults; no config file was found."
            case Some(file) => "Tuning: ${file} if it exists, otherwise the compiled-in defaults."
        }

    ///
    /// The tuning to start from: the config, unless `--defaults` says otherwise.
    ///
    /// A config that cannot be read is reported and then ignored. Refusing to run because a
    /// tuning file is malformed would be a strange way to treat a tool whose whole job is to
    /// tell you whether a set of numbers is any good.
    ///
    def startingTuning(flags: List[Flag], configFile: Option[String])
        : Tuning \ { Fs.FileRead, IO } =
        if (List.memberOf(Flag.Defaults, flags))
            Demo.defaults()
        else
            match configFile {
                case None => Demo.defaults()
                case Some(file) => match Tuning.load(file) {
                    case Ok(t) => t
                    case Err(why) =>
                        println("could not read ${file}: ${why}; using the compiled-in defaults");
                        Demo.defaults()
                }
            }

    def writeTuning(configFile: Option[String], t: Tuning)
        : Unit \ { Fs.FileWrite, Sys.Env, IO } =
        match configFile {
            case None =>
                println("nowhere to write a config; the tuning above was not saved")
            case Some(file) => match Tuning.save(file, parentOf(file), t) {
                case Ok(_) => println("Wrote ${file}.")
                case Err(why) => println("could not write ${file}: ${why}")
            }
        }

}
