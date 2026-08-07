///
/// Something the game wants heard.
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
    case ExtraLife
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
        SoundCmd.ExtraLife ::
        List.map(n -> SoundCmd.MarchStep(n), List.range(0, marchNotes()))

}

///
/// Making a noise, as an effect.
///
/// The rules say *what* should be heard and never learn *how*. The runtime interprets this
/// onto a pool of clips, the tests interpret it into a list, and a machine with no sound
/// card interprets it into nothing -- all three running the identical simulation.
///
pub eff Sound {
    def play(cmd: SoundCmd): Unit
}

mod Sound {

    ///
    /// Interprets `Sound` by recording what was played instead of playing it.
    ///
    /// Pure: the accumulator lives in a region that is fully discharged here, so this needs
    /// no `IO` and touches no device. This is what the sound tests use.
    ///
    pub def handleWithCollector(f: a -> b \ ef): a -> (b, List[SoundCmd]) \ ef - Sound = input ->
        region rc {
            let acc: Ref[List[SoundCmd], rc] = Ref.fresh(rc, Nil);
            let result = run {
                f(input)
            } with handler Sound {
                def play(cmd, k) = { Ref.put(cmd :: Ref.get(acc), acc); k() }
            };
            (result, List.reverse(Ref.get(acc)))
        }

    ///
    /// Runs `f`, returning its result together with everything it played.
    ///
    pub def runWithCollector(f: Unit -> a \ ef): (a, List[SoundCmd]) \ ef - Sound =
        handleWithCollector(f)()

    ///
    /// Runs `f` and returns only what it played.
    ///
    pub def played(f: Unit -> a \ ef): List[SoundCmd] \ ef - Sound =
        snd(runWithCollector(f))

    ///
    /// Lifts a step that makes no sound into one that is allowed to.
    ///
    /// The teaching sketches have nothing to play, but the runtime asks for a step that may.
    /// `checked_ecast` widens the effect without changing behaviour -- the escape hatch the
    /// Flix style guide sanctions for exactly this ("if necessary, effect casts are OK").
    ///
    pub def silent(f: (a, b) -> c): (a, b) -> c \ Sound = (x, y) -> checked_ecast(f(x, y))

    ///
    /// Interprets `Sound` by discarding it.
    ///
    /// Deliberately not a `@DefaultHandler`, for the same reason as `Canvas` and `Input`:
    /// a default would not save the callers anything (the effect still has to appear in
    /// every `@Test` signature) and it would let a forgotten interpretation pass unnoticed.
    ///
    pub def runWithNoOp(f: Unit -> a \ ef): a \ ef - Sound =
        run {
            f()
        } with handler Sound {
            def play(_cmd, k) = k()
        }

}
