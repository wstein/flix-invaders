///
/// Making noise.
///
/// The second of the two modules in `src/` that touch Java, and the only one that touches
/// the sound card. Everything above it deals in `SoundCmd` values.
///
/// The waveforms are synthesized here at startup rather than loaded from files: an arcade
/// bleep is a swept square wave and a burst of noise, both of which are a few lines of
/// arithmetic, and this keeps the repository free of audio assets.
///
/// Nothing here is allowed to take the game down. A machine with no sound card -- a CI
/// runner, a headless server, a laptop with the output muted at the driver level -- raises
/// an `IllegalArgumentException` from deep inside `AudioSystem` rather than the declared
/// `LineUnavailableException`, so every entry point catches `Exception` and degrades to
/// silence.
///
mod Audio {

    import java.lang.Exception
    import javax.sound.sampled.AudioFormat
    import javax.sound.sampled.AudioSystem
    import javax.sound.sampled.Clip

    /// A pool of pre-opened clips, tagged with the sound each one plays.
    ///
    /// `Clip.start()` returns immediately, which is what the animation thread needs, but a
    /// single clip cannot overlap with itself -- restarting it cuts the sound in flight. So
    /// each sound gets several voices and a trigger takes the first idle one.
    pub type alias Voices = List[(SoundCmd, Clip)]

    def sampleRate(): Int32 = 22050

    def format(): AudioFormat \ IO =
        // 8-bit mono: one signed byte per sample, so there is no endianness to get wrong and
        // no packing to do -- Flix's Int8 maps straight onto Java's byte.
        new AudioFormat(Int32.toFloat32(sampleRate()), 8, 1, true, false)

    /// How many simultaneous voices each sound gets.
    def voicesFor(cmd: SoundCmd): Int32 = match cmd {
        // Firing and kills can stack up; the rest never overlap with themselves.
        case SoundCmd.Shoot => 3
        case SoundCmd.InvaderDies => 3
        case _ => 1
    }

    ///
    /// The fractional part of a non-negative number.
    ///
    /// Only ever called with an accumulated phase, which stays well inside Int32 for every
    /// frequency and duration this module generates.
    ///
    def frac(x: Float32): Float32 = match Float32.tryToInt32(x) {
        case Some(whole) => x - Int32.toFloat32(whole)
        case None => unreachable!()
    }

    /// Clips a sample into signed 8-bit range. `level` is always bounded by the amplitude
    /// the callers pass, so the conversion cannot fail.
    def toSample(level: Float32): Int8 = match Float32.tryToInt32(level) {
        case Some(whole) => Int32.clampToInt8(min = -127i8, max = 127i8, whole)
        case None => unreachable!()
    }

    type alias SweepSpec = { startHz = Float32, endHz = Float32, millis = Int32, volume = Float32 }

