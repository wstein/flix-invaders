///
/// Drawing the cabinet, as opposed to drawing the game.
///
/// `View.render` knows how to draw one game and nothing else. This module decides *which*
/// game is on screen and what to overlay on top of it -- the title, the credits, the
/// invitation to press a key. It uses only the `Canvas` effect, so a test can record a whole
/// title screen as data without a window.
///
mod Screens {

    ///
    /// A translucent wash over the demo, so the title reads on top of it.
    ///
    /// Translucent rather than solid, and over the whole field rather than a band: a solid
    /// band cut the formation in half, which rather defeats an attract screen whose job is
    /// to show the game off.
    ///
    def veilAlpha(): Int32 = 170

    def veil(): Unit \ Canvas = {
        Canvas.fillAlpha(Palette.background(), veilAlpha());
        Canvas.rect(0.0f32, 0.0f32, Rules.fieldWidth(), Rules.fieldHeight())
    }

    def line(text: String, size: Float32, y: Float32, colour: Color): Unit \ Canvas = {
        Canvas.fill(colour);
        Canvas.textSize(size);
        Canvas.text(text, View.centredX(text, size), y)
    }

    ///
    /// The attract screen: the demo playing, with the title over it.
    ///
    def attract(s: Session): Unit \ Canvas = {
        View.render(Session.onScreen(s));
        veil();
        let middle = Rules.fieldHeight() / 2.0f32;
        line("FLIX INVADERS", View.bannerSize(), middle - 24.0f32, Palette.invaderGreen());
        line("PRESS 1 OR 2 TO PLAY", View.hudSize(), middle + 8.0f32, Palette.ink());
        line("- DEMO -", View.hudSize(), middle + 36.0f32, Palette.invaderCyan())
    }

    ///
    /// One frame of whatever the cabinet is showing.
    ///
    pub def render(s: Session): Unit \ Canvas = match s#screen {
        case Screen.Attract => attract(s)
        case Screen.Playing => View.renderWith(Session.active(s), Session.cabinet(s))
    }

}
