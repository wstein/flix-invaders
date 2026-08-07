///
/// What the cabinet is currently showing.
///
/// Deliberately separate from `Phase`, which describes a single *game* and lives inside
/// `World`. A screen outlives a game -- the attract loop keeps running while games start and
/// end underneath it -- so conflating the two would put cabinet state inside the rules.
///
pub enum Screen with Eq, ToString {
    case Attract
    case Playing
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
    demo = World,
    demoRng = Rng,
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

    pub def initial(seed: Int64): Session =
        { screen = Screen.Attract,
          players = 1,
          current = 0,
          worlds = Vector#{Game.initial(seed)},
          demo = Game.initial(demoSeed(seed)),
          demoRng = Rng.fromSeed(demoSeed(seed)),
          seed = seed }

    /// The world whose turn it is.
    pub def active(s: Session): World =
        Vector.get(Int32.min(s#current, Vector.length(s#worlds) - 1), s#worlds)

    /// The world the player is looking at -- the demo on the attract screen.
    pub def onScreen(s: Session): World = match s#screen {
        case Screen.Attract => s#demo
        case Screen.Playing => active(s)
    }

    /// Starts a fresh game for `players` players.
    def begin(players: Int32, s: Session): Session =
        { screen = Screen.Playing,
          players = players,
          current = 0,
          worlds = Vector.range(0, players) |> Vector.map(i -> Game.initial(s#seed + Int32.toInt64(i))) | s }

    ///
    /// Advances the attract screen.
    ///
    /// The demo runs under `runWithNoOp`, so the cabinet is silent until somebody actually
    /// plays. When the bot loses, a fresh demo starts from a different seed, so the loop
    /// never shows the same game twice.
    ///
    def attract(input: Snapshot, s: Session): Session = {
        let (botInput, nextRng) = Demo.imperfect(s#demo, s#demoRng);
        let advanced = Sound.runWithNoOp(() -> Game.step(s#demo, botInput));
        let restarted =
            if (advanced#phase == Phase.Lost) Game.initial(demoSeed(s#seed) + Int32.toInt64(advanced#score) + 1i64)
            else advanced;
        let waiting = { demo = restarted, demoRng = nextRng | s };
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
    def playing(input: Snapshot, s: Session): Session \ Sound = {
        let current = active(s);
        if (current#phase == Phase.Lost and Set.memberOf(Key.Enter, input#pressed))
            { screen = Screen.Attract | s }
        else {
            let stepped = Game.step(current, input);
            { worlds = Vector.update(s#current, stepped, s#worlds) | s }
        }
    }

    ///
    /// One tick of the cabinet.
    ///
    pub def step(s: Session, input: Snapshot): Session \ Sound = match s#screen {
        case Screen.Attract => attract(input, s)
        case Screen.Playing => playing(input, s)
    }

}
