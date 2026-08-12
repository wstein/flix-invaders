mod TestScoresFile {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertTrueWithMsg

    ///
    /// Reading and writing the high-score file, on a filesystem that does not exist.
    ///
    /// This is the one file in `test/` allowed to name `Fs.`, and it must run entirely in
    /// memory. `Fs.FileWrite` carries a `@DefaultHandler` that writes to the real disk, so a
    /// test that simply forgot a handler would still compile and would then scribble on the
    /// machine running it. CI enforces the rule this file follows: anything mentioning `Fs.`
    /// must also install `withInMemoryFS`.
    ///
    /// `withInMemoryFS` leaves a residual `Clock` -- file timestamps -- which is handled here
    /// with a frozen one rather than the default. Nothing below touches the outside world at
    /// all, not even to ask what time it is.
    ///

    type alias FsEffects = Fs.FileRead + Fs.FileWrite + Fs.FileSystem + Time.Clock

    def onMemoryFS(f: Unit -> a \ ef)
        : a \ (ef - FsEffects) =
        frozenClock(() ->
            Fs.FileSystem.withInMemoryFS(() ->
                Fs.FileWrite.runWithFileSystem(() ->
                    Fs.FileRead.runWithFileSystem(f))))

    def frozenClock(f: Unit -> a \ ef)
        : a \ (ef - Time.Clock) =
        run {
            f()
        } with handler Time.Clock {
            def currentTime(_unit, k) = k(0i64)
        }

    /// A directory that has never existed, so saving has to create it.
    def somewhere(): Scores.Location =
        { dir = "/nowhere/flix-invaders", file = "/nowhere/flix-invaders/scores.txt" }

    def entry(name: String, score: Int32): Entry =
        { name = name, score = score, level = 3 }

    def shown(e: Entry): String = "${e#name}/${e#score}/${e#level}"
    def shownAll(es: List[Entry]): List[String] = List.map(shown, es)

    /// The table `load` returns, or a failure with the error in the message.
    def loaded(at: Scores.Location): List[Entry] \ Fs.FileRead + Assert =
        match Scores.load(at) {
            case Ok(entries) => entries
            case Err(why) => { Assert.fail("load failed: ${why}"); Nil }
        }

    def saved(at: Scores.Location, entries: List[Entry]): Unit \ Fs.FileWrite + Assert =
        match Scores.save(at, entries) {
            case Ok() => ()
            case Err(why) => Assert.fail("save failed: ${why}")
        }

    // -- the round trip -------------------------------------------------------------------

    @Test
    def testATableSurvivesASaveAndLoad(): Unit \ Assert = onMemoryFS(() -> {
        let table = entry("WLS", 4200) :: entry("ABC", 900) :: Nil;
        let at = somewhere();
        saved(at, table);
        assertEq(expected = shownAll(table), shownAll(loaded(at)))
    })

    @Test
    def testTheFirstRunHasNoFileAndNoScores(): Unit \ Assert = onMemoryFS(() ->
        // A missing file is the ordinary first run, not an error to report.
        match Scores.load(somewhere()) {
            case Ok(entries) => assertTrue(List.isEmpty(entries))
            case Err(why) => Assert.fail("a missing file should be an empty table, got ${why}")
        })

    @Test
    def testSavingCreatesTheDirectory(): Unit \ Assert = onMemoryFS(() -> {
        // Nothing has created `/nowhere/flix-invaders`; `save` must do it itself.
        let at = somewhere();
        saved(at, entry("NEW", 10) :: Nil);
        assertEq(expected = 1, List.length(loaded(at)))
    })

    @Test
    def testSavingReplacesRatherThanAppends(): Unit \ Assert = onMemoryFS(() -> {
        // The table is written whole every time. If this appended, a table would grow by its
        // own length on every run and the file would double each session.
        let at = somewhere();
        saved(at, entry("AAA", 100) :: Nil);
        saved(at, entry("BBB", 200) :: Nil);
        assertEq(expected = shownAll(entry("BBB", 200) :: Nil), shownAll(loaded(at)))
    })

    @Test
    def testWhatIsStoredIsRankedAndCapped(): Unit \ Assert = onMemoryFS(() -> {
        // The file is not allowed to grow without bound, however the session got there.
        let at = somewhere();
        saved(at, List.map(i -> entry("X", i * 10), List.range(1, 40)));
        let back = loaded(at);
        assertEq(expected = Scores.places(), List.length(back));
        assertEq(expected = Some(390), Option.map(e -> e#score, List.head(back)))
    })

    // -- damage ---------------------------------------------------------------------------

    @Test
    def testAHandEditedFileLosesOnlyTheBadLines(): Unit \ Assert = onMemoryFS(() -> {
        // Corrupting the file should cost you those entries, not the game.
        let at = somewhere();
        Fs.FileWrite.writeLines(lines = "AAA|100|1" :: "nonsense" :: "CCC|50|2" :: Nil, at#file)
            |> Result.mapErr(why -> Assert.fail("could not plant a corrupt file: ${why}"))
            |> Result.getWithDefault(());
        assertEq(expected = "AAA" :: "CCC" :: Nil, List.map(e -> e#name, loaded(at)))
    })

    ///
    /// Every read fails with `kind`.
    ///
    /// The distinction below is about which errors `load` translates, which is easier to
    /// state as an injected failure than to provoke out of a filesystem -- the in-memory one
    /// is happy to read a directory, and provoking a permissions error on a real one would
    /// need a real one.
    ///
    def readingFails(kind: IoError.ErrorKind, f: Unit -> a \ ef): a \ (ef - Fs.FileRead) = {
        // Spelled out per operation rather than shared: the three results differ in their
        // success type, so one binding cannot stand for all of them.
        def failure() = IoError.IoError(kind, "injected by a test");
        run {
            f()
        } with handler Fs.FileRead {
            def read(_file, k) = k(Err(failure()))
            def readBytes(_file, k) = k(Err(failure()))
            def readLines(_file, k) = k(Err(failure()))
        }
    }

    @Test
    def testAMissingFileIsTranslatedToAnEmptyTable(): Unit \ Assert =
        readingFails(IoError.ErrorKind.NotFound, () ->
            match Scores.load(somewhere()) {
                case Ok(entries) => assertTrue(List.isEmpty(entries))
                case Err(why) => Assert.fail("NotFound should mean no scores yet, got ${why}")
            })

    @Test
    def testAnUnreadableFileIsNotSilentlyAnEmptyTable(): Unit \ Assert =
        // The distinction `load` exists to preserve: "no scores yet" and "I could not read
        // your scores" must not look the same. If they did, the save on the way out would
        // overwrite a table the game merely failed to read.
        readingFails(IoError.ErrorKind.PermissionDenied, () ->
            match Scores.load(somewhere()) {
                case Err(_) => assertTrue(true)
                case Ok(_) => Assert.fail("an unreadable file was reported as an empty table")
            })

}
