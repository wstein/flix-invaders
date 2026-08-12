///
/// A key, named rather than numbered.
///
/// The runtime translates Processing's `keyCode` into these, so no game code ever mentions
/// a key code.
///
pub enum Key with Eq, Order, ToString {
    case Left
    case Right
    case Up
    case Down
    case Space
    case Enter
    case Escape
    case Backspace
    case F3
    case Other(Int32)
}

mod Key {

    ///
    /// The digit a key stands for, if it is one of the number keys.
    ///
    /// Processing reports `keyCode`, and for the number row those values are ASCII digits,
    /// so this is a subtraction rather than a table.
    ///
    ///
    /// The letter a key stands for, if it is one of A-Z.
    ///
    /// Processing reports `keyCode`, and for letters those values are ASCII uppercase, so
    /// this is a conversion rather than a table. It is also why initials are uppercase only:
    /// `keyCode` carries no shift state.
    ///
    def alphabet(): String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    ///
    /// Converts a key press to an uppercase ASCII letter char ('A'-'Z'), if applicable.
    ///
    pub def letter(k: Key): Option[Char] = match k {
        case Key.Other(code) if code >= 65 and code <= 90 =>
            Some(String.charAt(code - 65, alphabet()))
        case _ => None
    }

    ///
    /// A character that may appear in a name: A-Z or 0-9.
    ///
    /// Two separate lookups rather than one range, because `keyCode` puts the digits well
    /// below the letters and nothing sensible lies between them. `Scores.clean` accepts the
    /// same set on the way in from a file, so what can be typed and what can be stored agree.
    ///
    pub def nameCharacter(k: Key): Option[Char] = match letter(k) {
        case Some(c) => Some(c)
        case None => Option.map(n -> String.charAt(n, digits()), digit(k))
    }

    def digits(): String = "0123456789"

    ///
    /// Converts a key press to a numeric digit (0-9), if applicable.
    ///
    pub def digit(k: Key): Option[Int32] = match k {
        case Key.Other(code) if code >= 48 and code <= 57 => Some(code - 48)
        case _ => None
    }

    ///
    /// Translates a Processing key code.
    ///
    pub def fromCode(code: Int32): Key = match code {
        case 8   => Key.Backspace
        case 10  => Key.Enter
        case 27  => Key.Escape
        case 32  => Key.Space
        case 37  => Key.Left
        case 38  => Key.Up
        case 39  => Key.Right
        case 40  => Key.Down
        case 114 => Key.F3
        case _   => Key.Other(code)
    }

}

///
/// Everything a single simulation step is allowed to know about the input devices.
///
/// `held` is the set of keys down for the whole of this step. `pressed` and `released` are
/// the edges since the previous step, so a step can distinguish "the key is down" from "the
/// key just went down" without keeping its own history.
///
pub type alias Snapshot = {
    held = Set[Key],
    pressed = Set[Key],
    released = Set[Key],
    mouseX = Int32,
    mouseY = Int32
}

///
/// Reading the input devices, as an effect.
///
/// `Input.poll` returns the *same* value every time it is called within one simulation
/// step: the runtime captures it once, at the top of the frame, and freezes it. That is
/// what makes a run reproducible from a recorded list of snapshots.
///
pub eff Input {
    def poll(): Snapshot
}

mod Input {

    ///
    /// A snapshot with nothing held and the mouse at the origin.
    ///
    pub def empty(): Snapshot = {
        held = Set.empty(),
        pressed = Set.empty(),
        released = Set.empty(),
        mouseX = 0,
        mouseY = 0
    }

    ///
    /// Builds a snapshot by comparing the keys held now against the keys held last step.
    ///
    /// The two key sets are named -- transposing them inverts every edge, turning presses
    /// into releases -- and so are the two mouse coordinates.
    pub def diff(previous: {previous = Set[Key]}, current: {current = Set[Key]},
                 mouseX: {mouseX = Int32}, mouseY: {mouseY = Int32}): Snapshot = {
        let before = previous#previous;
        let now = current#current;
        let newlyPressed = Set.difference(now, before);
        let newlyReleased = Set.difference(before, now);
        let mx = mouseX#mouseX;
        let my = mouseY#mouseY;
        { held = now,
          pressed = newlyPressed,
          released = newlyReleased,
          mouseX = mx,
          mouseY = my }
    }

    ///
    /// A snapshot with `keys` held, and all of them treated as newly pressed.
    ///
    /// Convenience for tests and scripted replays.
    ///
    pub def holding(keys: List[Key]): Snapshot = {
        let prev = Set.empty();
        let curr = List.toSet(keys);
        diff(previous = prev, current = curr, mouseX = 0, mouseY = 0)
    }

    // -- handing one frame's keyboard to several logical ticks ------------------------------

    ///
    /// How many logical ticks are due, given what has accumulated and what may be spent.
    ///
    pub def ticksDue(accumulated: Int64, perTick: Int64, budget: Int32): Int32 =
        if (perTick <= 0i64 or accumulated < perTick) 0
        else {
            let due = accumulated / perTick;
            if (due > Int32.toInt64(budget)) budget
            else Option.getWithDefault(0, Int64.tryToInt32(due))
        }

    ///
    /// The same snapshot with its edges removed: still held, but pressed and released nothing.
    ///
    pub def steady(s: Snapshot): Snapshot =
        { pressed = Set.empty(), released = Set.empty() | s }

    ///
    /// One frame's reading of the keyboard, spread over the `n` ticks it has to drive.
    ///
    /// A frame does not map to a tick. The display runs at whatever rate the machine manages
    /// and the simulation runs at a fixed one, so a frame may owe several ticks or none.
    ///
    /// Only the first tick gets the edges. A press is a *transition*, and handing the same
    /// `pressed` set to three catch-up ticks fires it three times -- which for anything
    /// edge-triggered means the action happens once per stalled frame instead of once per
    /// press, and for anything that toggles means it can end up back where it started.
    /// The rest of the ticks keep the keys held, because holding is a state and does last.
    ///
    pub def acrossTicks(n: Int32, s: Snapshot): List[Snapshot] =
        if (n <= 0) Nil
        else s :: List.repeat(n - 1, steady(s))

    ///
    /// Interprets `Input` by answering every `poll` with the same snapshot.
    ///
    /// Like `Canvas`, this deliberately has no `@DefaultHandler`: a default of "no keys
    /// held" would let a test that forgot to supply input pass while asserting on a world
    /// nobody played.
    ///
    pub def handleWith(s: Snapshot, f: a -> b \ ef): a -> b \ ef - Input = input ->
        run {
            f(input)
        } with handler Input {
            def poll(k) =
                k(s)
        }

    ///
    /// Runs `f`, answering every `Input.poll` with the same snapshot.
    ///
    pub def runWith(s: Snapshot, f: Unit -> a \ ef): a \ ef - Input =
        handleWith(s, f)()

}
