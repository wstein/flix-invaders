///
/// Colours and draw commands.
///
/// Plain immutable data shared by the `Canvas` effect and its handlers. Nothing in this
/// file knows that a window exists, which is what lets tests assert on what *would* be
/// drawn without opening one.
///
pub enum Color with Eq, ToString {
    case Rgb(Int32, Int32, Int32)
}

mod Color {

    /// Clamps a channel to 0..255.
    def channel(v: Int32): Int32 =
        if (v < 0) 0 else if (v > 255) 255 else v

    /// The red channel, clamped to 0..255.
    pub def redOf(c: Color): Int32 = match c {
        case Color.Rgb(r, _, _) => channel(r)
    }

    /// The green channel, clamped to 0..255.
    pub def greenOf(c: Color): Int32 = match c {
        case Color.Rgb(_, g, _) => channel(g)
    }

    /// The blue channel, clamped to 0..255.
    pub def blueOf(c: Color): Int32 = match c {
        case Color.Rgb(_, _, b) => channel(b)
    }

    pub def grey(v: Int32): Color = Color.Rgb(v, v, v)

    pub def black(): Color = Color.Rgb(0, 0, 0)
    pub def white(): Color = Color.Rgb(255, 255, 255)

    ///
    /// One channel converted from sRGB to linear light, per WCAG 2.1.
    ///
    def linearize(v: Int32): Float64 = {
        let s = Int32.toFloat64(channel(v)) / 255.0;
        if (s <= 0.03928) s / 12.92
        else Float64.pow(base = (s + 0.055) / 1.055, 2.4)
    }

    ///
    /// Relative luminance, from 0.0 (black) to 1.0 (white), per WCAG 2.1.
    ///
    pub def luminance(c: Color): Float64 =
        0.2126 * linearize(redOf(c))
            + 0.7152 * linearize(greenOf(c))
            + 0.0722 * linearize(blueOf(c))

    ///
    /// The WCAG 2.1 contrast ratio between two colours, from 1.0 to 21.0.
    ///
    /// Order does not matter. As a rule of thumb, body text needs at least 4.5 and shapes
    /// and large text need at least 3.0 to stay legible.
    ///
    pub def contrastRatio(a: Color, b: Color): Float64 = {
        let la = luminance(a);
        let lb = luminance(b);
        let lighter = if (la >= lb) la else lb;
        let darker = if (la >= lb) lb else la;
        (lighter + 0.05) / (darker + 0.05)
    }

}

///
/// A single drawing instruction.
///
/// `Canvas.runWithCollector` interprets the `Canvas` effect into a list of these, so rendering
/// can be tested as data.
///
pub enum DrawCmd with Eq, ToString {
    case Clear(Color)
    case Fill(Color)
    case FillAlpha(Color, Int32)
    case Rect(Float32, Float32, Float32, Float32)
    case Ellipse(Float32, Float32, Float32, Float32)
    case Text(String, Float32, Float32)
    case TextSize(Float32)
}
