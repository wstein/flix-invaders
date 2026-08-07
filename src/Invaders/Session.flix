///
/// What the cabinet is currently showing.
///
/// Deliberately separate from `Phase`, which describes a single *game* and lives inside
/// `World`. A screen outlives a game -- the attract loop keeps running while games start and
/// end underneath it -- so conflating the two would put cabinet state inside the rules.
///
pub enum Screen with Eq, Order, ToString {
    case Attract
    case Playing
    case Entering
    case Table
}

///
/// Everything the cabinet knows: which screen, whose turn, and a game running behind the
/// title for anybody who walks past.
///
pub type alias Session = {
    screen = Screen,
    players = Int32,
    current = Int32,
    worlds = Vector[World],
    scores = List[Entry],
    pending = List[Entry],
    typing = String,
    demo = World,
    demoHand = Hand,
    tuning = Tuning,
    nerds = Bool,
    seed = Int64
}

///
/// The layer above the game.
///
/// `Game.step` never learns that any of this exists. This module drives it -- once per real
/// player, or once for the attract-mode bot -- and owns everything a single game does not:
/// screens, player count, whose turn it is.
///
mod Session {

    /// The seed the attract game runs from, offset so it never mirrors a real game.
    def demoSeed(seed: Int64): Int64 = seed + 977i64

    pub def initial(seed: Int64): Session = withScores(seed, Scores.empty())

    ///
    /// A cabinet that already knows some high scores -- what `main` builds after reading them
    /// from disk.
    ///
    pub def withScores(seed: Int64, scores: List[Entry]): Session =
        withTuning(seed, scores, Demo.defaults())

    ///
    /// The same, with the demo player's numbers supplied.
    ///
    /// The cabinet carries them rather than `Demo` owning them as constants, so a tuning read
    /// from a file reaches the attract screen without anything below here knowing where it
    /// came from.
    ///
    pub def withTuning(seed: Int64, scores: List[Entry], tuning: Tuning): Session =
        { screen = Screen.Attract,
          players = 1,
          current = 0,
          worlds = Vector#{Game.initial(seed)},
          scores = scores,
          pending = Nil,
          typing = "",
          demo = Game.initial(demoSeed(seed)),
          demoHand = Demo.fresh(demoSeed(seed)),
          tuning = tuning,
          nerds = false,
          seed = seed }

    /// Whether this player still has a game to play.
    pub def stillIn(w: World): Bool = w#phase != Phase.Lost

