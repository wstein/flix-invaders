///
/// The shared palette.
///
/// Every colour here is checked by `test/TestContrast.flix` against the background it is
/// drawn on, using the WCAG 2.1 contrast ratio: at least 4.5 for text, at least 3.0 for
/// shapes. Changing a colour without keeping those ratios fails the build, which is the
/// point -- a sketch that looks fine on one display should stay legible on another.
///
mod Palette {

    /// The background every sketch clears to. Near-black, like an arcade cabinet.
    pub def background(): Color = Color.Rgb(8, 8, 14)

    /// Primary text.
    pub def ink(): Color = Color.Rgb(232, 236, 245)

    /// Secondary text and captions.
    pub def dim(): Color = Color.Rgb(158, 166, 198)

    /// Large blocks drawn against the background, such as the skyline.
    pub def silhouette(): Color = Color.Rgb(98, 104, 136)

    /// Yellow accent for the sun and banners.
    pub def sun(): Color = Color.Rgb(245, 205, 110)

    /// Bright green for top invader row.
    pub def invaderGreen(): Color = Color.Rgb(92, 240, 116)

    /// Cyan for middle invader row.
    pub def invaderCyan(): Color = Color.Rgb(96, 226, 240)

    /// Magenta for bottom invader row.
    pub def invaderMagenta(): Color = Color.Rgb(236, 118, 224)

    /// Green for the player cannon.
    pub def cannonGreen(): Color = Color.Rgb(92, 240, 116)

    /// Green for ground line.
    pub def ground(): Color = Color.Rgb(60, 200, 90)

    /// White for player and invader shots.
    pub def shot(): Color = Color.Rgb(240, 240, 240)

    /// Coral red accent color.
    pub def coral(): Color = Color.Rgb(240, 122, 112)

    /// Soft mint green accent color.
    pub def mint(): Color = Color.Rgb(126, 217, 168)

    /// Azure blue accent color.
    pub def azure(): Color = Color.Rgb(130, 182, 246)

    ///
    /// Colours used for text on `background`. Must reach a 4.5 contrast ratio.
    ///
    pub def textColors(): List[Color] = ink() :: dim() :: Nil

    ///
    /// Colours used for shapes on `background`. Must reach a 3.0 contrast ratio.
    ///
    pub def shapeColors(): List[Color] =
        silhouette() :: sun() :: coral() :: mint() :: azure()
            :: invaderGreen() :: invaderCyan() :: invaderMagenta()
            :: cannonGreen() :: ground() :: shot() :: Nil

}
