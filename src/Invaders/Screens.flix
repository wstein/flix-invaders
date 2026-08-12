///
/// One line of an overlay: what it says, how big, and in what colour.
///
pub type alias Caption = { text = String, size = Float32, colour = Color }

///
/// Drawing the cabinet, as opposed to drawing the game.
///
/// `View.render` knows how to draw one game and nothing else. This module decides *which*
/// game is on screen and what to overlay on it -- the title, the invitation to press a key,
/// the score table. It uses only the `Canvas` effect, so a test can record a whole title
/// screen as data without a window.
///
mod Screens {

    ///
    /// How dark the panel behind overlay text is.
    ///
    /// Light enough that the game keeps playing visibly through it. The point of an attract
    /// screen is the game; the text only has to stay readable where it crosses a sprite.
    ///
    def panelAlpha(): Int32 = 130

    def padding(): Float32 = 12.0f32
    def leading(): Float32 = 12.0f32

    /// The width of the widest caption.
    def blockWidth(captions: List[Caption]): Float32 =
        List.foldLeft((widest, c) ->
            Float32.max(widest, View.textWidth(c#text, c#size)),
            0.0f32, captions)

    /// The height the captions occupy once stacked.
    def blockHeight(captions: List[Caption]): Float32 =
        List.foldLeft((total, c) -> total + c#size + leading(), 0.0f32, captions) - leading()

    /// Draws a stack of centred captions, starting with the first baseline a line down.
    def stack(captions: List[Caption], top: Float32): Unit \ Canvas = {
        def draw(rest, y) = match rest {
            case Nil => ()
            case c :: more => {
                Canvas.fill(c#colour);
                Canvas.textSize(c#size);
                Canvas.text(c#text, View.centredX(c#text, c#size), y + c#size);
                draw(more, y + c#size + leading())
            }
        };
        draw(captions, top)
    }

    ///
    /// Draws captions on a translucent panel sized to fit them.
    ///
    /// Sized to the text rather than spanning the screen: a full-width band hid whichever
    /// invaders happened to be behind it, and dimming the whole field made the demo murky.
    ///
    def block(captions: List[Caption], top: Float32): Unit \ Canvas = {
        let width = blockWidth(captions);
        let height = blockHeight(captions);
        Canvas.fillAlpha(Palette.background(), panelAlpha());
        Canvas.rect((Rules.fieldWidth() - width) / 2.0f32 - padding(),
                    top - padding(),
                    width + 2.0f32 * padding(),
                    height + 2.0f32 * padding());
        stack(captions, top)
    }

    def caption(text: String, size: Float32, colour: Color): Caption =
        { text = text, size = size, colour = colour }

    /// Where a block of `captions` starts if it is to sit centred in the field.
    def centredTop(captions: List[Caption]): Float32 =
        (Rules.fieldHeight() - blockHeight(captions)) / 2.0f32

    ///
    /// The attract screen: the demo playing at full brightness, with the title over it.
    ///
    def attract(s: Session): Unit \ Canvas = {
        View.render(Session.onScreen(s));
        block(attractCaptions(), centredTop(attractCaptions()))
    }

    def attractCaptions(): List[Caption] =
        caption("FLIX INVADERS", View.bannerSize(), Palette.invaderGreen()) ::
        caption(Meta.label(), View.hudSize(), Palette.invaderGreen()) ::
        caption("PRESS 1 OR 2 FOR PLAYERS TO PLAY", View.hudSize(), Palette.ink()) :: Nil

    ///
    /// The top edge of the attract screen's panel.
    ///
    /// Public because `View` has to stay clear of it. The demo plays *behind* this panel, so
    /// anything the game itself draws at the middle of the field -- the level banner between
    /// waves, most of all -- lands inside it and neither is readable.
    ///
    pub def attractPanelTop(): Float32 = centredTop(attractCaptions()) - padding()

    ///
    /// Asking for the initials that go beside a qualifying score.
    ///
    /// The caret is a literal underscore rather than a drawn rectangle, so it lines up with
    /// the monospaced font for free.
    ///
    def entering(s: Session): Unit \ Canvas = {
        // Told who else is playing, like the playing screen: a two-player game must still show
        // both scores while the second player is typing.
        View.renderWith(Session.onScreen(s), Session.cabinet(s));
        let asking = List.head(s#pending);
        let score = asking |> Option.map(claim -> claim#entry#score) |> Option.getWithDefault(0);
        let caret = if (String.length(s#typing) < Scores.nameLength()) "_" else "";

        // Whose initials these are, but only when there is more than one candidate. In a
        // one-player game naming the player is noise; in a two-player game the prompts arrive
        // back to back and are otherwise indistinguishable -- the first version of this screen
        // asked twice without ever saying who it was asking.
        let whose =
            if (s#players < 2) Nil
            else asking
                |> Option.map(claim -> caption("PLAYER ${claim#player + 1}",
                                               View.hudSize(), Palette.invaderGreen()) :: Nil)
                |> Option.getWithDefault(Nil);

        let captions = List.append(whose,
            caption("NEW HIGH SCORE ${score}", View.hudSize(), Palette.sun()) ::
            caption(s#typing + caret, View.bannerSize(), Palette.ink()) ::
            caption("TYPE 3, THEN ENTER", View.hudSize(), Palette.invaderCyan()) :: Nil);
        block(captions, centredTop(captions))
    }

    ///
    /// The high-score table, on its own rather than over the game.
    ///
    def table(s: Session): Unit \ Canvas = {
        Canvas.clear(Palette.background());
        Canvas.fill(Palette.invaderGreen());
        Canvas.textSize(View.bannerSize());
        Canvas.text("HIGH SCORES", View.centredX("HIGH SCORES", View.bannerSize()), 64.0f32);

        let rows =
            if (List.isEmpty(s#scores)) caption("NOBODY YET", View.hudSize(), Palette.dim()) :: Nil
            else List.mapWithIndex((i, e) ->
                caption("${Scores.padded(e#name)}  ${View.scoreText(e#score)}  L${e#level}",
                        View.hudSize(),
                        if (i == 0) Palette.sun() else Palette.ink()), s#scores);
        // No panel here: there is no game behind this screen to see through to.
        stack(rows, 110.0f32);

        Canvas.fill(Palette.invaderCyan());
        Canvas.textSize(View.hudSize());
        Canvas.text("PRESS ENTER",
                    View.centredX("PRESS ENTER", View.hudSize()),
                    Rules.fieldHeight() - 40.0f32)
    }

    // -- stats for nerds ------------------------------------------------------------------

    def nerdSize(): Float32 = 10.0f32
    def nerdLeft(): Float32 = 12.0f32
    def nerdTop(): Float32 = 64.0f32
    def nerdLine(): Float32 = 13.0f32
    def nerdWidth(): Float32 = 214.0f32

    ///
    /// The telemetry overlay, in the corner, on F3.
    ///
    /// Left-aligned and monospaced-by-accident -- the arcade font is fixed width -- so the
    /// numbers sit in columns and a changing digit is easy to catch out of the corner of an
    /// eye. Deliberately in the top left, clear of the score row above it, the formation, and
    /// the attract panel across the middle.
    ///
    /// What it shows is chosen to answer the questions this project actually asks: is the
    /// frame budget being met, is the simulation keeping up, and is the world where you think
    /// it is. `DIGEST` is the same fingerprint the replay tests compare, so two runs that
    /// should be identical can be checked against each other by eye.
    ///
    def nerds(s: Session, telemetry: Stats): Unit \ Canvas = {
        let w = Session.onScreen(s);
        let lines = nerdLines(s, w, telemetry);
        let height = Int32.toFloat32(List.length(lines)) * nerdLine() + padding();

        Canvas.fillAlpha(Palette.background(), 190);
        Canvas.rect(nerdLeft() - padding() / 2.0f32, nerdTop() - nerdLine(),
                    nerdWidth(), height);

        Canvas.textSize(nerdSize());
        List.forEachWithIndex((i, line) -> {
            let (label, value) = line;
            Canvas.fill(Palette.dim());
            Canvas.text(label, nerdLeft(), nerdTop() + Int32.toFloat32(i) * nerdLine());
            Canvas.fill(Palette.invaderCyan());
            Canvas.text(value, nerdLeft() + 84.0f32, nerdTop() + Int32.toFloat32(i) * nerdLine())
        }, lines)
    }

    ///
    /// What the overlay says, as label and value pairs.
    ///
    /// Split out from the drawing so a test can read it. Everything here is a pure function of
    /// the session and the figures the runtime handed over.
    ///
    pub def nerdLines(s: Session, w: World, telemetry: Stats): List[(String, String)] = {
        let alive = Vector.count(inv -> inv#alive, w#invaders);
        let blocks = Vector.foldLeft((total, b) -> total + Bunkers.remaining(b), 0, w#bunkers);
        ("FPS", Stats.oneDecimal(telemetry#fps)) ::
        ("SIM", "${Stats.twoDecimals(telemetry#simMs)} MS") ::
        ("DRAW", "${Stats.twoDecimals(telemetry#drawMs)} MS") ::
        ("BUDGET", "${Stats.twoDecimals(telemetry#simMs + telemetry#drawMs)} / "
                 + "${Stats.twoDecimals(1000.0f32 / Int32.toFloat32(Rules.ticksPerSecond()))} MS") ::
        ("STEPS", "${telemetry#steps}  CATCHUP ${telemetry#catchUps}") ::
        ("FRAMES", "${telemetry#frames}") ::
        ("SCREEN", "${s#screen}") ::
        ("TICK", "${w#tick}  LEVEL ${w#level}") ::
        ("INVADERS", "${alive} / ${Rules.totalInvaders()}") ::
        ("SHOTS", "${List.length(w#bullets)} UP  ${List.length(w#bombs)} DOWN") ::
        ("BUNKERS", "${blocks}") ::
        ("SHIELD", "${w#shield}") ::
        ("SEED", "${w#seed}") ::
        ("DIGEST", digestOf(w)) :: Nil
    }

    /// The replay fingerprint, shortened to something a person can compare at a glance.
    def digestOf(w: World): String = {
        let full = Game.digest(w);
        if (String.length(full) <= 22) full else String.takeLeft(22, full) + ".."
    }

    ///
    /// The beat between one player's game ending and the next player's starting.
    ///
    /// Their own fresh field is already behind it, so what they are about to play is visible
    /// while they get a hand back on the controls. On the same dimmed panel the title uses,
    /// for the same reason: the field behind stays legible, and a plain overlay of text on a
    /// formation is hard to read at a glance.
    ///
    /// Same position and same count as the pause between waves -- it is the same idea, and
    /// two different countdowns would be two things to learn.
    ///
    def handover(s: Session): Unit \ Canvas = {
        View.renderWith(Session.active(s), Session.cabinet(s));
        let count = View.countdown(s#handover);
        let digits =
            if (count <= 0) Nil
            else caption("${count}", View.countdownSize(), Palette.sun()) :: Nil;
        let captions =
            caption("PLAYER ${s#current + 1}", View.bannerSize(), Palette.ink()) ::
            caption("GET READY", View.hudSize(), Palette.invaderCyan()) ::
            digits;
        // Positioned so the first line lands on the same baseline as every other banner.
        block(captions, View.bannerY() - View.bannerSize())
    }

    ///
    /// The beat after a game ends, before anything replaces it.
    ///
    /// On the same dimmed panel as the title and the hand-over. It names the player in a
    /// two-player game for the same reason the initials prompt does: two people finish one
    /// after the other, and an unlabelled GAME OVER between them says nothing about whose.
    ///
    def gameOver(s: Session): Unit \ Canvas = {
        View.renderWith(Session.active(s), Session.cabinet(s));
        let whose =
            if (s#players < 2) Nil
            else caption("PLAYER ${s#current + 1}", View.hudSize(), Palette.invaderGreen()) :: Nil;
        let captions = List.append(whose,
            caption("GAME OVER", View.bannerSize(), Palette.ink()) :: Nil);
        block(captions, View.bannerY() - View.bannerSize())
    }

    ///
    /// One frame of whatever the cabinet is showing.
    ///
    pub def render(s: Session, telemetry: Stats): Unit \ Canvas = {
        match s#screen {
            case Screen.Attract => attract(s)
            case Screen.Playing =>
                if (s#over > 0) gameOver(s)
                else if (s#handover > 0) handover(s)
                else View.renderWith(Session.active(s), Session.cabinet(s))
            case Screen.Entering => entering(s)
            case Screen.Table => table(s)
        };
        if (s#nerds) nerds(s, telemetry) else ()
    }

}
