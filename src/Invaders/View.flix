///
/// Drawing a world.
///
/// Uses only the `Canvas` effect, so `Canvas.runWithCollector` can record a frame as data and
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

    ///
    /// The cannon, unless it is currently a pile of wreckage.
    ///
    def drawPlayer(w: World): Unit \ Canvas =
        if (List.exists(b -> b#kind == BlastKind.PlayerBlast, w#blasts)) ()
        else {
            Canvas.fill(Palette.cannonGreen());
            Sprite.draw(Sprites.cannon(), { x = w#playerX, y = Rules.playerY() }, Rules.cannonScale())
        }

    def drawMystery(w: World): Unit \ Canvas = match w#mystery {
        case None => ()
        case Some(m) => {
            Canvas.fill(Palette.invaderMagenta());
            Sprite.drawScaled(Sprites.mystery(), { x = m#x, y = Rules.mysteryY() },
                              scaleX = Rules.mysteryScaleX(), scaleY = Rules.mysteryScaleY())
        }
    }

    ///
    /// The shield, as a bracket over the cannon.
    ///
    /// It flashes for the last stretch so its expiry is something you see coming rather than
    /// discover by dying.
    ///
    def drawShield(w: World): Unit \ Canvas =
        if (w#shield <= 0) ()
        else {
            let failing = w#shield < Rules.shieldWarningTicks();
            let blink = Int32.remainder(w#shield / 8, 2) == 0;
            if (failing and blink) ()
            else {
                let half = Rules.playerSize()#x / 2.0f32 + 6.0f32;
                let top = Rules.playerY() - Rules.playerSize()#y / 2.0f32 - 8.0f32;
                Canvas.fill(Palette.invaderCyan());
                Canvas.rect(w#playerX - half, top, half * 2.0f32, 3.0f32);
                Canvas.rect(w#playerX - half, top, 3.0f32, 10.0f32);
                Canvas.rect(w#playerX + half - 3.0f32, top, 3.0f32, 10.0f32)
            }
        }

    def drawBlasts(w: World): Unit \ Canvas =
        List.forEach(b -> {
            Canvas.fill(match b#kind {
                case BlastKind.InvaderBlast => Palette.ink()
                case BlastKind.PlayerBlast => Palette.coral()
            });
            let scale = match b#kind {
                case BlastKind.InvaderBlast => Rules.spriteScale()
                case BlastKind.PlayerBlast => Rules.cannonScale()
            };
            Sprite.draw(Sprites.forBlast(b#kind, b#ticksLeft), b#pos, scale)
        }, w#blasts)

    // -- the cabinet furniture --------------------------------------------------------

    def zeros(n: Int32): String =
        if (n <= 0) "" else "0" + zeros(n - 1)

    /// Left-pads a score with zeros, the way the cabinet displays it.
    pub def scoreText(value: Int32): String = {
        let digits = Int32.toString(value);
        zeros(4 - String.length(digits)) + digits
    }

    /// The HUD type size. Press Start 2P is a pixel font: whole multiples look best.
    pub def hudSize(): Float32 = 12.0f32

    pub def bannerSize(): Float32 = 24.0f32

    ///
    /// The width of a string, in pixels.
    ///
    /// Press Start 2P is monospaced with an advance equal to the em size, so this is exact
    /// and lets the HUD be laid out by character count rather than by numbers tuned against
    /// whatever font the platform happened to supply.
    ///
    pub def textWidth(s: String, size: Float32): Float32 =
        Int32.toFloat32(String.length(s)) * size

    /// The x that centres `s` in the field.
    pub def centredX(s: String, size: Float32): Float32 =
        (Rules.fieldWidth() - textWidth(s, size)) / 2.0f32

    /// The x that right-aligns `s` with its right edge `margin` from the field edge.
    pub def rightAlignedX(s: String, size: Float32, margin: Float32): Float32 =
        Rules.fieldWidth() - textWidth(s, size) - margin

    def drawHud(w: World): Unit \ Canvas = {
        Canvas.textSize(hudSize());
        let margin = 24.0f32;

        Canvas.fill(Palette.invaderCyan());
        Canvas.text("SCORE<1>", margin, 26.0f32);
        Canvas.fill(Palette.ink());
        Canvas.text("HI-SCORE", centredX("HI-SCORE", hudSize()), 26.0f32);
        Canvas.fill(Palette.sun());
        Canvas.text("SCORE<2>", rightAlignedX("SCORE<2>", hudSize(), margin), 26.0f32);

        // Each value sits centred under its own label.
        let under = (label, value) -> {
            let labelWidth = textWidth(label, hudSize());
            let valueWidth = textWidth(value, hudSize());
            (labelWidth - valueWidth) / 2.0f32
        };
        Canvas.fill(Palette.ink());
        let own = scoreText(w#score);
        let best = scoreText(w#hiScore);
        let other = scoreText(0);
        Canvas.text(own, margin + under("SCORE<1>", own), 48.0f32);
        Canvas.text(best, centredX("HI-SCORE", hudSize()) + under("HI-SCORE", best), 48.0f32);
        Canvas.text(other, rightAlignedX("SCORE<2>", hudSize(), margin) + under("SCORE<2>", other), 48.0f32)
    }

    ///
    /// The green line the cannon stands on, the remaining lives, and the credit counter.
    ///
    def drawCabinet(w: World): Unit \ Canvas = {
        Canvas.fill(Palette.ground());
        Canvas.rect(0.0f32, Rules.groundY(), Rules.fieldWidth(), 2.0f32);

        Canvas.fill(Palette.ink());
        Canvas.textSize(hudSize());
        Canvas.text("${w#lives}", 24.0f32, Rules.fieldHeight() - 8.0f32);

        // One small cannon per life still in reserve, so the count is readable at a glance.
        Canvas.fill(Palette.cannonGreen());
        drawSpareLives(Sprites.cannon(), w#lives - 1, 0);

        Canvas.fill(Palette.ink());
        let level = "LEVEL ${w#level}";
        Canvas.text(level, centredX(level, hudSize()), Rules.fieldHeight() - 8.0f32);
        Canvas.text("CREDIT 01", rightAlignedX("CREDIT 01", hudSize(), 24.0f32), Rules.fieldHeight() - 8.0f32)
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
        case Phase.Cleared => {
            let message = "LEVEL ${w#level + 1}";
            Canvas.fill(Palette.invaderCyan());
            Canvas.textSize(bannerSize());
            Canvas.text(message, centredX(message, bannerSize()), Rules.fieldHeight() / 2.0f32)
        }
        case Phase.Lost => banner("GAME OVER")
    }

    def banner(message: String): Unit \ Canvas = {
        let hint = "PRESS ENTER TO PLAY AGAIN";
        Canvas.fill(Palette.ink());
        Canvas.textSize(bannerSize());
        Canvas.text(message, centredX(message, bannerSize()), Rules.fieldHeight() / 2.0f32);
        Canvas.fill(Palette.invaderCyan());
        Canvas.textSize(hudSize());
        Canvas.text(hint, centredX(hint, hudSize()), Rules.fieldHeight() / 2.0f32 + 36.0f32)
    }

    ///
    /// Describes one frame.
    ///
    pub def render(w: World): Unit \ Canvas = {
        Canvas.clear(Palette.background());
        drawMystery(w);
        drawInvaders(w);
        drawBunkers(w);
        drawShots(w);
        drawPlayer(w);
        drawShield(w);
        drawBlasts(w);
        drawHud(w);
        drawCabinet(w);
        drawEndMessage(w)
    }

}