    ///
    /// A square wave sweeping from `startHz` to `endHz`, fading out over its length.
    ///
    /// The phase is the integral of a linearly swept frequency, which is what keeps the
    /// pitch glide smooth instead of stepping.
    ///
    def sweep(rc: Region[r], spec: SweepSpec): Array[Int8, r] \ r = {
        let f0 = spec#startHz;
        let f1 = spec#endHz;
        let count = Int32.max(1, (spec#millis * sampleRate()) / 1000);
        let seconds = Int32.toFloat32(spec#millis) / 1000.0f32;
        Array.init(rc, i -> {
            let t = Int32.toFloat32(i) / Int32.toFloat32(sampleRate());
            let progress = Int32.toFloat32(i) / Int32.toFloat32(count);
            let phase = f0 * t + (f1 - f0) * t * t / (2.0f32 * seconds);
            let square = if (frac(phase) < 0.5f32) 1.0f32 else -1.0f32;
            toSample(square * 110.0f32 * spec#volume * (1.0f32 - progress))
        }, count)
    }

    ///
    /// A burst of noise, fading out. Used for things blowing up.
    ///
    /// The generator is seeded per sample, so the burst is identical every run -- there is
    /// no reason for an explosion to differ between sessions.
    ///
    def burst(rc: Region[r], millis: Int32, volume: Float32): Array[Int8, r] \ r = {
        let count = Int32.max(1, (millis * sampleRate()) / 1000);
        Array.init(rc, i -> {
            let (value, _) = Rng.nextInt32Below(220, Rng.fromSeed(Int32.toInt64(i)));
            let progress = Int32.toFloat32(i) / Int32.toFloat32(count);
            toSample(Int32.toFloat32(value - 110) * volume * (1.0f32 - progress))
        }, count)
    }

    /// The four descending notes of the marching bassline.
    def marchHz(note: Int32): Float32 = match Int32.remainder(note, 4) {
        case 0 => 116.0f32
        case 1 => 104.0f32
        case 2 => 93.0f32
        case _ => 87.0f32
    }

    ///
    /// The waveform for one sound.
    ///
    def samplesFor(rc: Region[r], cmd: SoundCmd): Array[Int8, r] \ r = match cmd {
        case SoundCmd.Shoot =>
            sweep(rc, { startHz = 820.0f32, endHz = 1500.0f32, millis = 90, volume = 0.55f32 })
        case SoundCmd.InvaderDies =>
            burst(rc, 190, 0.7f32)
        case SoundCmd.PlayerDies =>
            burst(rc, 620, 1.0f32)
        case SoundCmd.MysteryAppears =>
            sweep(rc, { startHz = 620.0f32, endHz = 900.0f32, millis = 220, volume = 0.4f32 })
        case SoundCmd.MysteryDies =>
            sweep(rc, { startHz = 900.0f32, endHz = 180.0f32, millis = 380, volume = 0.6f32 })
        case SoundCmd.ShieldBlock =>
            sweep(rc, { startHz = 300.0f32, endHz = 1100.0f32, millis = 130, volume = 0.5f32 })
        case SoundCmd.ExtraLife =>
            sweep(rc, { startHz = 500.0f32, endHz = 1600.0f32, millis = 420, volume = 0.6f32 })
        case SoundCmd.MarchStep(note) => {
            let hz = marchHz(note);
            sweep(rc, { startHz = hz, endHz = hz * 0.92f32, millis = 110, volume = 0.85f32 })
        }
    }

    /// Opens one clip loaded with `cmd`'s waveform, or `None` if the device refuses.
    def openVoice(fmt: AudioFormat, cmd: SoundCmd): Option[Clip] \ IO =
        try {
            region rc {
                let data = samplesFor(rc, cmd);
                let clip = AudioSystem.getClip();
                clip.open(fmt, data, 0, Array.length(data));
                Some(clip)
            }
        } catch {
            // Includes IllegalArgumentException, which is what a machine with no mixer
            // actually throws -- catching only LineUnavailableException would miss it.
            case _: Exception => None
        }

    ///
    /// Synthesizes every sound and opens its voices.
    ///
    /// Returns an empty list if audio is unavailable, which every other function here treats
    /// as "play nothing".
    ///
    pub def open(): Voices \ IO =
        try {
            let fmt = format();
            List.flatMap(cmd ->
                List.filterMap(_ -> match openVoice(fmt, cmd) {
                    case Some(clip) => Some((cmd, clip))
                    case None => None
                }, List.range(0, voicesFor(cmd))),
                SoundCmd.all())
        } catch {
            case _: Exception => Nil
        }

    ///
    /// Triggers `cmd` on its first idle voice.
    ///
    /// If every voice for that sound is still playing the trigger is dropped, which is
    /// ordinary game-audio voice stealing and keeps this O(pool size) with no allocation on
    /// the animation thread.
    ///
    pub def play(voices: Voices, cmd: SoundCmd): Unit \ IO =
        try {
            // `findLeft` stops at the first idle voice, so a sound with three lines free does
            // not restart all three.
            match List.findLeft(entry -> fst(entry) == cmd and not snd(entry).isRunning(), voices) {
                case None => ()
                case Some((_, clip)) => {
                    clip.setFramePosition(0);
                    clip.start()
                }
            }
        } catch {
            case _: Exception => ()
        }

    /// Releases every line. Safe to call when audio never opened.
    pub def close(voices: Voices): Unit \ IO =
        try {
            List.forEach(entry -> {
                let (_, clip) = entry;
                clip.close()
            }, voices)
        } catch {
            case _: Exception => ()
        }

}
