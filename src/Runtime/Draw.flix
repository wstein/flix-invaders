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

    ///
    /// Packs to the `0xRRGGBB` integer form Processing expects.
    ///
    pub def toInt32(c: Color): Int32 = match c {
        case Color.Rgb(r, g, b) => (channel(r) * 65536) + (channel(g) * 256) + channel(b)
    }

    pub def grey(v: Int32): Color = Color.Rgb(v, v, v)

    pub def black(): Color = Color.Rgb(0, 0, 0)
    pub def white(): Color = Color.Rgb(255, 255, 255)

}

///
/// A single drawing instruction.
///
/// `Canvas.runCollecting` interprets the `Canvas` effect into a list of these, so rendering
/// can be tested as data.
///
pub enum DrawCmd with Eq, ToString {
    case Clear(Color)
    case Fill(Color)
    case Rect(Float32, Float32, Float32, Float32)
    case Ellipse(Float32, Float32, Float32, Float32)
    case Text(String, Float32, Float32)
    case TextSize(Float32)
}
