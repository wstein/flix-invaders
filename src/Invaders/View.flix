///
/// Drawing a world.
///
/// Uses only the `Canvas` effect, so `Canvas.runCollecting` can record a frame as data and
/// the rendering tests need no display. Nothing here changes the world -- given the same
/// world, `render` always produces the same commands.
///
mod View {

    ///
    /// Draws a rectangle from its centre.
    ///
    /// The game stores positions as centres because that is what collision wants; `Canvas`
    /// takes a top-left corner because that is what drawing wants. This is the one place
    /// the two conventions meet.
    ///
    def box(pos: Vec2, size: Vec2): Unit \ Canvas =
        Canvas.rect(pos#x - size#x / 2.0f32, pos#y - size#y / 2.0f32, size#x, size#y)

    def drawInvaders(w: World): Unit \ Canvas =
        Vector.forEach(inv ->
            if (inv#alive) {
                Canvas.fill(Palette.mint());
                box(inv#pos, Rules.invaderSize())
            } else (), w#invaders)

    def drawShots(w: World): Unit \ Canvas = {
        Canvas.fill(Palette.sun());
        List.forEach(b -> box(b, Rules.bulletSize()), w#bullets);
        Canvas.fill(Palette.coral());
        List.forEach(b -> box(b, Rules.bombSize()), w#bombs)
    }

    def drawPlayer(w: World): Unit \ Canvas = {
        Canvas.fill(Palette.azure());
        box({ x = w#playerX, y = Rules.playerY() }, Rules.playerSize())
    }

    def drawHud(w: World): Unit \ Canvas = {
        Canvas.fill(Palette.dim());
        Canvas.textSize(14.0f32);
        Canvas.text("score ${w#score}", 20.0f32, 28.0f32);
        Canvas.text("lives ${w#lives}", Rules.fieldWidth() - 90.0f32, 28.0f32)
    }

    def drawEndMessage(w: World): Unit \ Canvas = match w#phase {
        case Phase.Playing => ()
        case Phase.Won => banner("you win", w)
        case Phase.Lost => banner("game over", w)
    }

    def banner(message: String, _w: World): Unit \ Canvas = {
        Canvas.fill(Palette.ink());
        Canvas.textSize(28.0f32);
        Canvas.text(message, Rules.fieldWidth() / 2.0f32 - 70.0f32, Rules.fieldHeight() / 2.0f32);
        Canvas.fill(Palette.dim());
        Canvas.textSize(14.0f32);
        Canvas.text("press enter to play again",
                    Rules.fieldWidth() / 2.0f32 - 88.0f32,
                    Rules.fieldHeight() / 2.0f32 + 30.0f32)
    }

    ///
    /// Describes one frame.
    ///
    pub def render(w: World): Unit \ Canvas = {
        Canvas.clear(Palette.background());
        drawInvaders(w);
        drawShots(w);
        drawPlayer(w);
        drawHud(w);
        drawEndMessage(w)
    }

}
