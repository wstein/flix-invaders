mod TestScores {

    use Assert.assertEq
    use Assert.assertTrue
    use Assert.assertFalse

    ///
    /// Everything here runs with no handler at all. Deciding *what* the table contains is
    /// ordinary arithmetic on ordinary data; only reading and writing the file is an effect,
    /// and that lives in `main` where no test can reach it.
    ///

    def entry(name: String, score: Int32): Entry = { name = name, score = score, level = 1 }

    def names(es: List[Entry]): List[String] = List.map(e -> e#name, es)
    def points(es: List[Entry]): List[Int32] = List.map(e -> e#score, es)

    /// Records have no `Eq`, so entries are compared by a rendering of their fields.
    def shown(e: Entry): String = "${e#name}/${e#score}/${e#level}"
    def shownAll(es: List[Entry]): List[String] = List.map(shown, es)

    // -- parsing ------------------------------------------------------------------------

    @Test
    def testALineRoundTrips(): Unit \ Assert = {
        let original = { name = "WLS", score = 4200, level = 7 };
        match Scores.render(original :: Nil) {
            case line :: Nil => match Scores.parseLine(line) {
                case Some(back) => assertEq(expected = shown(original), shown(back))
                case None => Assert.fail("a rendered line did not parse back")
            }
            case _ => Assert.fail("render produced the wrong number of lines")
        }
    }

    @Test
    def testAWholeTableRoundTrips(): Unit \ Assert = {
        let table = entry("AAA", 300) :: entry("BBB", 200) :: entry("CCC", 100) :: Nil;
        assertEq(expected = shownAll(table), shownAll(Scores.parse(Scores.render(table))))
    }

    @Test
    def testMalformedLinesAreDroppedNotFatal(): Unit \ Assert = {
        // A truncated or hand-edited file should cost you the table, not the game.
        let lines = "AAA|100|1" :: "rubbish" :: "" :: "BBB|not-a-number|1" :: "CCC|50|2" :: Nil;
        assertEq(expected = "AAA" :: "CCC" :: Nil, names(Scores.parse(lines)))
    }

    @Test
    def testWhitespaceIsTolerated(): Unit \ Assert =
        assertEq(expected = Some(shown(entry("ZZ", 10))),
                 Option.map(shown, Scores.parseLine(" ZZ | 10 | 1 ")))

    @Test
    def testAnEmptyFileIsAnEmptyTable(): Unit \ Assert =
        assertTrue(List.isEmpty(Scores.parse(Nil)))

    // -- names --------------------------------------------------------------------------

    @Test
    def testNamesAreClampedToThreeCharacters(): Unit \ Assert =
        assertEq(expected = "ABC", Scores.clean("ABCDEF"))

    @Test
    def testOnlyLettersAndDigitsSurvive(): Unit \ Assert = {
        // A file can contain anything; the cabinet can only draw these.
        assertEq(expected = "AB1", Scores.clean("A-B_1!"));
        assertEq(expected = "", Scores.clean("...|..."))
    }

    @Test
    def testShortNamesArePaddedForTheTable(): Unit \ Assert = {
        assertEq(expected = 3, String.length(Scores.padded("A")));
        assertEq(expected = 3, String.length(Scores.padded("ABC")))
    }

    @Test
    def testASeparatorInANameCannotCorruptTheFile(): Unit \ Assert = {
        // The stored format is delimited, so a name containing the delimiter would produce
        // a line that parses back as something else entirely.
        let dodgy = { name = Scores.clean("A|B"), score = 10, level = 1 };
        let line = Scores.render(dodgy :: Nil) |> List.head |> Option.getWithDefault("");
        assertEq(expected = Some(shown(dodgy)), Option.map(shown, Scores.parseLine(line)))
    }

    // -- ordering and qualification -------------------------------------------------------

    @Test
    def testTheTableIsSortedBestFirst(): Unit \ Assert = {
        let table = Scores.ranked(entry("A", 100) :: entry("B", 900) :: entry("C", 500) :: Nil);
        assertEq(expected = 900 :: 500 :: 100 :: Nil, points(table))
    }

    @Test
    def testTheTableIsCapped(): Unit \ Assert = {
        let many = List.map(i -> entry("X", i * 10), List.range(0, 40));
        assertEq(expected = Scores.places(), List.length(Scores.ranked(many)))
    }

    @Test
    def testInsertingKeepsTheOrderAndTheCap(): Unit \ Assert = {
        let table = List.map(i -> entry("X", i * 10), List.range(1, Scores.places() + 1));
        let after = Scores.insert(entry("NEW", 10000), table);
        assertEq(expected = Scores.places(), List.length(after));
        assertEq(expected = Some("NEW"), List.head(names(after)))
    }

    @Test
    def testAnEmptyTableAcceptsAnything(): Unit \ Assert =
        assertTrue(Scores.qualifies(10, Scores.empty()))

    @Test
    def testAZeroNeverQualifies(): Unit \ Assert = {
        // There is no dignity in immortalising a game you did not play.
        assertFalse(Scores.qualifies(0, Scores.empty()));
        assertFalse(Scores.qualifies(-5, Scores.empty()))
    }

    @Test
    def testAFullTableOnlyAcceptsABetterScore(): Unit \ Assert = {
        let table = List.map(_ -> entry("X", 1000), List.range(0, Scores.places()));
        assertFalse(Scores.qualifies(999, table));
        assertTrue(Scores.qualifies(1001, table))
    }

    @Test
    def testBestIsTheTopScore(): Unit \ Assert = {
        assertEq(expected = 0, Scores.best(Scores.empty()));
        assertEq(expected = 900, Scores.best(entry("A", 100) :: entry("B", 900) :: Nil))
    }

}
