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
    case Other(Int32)
}

mod Key {

    // Processing reports java.awt.event.KeyEvent.VK_* values in PApplet.keyCode.
    def vkEnter(): Int32 = 10
    def vkEscape(): Int32 = 27
    def vkSpace(): Int32 = 32
    def vkLeft(): Int32 = 37
    def vkUp(): Int32 = 38
    def vkRight(): Int32 = 39
    def vkDown(): Int32 = 40

    ///
    /// Translates a Processing key code.
    ///
    pub def fromCode(code: Int32): Key =
        if (code == vkLeft()) Key.Left
        else if (code == vkRight()) Key.Right
        else if (code == vkUp()) Key.Up
        else if (code == vkDown()) Key.Down
        else if (code == vkSpace()) Key.Space
        else if (code == vkEnter()) Key.Enter
        else if (code == vkEscape()) Key.Escape
        else Key.Other(code)

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
    pub def empty(): Snapshot =
        { held = Set.empty(), pressed = Set.empty(), released = Set.empty(), mouseX = 0, mouseY = 0 }

    ///
    /// Builds a snapshot by comparing the keys held now against the keys held last step.
    ///
    pub def diff(previous: Set[Key], current: Set[Key], mouseX: Int32, mouseY: Int32): Snapshot =
        { held = current,
          pressed = Set.difference(current, previous),
          released = Set.difference(previous, current),
          mouseX = mouseX,
          mouseY = mouseY }

    ///
    /// A snapshot with `keys` held, and all of them treated as newly pressed.
    ///
    /// Convenience for tests and scripted replays.
    ///
    pub def holding(keys: List[Key]): Snapshot =
        diff(Set.empty(), List.toSet(keys), 0, 0)

    ///
    /// Runs `f`, answering every `Input.poll` with the same snapshot.
    ///
    pub def runWith(s: Snapshot, f: Unit -> a \ ef): a \ ef - Input =
        run {
            f()
        } with handler Input {
            def poll(k) = k(s)
        }

}
