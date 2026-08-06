///
/// The shared palette.
///
/// Every colour here is checked by `test/TestContrast.flix` against the background it is
/// drawn on, using the WCAG 2.1 contrast ratio: at least 4.5 for text, at least 3.0 for
/// shapes. Changing a colour without keeping those ratios fails the build, which is the
/// point -- a sketch that looks fine on one display should stay legible on another.
///
mod Palette {

    /// The background every sketch clears to.
    pub def background(): Color = Color.Rgb(18, 20, 34)

    /// Primary text.
    pub def ink(): Color = Color.Rgb(232, 236, 245)

    /// Secondary text and captions.
    pub def dim(): Color = Color.Rgb(158, 166, 198)

    /// Large blocks drawn against the background, such as the skyline.
    pub def silhouette(): Color = Color.Rgb(98, 104, 136)

    pub def sun(): Color = Color.Rgb(245, 205, 110)
    pub def coral(): Color = Color.Rgb(240, 122, 112)
    pub def mint(): Color = Color.Rgb(126, 217, 168)
    pub def azure(): Color = Color.Rgb(130, 182, 246)

    ///
    /// Colours used for text on `background`. Must reach a 4.5 contrast ratio.
    ///
    pub def textColors(): List[Color] = ink() :: dim() :: Nil

    ///
    /// Colours used for shapes on `background`. Must reach a 3.0 contrast ratio.
    ///
    pub def shapeColors(): List[Color] =
        silhouette() :: sun() :: coral() :: mint() :: azure() :: Nil

}
