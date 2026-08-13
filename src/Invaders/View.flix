///
/// Drawing a world.
///
/// Uses only the `Canvas` effect, so `Canvas.runWithCollector` can record a frame as data and
/// the rendering tests need no display. Nothing here changes the world -- given the same
/// world, `render` always produces the same commands, which is why a replayed game renders
/// identically.
///
///
/// Who else is playing, from the point of view of one game.
///
/// The rules know nothing about a second player -- a `World` is one game. This is the little
/// bit of cabinet context the HUD needs in order to fill in the other score and show whose
/// turn it is.
///
///
/// What a single game needs to know about the machine around it.
///
/// `ownGameOver` is whether `View` should announce the *end of the game* itself. Standing
/// alone it must -- there is nobody else to do it, and Enter really does start a new game.
/// Inside the cabinet the session owns what happens next, so it draws its own and this is
/// false; otherwise the screen carries two GAME OVERs and an invitation to press a key that
/// the cabinet has already taken charge of.
///
/// It says nothing about the banner between waves. That one belongs to the game either way --
/// gating both on one flag is what made the level banner disappear from the cabinet and left
/// a silent three-second pause where it used to be.
///
pub type alias Cabinet = { player = Int32, players = Int32, otherScore = Int32, ownGameOver = Bool }

