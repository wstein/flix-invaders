mod TestScreenGraph {

    use Assert.assertTrueWithMsg

    ///
    /// Liveness of the cabinet, as a fixpoint.
    ///
    /// The screens form a small graph, and the properties that matter about it are reachability
    /// properties: every screen can be got to, and no screen traps the player. Both are
    /// transitive closure, which is what Datalog is for -- three rules instead of a hand-rolled
    /// search, and they say what they mean.
    ///
    /// The point of care is where the edges come from. They are **discovered by running the
    /// real `Session.step`** over each screen and a spread of inputs, not typed out. A test
    /// that listed the transitions by hand would assert the author's belief about the state
    /// machine rather than the state machine, and would keep passing after somebody deleted
    /// the way out of `Table`.
    ///

    def seed(): Int64 = 2026i64

    /// Enter, space, 1, 2, a letter, backspace, and nothing at all.
    def inputs(): List[Snapshot] =
        Input.empty() ::
        Input.holding(Key.Enter :: Nil) ::
        Input.holding(Key.Space :: Nil) ::
        Input.holding(Key.Other(49) :: Nil) ::     // '1'
        Input.holding(Key.Other(50) :: Nil) ::     // '2'
        Input.holding(Key.Other(65) :: Nil) ::     // 'A'
        Input.holding(Key.Backspace :: Nil) ::
        Input.holding(Key.Left :: Key.Space :: Nil) :: Nil

    ///
    /// Every world finished, on a score worth recording.
    ///
    /// The score matters: `finish` routes to `Entering` only for a player who earned a place,
    /// and a zero never qualifies. A game-over fixture scoring nothing therefore exercises
    /// only the road to `Table` -- which is how the first draft of this test managed to report
    /// `Entering` as unreachable.
    ///
    def gameOver(s: Session): Session =
        { worlds = Vector.map(w -> { phase = Phase.Lost, score = 9999 | w }, s#worlds) | s }

    ///
    /// A session sitting on each screen, in a state where that screen has something to do.
    ///
    /// These are start states, not transitions: what each one *does* is left to `Session.step`
    /// to decide.
    ///
    def fixtures(): List[(Screen, Session)] = {
        let base = Session.withScores(seed(), { name = "OLD", score = 10, level = 1 } :: Nil);
        let playing = gameOver({ screen = Screen.Playing, players = 1 | base });
        // A score worth entering initials for, so `Entering` has a name to collect.
        let entering =
            { screen = Screen.Entering,
              pending = { name = "", score = 9999, level = 4 } :: Nil,
              typing = "AB" | base };
        (Screen.Attract, base) ::
        (Screen.Playing, playing) ::
        (Screen.Entering, entering) ::
        (Screen.Table, { screen = Screen.Table | base }) :: Nil
    }

    ///
    /// Every transition the cabinet actually makes, as `(from, to)` pairs.
    ///
    /// The demo runs inside `Session.step`, so this needs a `Sound` handler -- `runWithNoOp`,
    /// because what the attract screen would have played is not the subject here.
    ///
    def discoveredEdges(): List[(Screen, Screen)] =
        Sound.runWithNoOp(() ->
            fixtures() |> List.flatMap(match (source, s) ->
                inputs() |> List.map(input -> (source, Session.step(s, input)#screen))))

    /// Which screens are reachable from which, by one or more transitions.
    def reachable(edges: List[(Screen, Screen)]): Vector[(Screen, Screen)] = {
        let facts = List.foldLeft((acc, edge) -> {
            let (source, target) = edge;
            let fact = #{ Edge(source, target). };
            acc <+> fact
        }, #{}, edges);
        let rules = #{
            Path(x, y) :- Edge(x, y).
            Path(x, z) :- Path(x, y), Edge(y, z).
        };
        query facts, rules select (x, y) from Path(x, y)
    }

    def screens(): List[Screen] =
        Screen.Attract :: Screen.Playing :: Screen.Entering :: Screen.Table :: Nil

    def leadsTo(paths: Vector[(Screen, Screen)], source: Screen, target: Screen): Bool =
        Vector.exists(match (x, y) -> x == source and y == target, paths)

    // -- the properties -------------------------------------------------------------------

    @Test
    def testEveryScreenIsReachableFromTheTitle(): Unit \ Assert = {
        let paths = reachable(discoveredEdges());
        let stranded = screens()
            |> List.filter(target -> target != Screen.Attract)
            |> List.filter(target -> not leadsTo(paths, Screen.Attract, target));
        assertTrueWithMsg(List.isEmpty(stranded),
            "no sequence of keys reaches ${stranded} from the title screen")
    }

    @Test
    def testNoScreenTrapsThePlayer(): Unit \ Assert = {
        // The property a coin-op cabinet actually needs: whatever it is showing, it finds its
        // way back to attracting. A screen with no path home is a machine nobody can start.
        let paths = reachable(discoveredEdges());
        let traps = screens()
            |> List.filter(source -> not leadsTo(paths, source, Screen.Attract));
        assertTrueWithMsg(List.isEmpty(traps),
            "${traps} never returns to the attract screen")
    }

    @Test
    def testTheGraphIsConnectedInBothDirections(): Unit \ Assert = {
        // Reachability alone would be satisfied by a one-way street. Every screen should be
        // reachable from every other, which for this cabinet is a genuine cycle.
        let paths = reachable(discoveredEdges());
        let missing = screens() |> List.flatMap(source ->
            screens() |> List.filterMap(target ->
                if (leadsTo(paths, source, target)) None else Some((source, target))));
        assertTrueWithMsg(List.isEmpty(missing),
            "these screen pairs are not connected: ${missing}")
    }

    @Test
    def testTheDiscoveredGraphIsNotEmpty(): Unit \ Assert = {
        // The guard on the guard. If the fixtures stopped producing transitions -- a renamed
        // key, a changed start condition -- the reachability assertions above would pass
        // vacuously on an empty graph and prove nothing.
        let moves = discoveredEdges() |> List.filter(match (source, target) -> source != target);
        assertTrueWithMsg(List.length(moves) >= 3,
            "only ${List.length(moves)} real transitions were discovered; the fixtures have gone stale")
    }

}