    /// True once every player has finished.
    pub def allDone(s: Session): Bool = not Vector.exists(stillIn, s#worlds)

    ///
    /// The next player still in the game, starting after `current` and wrapping.
    ///
    /// Returns `None` when nobody is left, which is what ends the session.
    ///
    pub def nextPlayer(current: Int32, s: Session): Option[Int32] = {
        let count = Vector.length(s#worlds);
        def look(offset) =
            if (offset > count) None
            else {
                let i = Int32.remainder(current + offset, count);
                if (stillIn(Vector.get(i, s#worlds))) Some(i) else look(offset + 1)
            };
        look(1)
    }

    /// What the HUD needs to know about the other player.
    pub def cabinet(s: Session): Cabinet = {
        let other =
            if (s#players < 2) 0
            else Vector.get(Int32.remainder(s#current + 1, Vector.length(s#worlds)), s#worlds)#score;
        { player = s#current + 1, players = s#players, otherScore = other }
    }

    /// The world whose turn it is.
    pub def active(s: Session): World =
        Vector.get(Int32.min(s#current, Vector.length(s#worlds) - 1), s#worlds)

    /// The world the player is looking at -- the demo on the attract screen.
    pub def onScreen(s: Session): World = match s#screen {
        case Screen.Playing => active(s)
        case _ => s#demo
    }

    /// Starts a fresh game for `players` players.
    def begin(players: Int32, s: Session): Session = {
        let best = Scores.best(s#scores);
        { screen = Screen.Playing,
          players = players,
          current = 0,
          pending = Nil,
          typing = "",
          worlds = Vector.range(0, players)
              |> Vector.map(i -> { hiScore = best | Game.initial(s#seed + Int32.toInt64(i)) }) | s }
    }

    ///
    /// Advances the attract screen.
    ///
    /// The demo runs under `runWithNoOp`, so the cabinet is silent until somebody actually
    /// plays. When the bot loses, a fresh demo starts from a different seed, so the loop
    /// never shows the same game twice.
    ///
    def attract(input: Snapshot, s: Session): Session = {
        let (botInput, nextHand) = Demo.imperfect(s#tuning, s#demo, s#demoHand);
        let advanced = Sound.runWithNoOp(() -> Game.step(s#demo, botInput));
        let restarted =
            if (advanced#phase == Phase.Lost) Game.initial(demoSeed(s#seed) + Int32.toInt64(advanced#score) + 1i64)
            else advanced;
        let waiting = { demo = restarted, demoHand = nextHand | s };
        match startRequest(input) {
            case Some(players) => begin(players, waiting)
            case None => waiting
        }
    }

    ///
    /// How many players the keypress asks for, if it asks for a game at all.
    ///
    pub def startRequest(input: Snapshot): Option[Int32] =
        if (Set.exists(k -> Key.digit(k) == Some(1), input#pressed)) Some(1)
        else if (Set.exists(k -> Key.digit(k) == Some(2), input#pressed)) Some(2)
        else if (Set.memberOf(Key.Enter, input#pressed) or Set.memberOf(Key.Space, input#pressed)) Some(1)
        else None

    ///
    /// Advances the game the player is actually playing.
    ///
    /// The Enter check happens *before* stepping, deliberately. `Game.step` handles Enter on
    /// a lost world by restarting the game itself; if the session stepped first it would
    /// never see a lost world, because the game would already have replaced it. Leaving the
    /// cabinet in charge of what happens after a game keeps the decision in one place.
    ///
    ///
    /// What happens once every player has finished: collect anyone who earned a place, and
    /// either ask for their initials or go straight to the table.
    ///
    def finish(s: Session): Session = {
        let earned = Vector.toList(s#worlds)
            |> List.filter(w -> Scores.qualifies(w#score, s#scores))
            |> List.map(w -> { name = "", score = w#score, level = w#level });
        if (List.isEmpty(earned)) { screen = Screen.Table, pending = Nil | s }
        else { screen = Screen.Entering, pending = earned, typing = "" | s }
    }

    def playing(input: Snapshot, s: Session): Session \ Sound = {
        if (allDone(s)) finish(s)
        else {
            let stepped = Game.step(active(s), input);
            let worlds = Vector.update(s#current, stepped, s#worlds);
            let advanced = { worlds = worlds | s };

            // A turn is a whole game: player one plays down to their last life before player
            // two starts. Losing a cannon costs a life and nothing else.
            //
            // The arcade original hands over on every destroyed cannon, and that was built
            // first. It is a different game rather than a better or worse one -- alternating
            // keeps both players watching and neither able to hold a run together, and this
            // way round trades the second for the first.
            if (stepped#phase != Phase.Lost) advanced
            else match nextPlayer(s#current, advanced) {
                case Some(next) => { current = next | advanced }
                case None => advanced   // nobody left; the game-over screen holds
            }
        }
    }

    ///
    /// Typing a name for the next score that earned a place.
    ///
    /// Letters append, backspace removes, Enter commits. Enter is ignored on an empty name,
    /// so the table never gains a blank row.
    ///
    def entering(input: Snapshot, s: Session): Session = {
        let typed = Set.foldLeft((acc, k) -> match Key.letter(k) {
            case Some(c) if String.length(acc) < Scores.nameLength() => acc + "${c}"
            case _ => acc
        }, s#typing, input#pressed);
        let afterDelete =
            if (Set.memberOf(Key.Backspace, input#pressed) and String.length(typed) > 0)
                String.dropRight(1, typed)
            else typed;
        if (not (Set.memberOf(Key.Enter, input#pressed) and String.length(afterDelete) > 0))
            { typing = afterDelete | s }
        else match s#pending {
            case Nil => { screen = Screen.Table, typing = "" | s }
            case entry :: rest => {
                let recorded = Scores.insert({ name = afterDelete | entry }, s#scores);
                if (List.isEmpty(rest)) { screen = Screen.Table, scores = recorded, pending = Nil, typing = "" | s }
                else { scores = recorded, pending = rest, typing = "" | s }
            }
        }
    }

    /// The table waits for a key, then goes back to attracting.
    def table(input: Snapshot, s: Session): Session =
        if (Set.memberOf(Key.Enter, input#pressed) or Set.memberOf(Key.Space, input#pressed))
            { screen = Screen.Attract | s }
        else s

    ///
    /// One tick of the cabinet.
    ///
    ///
    /// Whether the telemetry overlay is up.
    ///
    /// F3, following the convention every game that has one of these uses. It is cabinet state
    /// rather than game state: it survives a game ending, and turning it on must not change
    /// what the game does -- `TestSession` holds it to that.
    ///
    pub def togglesNerds(input: Snapshot): Bool = Set.memberOf(Key.F3, input#pressed)

    pub def step(s: Session, input: Snapshot): Session \ Sound = {
        let shown = if (togglesNerds(input)) not s#nerds else s#nerds;
        { nerds = shown | advance(s, input) }
    }

    def advance(s: Session, input: Snapshot): Session \ Sound = match s#screen {
        case Screen.Attract => attract(input, s)
        case Screen.Playing => playing(input, s)
        case Screen.Entering => entering(input, s)
        case Screen.Table => table(input, s)
    }

}