mod Cabinet {
    /// A single player with nobody to contrast against.
    pub def solo(): Cabinet = { player = 1, players = 1, otherScore = 0, ownGameOver = true }
}

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
        let drawBullet = b ->
            Sprite.draw(bullet, b, Rules.spriteScale());
        Canvas.fill(Palette.shot());
        List.forEach(drawBullet, w#bullets);
        // One fill for all three bombs: they are told apart by shape, not colour, so that a
        // player who cannot separate the palette's coral from its shot colour still can.
        Canvas.fill(Palette.coral());
        List.forEach(b -> {
            let pos = { x = b#x, y = b#y };
            Sprite.draw(Sprites.bombFor(b#kind), pos, Rules.spriteScale())
        }, w#bombs)
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
            let pos = { x = w#playerX, y = Rules.playerY() };
            Sprite.draw(Sprites.cannon(), pos, Rules.cannonScale())
        }

    def drawMystery(w: World): Unit \ Canvas = match w#mystery {
        case None => ()
        case Some(m) =>
            Canvas.fill(Palette.invaderMagenta());
            let mPos = { x = m#x, y = Rules.mysteryY() };
            let sx = Rules.mysteryScaleX();
            let sy = Rules.mysteryScaleY();
            Sprite.drawScaled(Sprites.mystery(), mPos, scaleX = sx, scaleY = sy)
    }

    /// How many blocks the dome is built from.
    def shieldSegments(): Int32 = 7

    /// How far the outer blocks sit below the crown, which is what makes it a dome.
    def shieldRise(): Float32 = 5.0f32

    /// How far the dome clears the cannon, and how far it overhangs at each side.
    def shieldLift(): Float32 = 12.0f32
    def shieldSpan(): Float32 = 7.0f32

    ///
    /// The shield, as a dome of energy blocks over the cannon.
    ///
    /// It was a plain bracket -- a bar and two posts -- which read as scenery rather than
    /// something switched on. The blocks now step down towards the edges so the silhouette
    /// curves over the cannon, and a bright pair travels along the arc off the world's own
    /// tick, so it looks powered rather than painted.
    ///
    /// The blocks butt together on purpose. An earlier version dimmed alternate blocks as the
    /// shield aged, meaning to show it thinning; on screen it read as a broken thing scattered
    /// above the cannon rather than a shield running low. A dome is either up or it is not.
    /// The warning it does need is the last couple of seconds of flashing, and that is enough.
    ///
    def drawShield(w: World): Unit \ Canvas = {
        let low = w#shield < Rules.shieldWarningTicks();
        let flash = Int32.remainder(w#shield / 8, 2) == 0;
        if (w#shield <= 0)
            ()
        else if (low and flash)
            ()
        else {
            let count = shieldSegments();
            let half = Rules.playerSize()#x / 2.0f32 + shieldSpan();
            let crown = Rules.playerY() - Rules.playerSize()#y / 2.0f32 - shieldLift();
            let block = (half * 2.0f32) / Int32.toFloat32(count);
            let middle = Int32.toFloat32(count - 1) / 2.0f32;
            List.forEach(i -> {
                let fromMiddle = (Int32.toFloat32(i) - middle) / middle;
                let dip = shieldRise() * fromMiddle * fromMiddle;
                let lit = Int32.remainder(i + w#tick / 3, count) < 2;
                Canvas.fillAlpha(Palette.invaderCyan(), if (lit) 255 else 170);
                Canvas.rect(w#playerX - half + Int32.toFloat32(i) * block, crown + dip, block, 4.0f32)
            }, List.range(0, count));
            // Posts at each end, so the dome is anchored to the cannon rather than floating.
            Canvas.fillAlpha(Palette.invaderCyan(), 170);
            Canvas.rect(w#playerX - half, crown + shieldRise(), 3.0f32, 9.0f32);
            Canvas.rect(w#playerX + half - 3.0f32, crown + shieldRise(), 3.0f32, 9.0f32)
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

    /// The font size used for large screen banners (e.g. GAME OVER, READY).
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

    ///
    /// The three headings across the top.
    ///
    /// The player whose turn it is gets the bright label; the other is dimmed. On a one-player
    /// game there is nobody to contrast with, so both stay bright.
    ///
    def drawHudLabels(c: Cabinet, margin: Float32): Unit \ Canvas = {
        let active = n ->
            c#players < 2 or c#player == n;
        let lit = n ->
            if (active(n)) Palette.ink() else Palette.dim();
        Canvas.fill(lit(1));
        Canvas.text("SCORE<1>", margin, 26.0f32);
        Canvas.fill(Palette.invaderCyan());
        let hiX = centredX("HI-SCORE", hudSize());
        Canvas.text("HI-SCORE", hiX, 26.0f32);
        Canvas.fill(lit(2));
        let p2X = rightAlignedX("SCORE<2>", hudSize(), margin);
        Canvas.text("SCORE<2>", p2X, 26.0f32)
    }

    ///
    /// The three numbers under those headings.
    ///
    /// Each value sits centred under its own label, which is what `under` works out. The
    /// active player's score comes from the live world; the other from the cabinet, because
    /// the world that earned it is put aside while it is not that player's turn.
    ///
    def drawHudScores(w: World, c: Cabinet, margin: Float32): Unit \ Canvas = {
        let under = (label, value) -> {
            let labelWidth = textWidth(label, hudSize());
            let valueWidth = textWidth(value, hudSize());
            (labelWidth - valueWidth) / 2.0f32
        };
        Canvas.fill(Palette.ink());
        let mine = scoreText(w#score);
        let theirs = scoreText(c#otherScore);
        let own = if (c#player == 1) mine else theirs;
        let other = if (c#player == 1) theirs else mine;
        let best = scoreText(w#hiScore);
        let p1X = margin + under("SCORE<1>", own);
        let hiX = centredX("HI-SCORE", hudSize()) + under("HI-SCORE", best);
        let p2X = rightAlignedX("SCORE<2>", hudSize(), margin) + under("SCORE<2>", other);
        Canvas.text(own, p1X, 48.0f32);
        Canvas.text(best, hiX, 48.0f32);
        Canvas.text(other, p2X, 48.0f32)
    }

    def drawHud(w: World, c: Cabinet): Unit \ Canvas = {
        Canvas.textSize(hudSize());
        let margin = 24.0f32;
        drawHudLabels(c, margin);
        drawHudScores(w, c, margin)
    }

    ///
    /// The green line the cannon stands on, the remaining lives, and the credit counter.
    ///
    def drawCabinet(w: World, c: Cabinet): Unit \ Canvas = {
        Canvas.fill(Palette.ground());
        Canvas.rect(0.0f32, Rules.groundY(), Rules.fieldWidth(), 2.0f32);

        let bottomY = Rules.fieldHeight() - 8.0f32;
        Canvas.fill(Palette.ink());
        Canvas.textSize(hudSize());
        Canvas.text("${w#lives}", 24.0f32, bottomY);

        // One small cannon per life still in reserve, so the count is readable at a glance.
        Canvas.fill(Palette.cannonGreen());
        drawSpareLives(Sprites.cannon(), w#lives - 1, 0);

        Canvas.fill(Palette.ink());
        let level = if (c#players < 2) "LEVEL ${w#level}" else "P${c#player}  LEVEL ${w#level}";
        Canvas.text(level, centredX(level, hudSize()), bottomY);
        let credX = rightAlignedX("CREDIT 01", hudSize(), 24.0f32);
        Canvas.text("CREDIT 01", credX, bottomY)
    }

    def drawSpareLives(cannon: Sprite, remaining: Int32, index: Int32): Unit \ Canvas =
        if (index >= remaining) ()
        else {
            let x = 52.0f32 + Int32.toFloat32(index) * 40.0f32;
            Sprite.draw(cannon, { x = x, y = Rules.fieldHeight() - 14.0f32 }, 2.0f32);
            drawSpareLives(cannon, remaining, index + 1)
        }

    ///
    /// Where the game's own banners sit.
    ///
    /// Above the middle of the field, not in it. The attract screen puts its title panel across
    /// the centre and plays the demo behind it, so a level banner at the midpoint lands inside
    /// the panel and neither can be read. `TestView` keeps the two apart.
    ///
    pub def bannerY(): Float32 = 128.0f32
    def bannerHintY(): Float32 = 156.0f32
    /// Vertical baseline coordinate for rendering the countdown digit.
    pub def countdownY(): Float32 = 170.0f32

    /// Font size used for rendering the ready countdown digits.
    pub def countdownSize(): Float32 = 30.0f32

    ///
    /// Which number the countdown is showing, given how much of the pause is left.
    ///
    /// One second each, taken from the rules rather than from a constant here, so the digits
    /// and the pause they divide up cannot drift apart.
    ///
    pub def countdown(pause: Int32): Int32 = {
        let each = Int32.max(1, Rules.ticksPerSecond());
        Int32.min(Rules.countdownSteps(), (pause + each - 1) / each)
    }

    def drawEndMessage(w: World, c: Cabinet): Unit \ Canvas = match w#phase {
        case Phase.Playing => ()
        case Phase.Cleared => {
            let message = "LEVEL ${w#level + 1}";
            Canvas.fill(Palette.invaderCyan());
            Canvas.textSize(bannerSize());
            Canvas.text(message, centredX(message, bannerSize()), bannerY());
            // Counting down turns dead air into a moment to get ready, and tells you the game
            // is waiting on purpose rather than thinking about something.
            let count = countdown(w#pause);
            if (count <= 0) ()
            else {
                let digit = "${count}";
                Canvas.fill(Palette.sun());
                Canvas.textSize(countdownSize());
                Canvas.text(digit, centredX(digit, countdownSize()), countdownY())
            }
        }
        // ...but who announces the end of the *game* depends on what is around it.
        case Phase.Lost => if (c#ownGameOver) banner("GAME OVER") else ()
    }

    def banner(message: String): Unit \ Canvas = {
        let hint = "PRESS ENTER TO PLAY AGAIN";
        Canvas.fill(Palette.ink());
        Canvas.textSize(bannerSize());
        Canvas.text(message, centredX(message, bannerSize()), bannerY());
        Canvas.fill(Palette.invaderCyan());
        Canvas.textSize(hudSize());
        Canvas.text(hint, centredX(hint, hudSize()), bannerHintY())
    }

    ///
    /// Describes one frame of a single game, with no cabinet around it.
    ///
    pub def render(w: World): Unit \ Canvas = renderWith(w, Cabinet.solo())

    ///
    /// Describes one frame, told who else is playing.
    ///
    pub def renderWith(w: World, c: Cabinet): Unit \ Canvas = {
        Canvas.clear(Palette.background());
        drawMystery(w);
        drawInvaders(w);
        drawBunkers(w);
        drawShots(w);
        drawPlayer(w);
        drawShield(w);
        drawBlasts(w);
        drawHud(w, c);
        drawCabinet(w, c);
        drawEndMessage(w, c)
    }

}
