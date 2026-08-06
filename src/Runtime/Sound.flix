///
/// Something the game wants heard.
///
/// Sound is *data*, not an effect in the model. `Game.step` stays a pure
/// `(World, Snapshot) -> World` and simply records what happened this tick; the runtime
/// reads the list afterwards and makes noise. That keeps replay exact, lets the tests assert
/// on sound without an audio device, and means a machine with no sound card runs the same
/// simulation as one with speakers.
///
/// `MarchStep` carries which of the four notes of the bassline is due. Its tempo is not a
/// timer -- it is driven by how far the formation has actually moved, so it speeds up
/// exactly in step with the invaders.
///
pub enum SoundCmd with Eq, Order, ToString {
    case Shoot
    case InvaderDies
    case PlayerDies
    case MysteryAppears
    case MysteryDies
    case ShieldBlock
    case MarchStep(Int32)
}

mod SoundCmd {

    ///
    /// How many notes the marching bassline cycles through.
    ///
    pub def marchNotes(): Int32 = 4

    ///
    /// Every sound the game can make, which is what the runtime pre-builds voices for.
    ///
    pub def all(): List[SoundCmd] =
        SoundCmd.Shoot ::
        SoundCmd.InvaderDies ::
        SoundCmd.PlayerDies ::
        SoundCmd.MysteryAppears ::
        SoundCmd.MysteryDies ::
        SoundCmd.ShieldBlock ::
        List.map(n -> SoundCmd.MarchStep(n), List.range(0, marchNotes()))

}
