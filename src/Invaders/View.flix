///
/// Drawing a world.
///
/// Uses only the `Canvas` effect, so `Canvas.runCollecting` can record a frame as data and
/// the rendering tests need no display. Nothing here changes the world -- given the same
/// world, `render` always produces the same commands, which is why a replayed game renders
/// identically.
///
mod View {

    ///
    /// How many ticks each animation frame is held for.
    ///
    /// The invaders have two frames each; alternating them is the entire animation budget of
    /// the original, and it is what makes the formation look like it is walking.
    ///
    def frameHold(): Int32 = 22

    def animationFrame(w: World): Int32 =
        Int32.remainder(w#tick / frameHold(), 2)

    ///
    /// The colour band a row belongs to.
    ///
    /// The original arcade machine had a black-and-white monitor; the colours came from a
    /// strip of coloured cellophane stuck over the glass, which is why they are horizontal
    /// bands that do not line up with the creature types.
    ///
    def rowColor(row: Int32): Color =
        if (row <= 1) Palette.invaderGreen()
        else if (row <= 3) Palette.invaderCyan()
        else Palette.invaderMagenta()

    def drawInvaders(w: World): Unit \ Canvas = {
        let frame = animationFrame(w);
        // Built once per frame rather than once per invader: with 55 of them, rebuilding a
        // sprite inside the loop cost about half the frame rate.
        let squid = Sprites.forKind(InvaderKind.Squid, frame);
        let crab = Sprites.forKind(InvaderKind.Crab, frame);
        let octopus = Sprites.forKind(InvaderKind.Octopus, frame);
        Vector.forEach(inv ->
            if (inv#alive) {
                Canvas.fill(rowColor(inv#row));
                let sprite = match inv#kind {
                    case InvaderKind.Squid => squid
                    case InvaderKind.Crab => crab
                    case InvaderKind.Octopus => octopus
                };
                Sprite.draw(sprite, inv#pos, Rules.spriteScale())
            } else (), w#invaders)
    }

    def drawShots(w: World): Unit \ Canvas = {
        let bullet = Sprites.bullet();
        let bomb = Sprites.bomb();
        Canvas.fill(Palette.shot());
        List.forEach(b -> Sprite.draw(bullet, b, Rules.spriteScale()), w#bullets);
        Canvas.fill(Palette.coral());
        List.forEach(b -> Sprite.draw(bomb, b, Rules.spriteScale()), w#bombs)
    }

    ///
    /// Destroyed blocks simply are not drawn, which is the whole of the damage model
    /// showing through.
    ///
    def drawBunkers(w: World): Unit \ Canvas = {
        Canvas.fill(Palette.coral());
        let cell = Rules.bunkerCell();
        Vector.forEach(bunker ->
            List.forEach(segment -> {
                let (row, column, length) = segment;
                Canvas.rect(bunker#origin#x + Int32.toFloat32(column) * cell,
                            bunker#origin#y + Int32.toFloat32(row) * cell,
                            Int32.toFloat32(length) * cell,
                            cell)
            }, Bunkers.runs(bunker)),
            w#bunkers)
    }

    def drawPlayer(w: World): Unit \ Canvas = {
        Canvas.fill(Palette.cannonGreen());
        Sprite.draw(Sprites.cannon(), { x = w#playerX, y = Rules.playerY() }, Rules.cannonScale())
    }

    // -- the cabinet furniture --------------------------------------------------------

    def zeros(n: Int32): String =
        if (n <= 0) "" else "0" + zeros(n - 1)

    /// Left-pads a score with zeros, the way the cabinet displays it.
    def scoreText(value: Int32): String = {
        let digits = Int32.toString(value);
        zeros(4 - String.length(digits)) + digits
    }

    def drawHud(w: World): Unit \ Canvas = {
        Canvas.textSize(14.0f32);

        Canvas.fill(Palette.invaderCyan());
        Canvas.text("SCORE<1>", 34.0f32, 26.0f32);
        Canvas.fill(Palette.ink());
        Canvas.text("HI-SCORE", 262.0f32, 26.0f32);
        Canvas.fill(Palette.sun());
        Canvas.text("SCORE<2>", 486.0f32, 26.0f32);

        Canvas.fill(Palette.ink());
        Canvas.text(scoreText(w#score), 52.0f32, 48.0f32);
        Canvas.text(scoreText(w#hiScore), 280.0f32, 48.0f32);
        Canvas.text(scoreText(0), 504.0f32, 48.0f32)
    }

    ///
    /// The green line the cannon stands on, the remaining lives, and the credit counter.
    ///
    def drawCabinet(w: World): Unit \ Canvas = {
        Canvas.fill(Palette.ground());
        Canvas.rect(0.0f32, Rules.groundY(), Rules.fieldWidth(), 2.0f32);

        Canvas.fill(Palette.ink());
        Canvas.textSize(14.0f32);
        Canvas.text("${w#lives}", 20.0f32, Rules.fieldHeight() - 6.0f32);

        // One small cannon per life still in reserve, so the count is readable at a glance.
        Canvas.fill(Palette.cannonGreen());
        drawSpareLives(Sprites.cannon(), w#lives - 1, 0);

        Canvas.fill(Palette.ink());
        Canvas.text("CREDIT 01", Rules.fieldWidth() - 108.0f32, Rules.fieldHeight() - 6.0f32)
    }

    def drawSpareLives(cannon: Sprite, remaining: Int32, index: Int32): Unit \ Canvas =
        if (index >= remaining) ()
        else {
            let x = 52.0f32 + Int32.toFloat32(index) * 40.0f32;
            Sprite.draw(cannon, { x = x, y = Rules.fieldHeight() - 14.0f32 }, 2.0f32);
            drawSpareLives(cannon, remaining, index + 1)
        }

    def drawEndMessage(w: World): Unit \ Canvas = match w#phase {
        case Phase.Playing => ()
        case Phase.Won => banner("YOU WIN")
        case Phase.Lost => banner("GAME OVER")
    }

    def banner(message: String): Unit \ Canvas = {
        Canvas.fill(Palette.ink());
        Canvas.textSize(30.0f32);
        Canvas.text(message, Rules.fieldWidth() / 2.0f32 - 80.0f32, Rules.fieldHeight() / 2.0f32);
        Canvas.fill(Palette.invaderCyan());
        Canvas.textSize(14.0f32);
        Canvas.text("PRESS ENTER TO PLAY AGAIN",
                    Rules.fieldWidth() / 2.0f32 - 96.0f32,
                    Rules.fieldHeight() / 2.0f32 + 32.0f32)
    }

    ///
    /// Describes one frame.
    ///
    pub def render(w: World): Unit \ Canvas = {
        Canvas.clear(Palette.background());
        drawInvaders(w);
        drawBunkers(w);
        drawShots(w);
        drawPlayer(w);
        drawHud(w);
        drawCabinet(w);
        drawEndMessage(w)
    }

}
