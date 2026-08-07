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
        List.foldLeft((widest, c) -> Float32.max(widest, View.textWidth(c#text, c#size)), 0.0f32, captions)

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
        caption("PRESS 1 OR 2 TO PLAY", View.hudSize(), Palette.ink()) ::
        caption("- DEMO -", View.hudSize(), Palette.invaderCyan()) :: Nil

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
        View.render(Session.onScreen(s));
        let score = match s#pending {
            case entry :: _ => entry#score
            case Nil => 0
        };
        let caret = if (String.length(s#typing) < Scores.nameLength()) "_" else "";
        let captions =
            caption("NEW HIGH SCORE ${score}", View.hudSize(), Palette.sun()) ::
            caption(s#typing + caret, View.bannerSize(), Palette.ink()) ::
            caption("TYPE 3 LETTERS, ENTER", View.hudSize(), Palette.invaderCyan()) :: Nil;
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

    ///
    /// One frame of whatever the cabinet is showing.
    ///
    pub def render(s: Session): Unit \ Canvas = match s#screen {
        case Screen.Attract => attract(s)
        case Screen.Playing => View.renderWith(Session.active(s), Session.cabinet(s))
        case Screen.Entering => entering(s)
        case Screen.Table => table(s)
    }

}
