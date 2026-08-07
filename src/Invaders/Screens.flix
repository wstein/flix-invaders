///
/// Drawing the cabinet, as opposed to drawing the game.
///
/// `View.render` knows how to draw one game and nothing else. This module decides *which*
/// game is on screen and what to overlay on top of it -- the title, the credits, the
/// invitation to press a key. It uses only the `Canvas` effect, so a test can record a whole
/// title screen as data without a window.
///
mod Screens {

    /// A dimming wash over the demo, so the title reads clearly on top of it.
    def veil(): Unit \ Canvas = {
        Canvas.fill(Palette.background());
        // Drawn as a band behind the text rather than the whole field, which would hide the
        // game the attract screen exists to show off.
        Canvas.rect(0.0f32, Rules.fieldHeight() / 2.0f32 - 64.0f32, Rules.fieldWidth(), 128.0f32)
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
        case Screen.Playing => View.render(Session.onScreen(s))
    }

}
