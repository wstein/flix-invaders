///
/// A pseudo-random number generator, as a value.
///
/// Randomness is deliberately *data* rather than an effect. A generator is threaded through
/// `step` like any other part of the world, which means a simulation that uses randomness is
/// still a pure function of its inputs. Replaying a recorded input script from the same seed
/// therefore produces a bit-identical result, with no handler to install and no shared
/// generator to reason about across threads.
///
/// This is a 64-bit linear congruential generator using the multiplier and increment from
/// Knuth's MMIX. It is not cryptographic and is not meant to be.
///
pub enum Rng with Eq, ToString {
    case Rng(Int64)
}

mod Rng {

    def multiplier(): Int64 = 6364136223846793005i64
    def increment(): Int64 = 1442695040888963407i64

    ///
    /// Creates a generator from `seed`.
    ///
    /// The state is advanced once so that adjacent seeds do not produce correlated first
    /// values, which is the usual failure mode of a bare LCG.
    ///
    pub def fromSeed(seed: Int64): Rng =
        advance(Rng.Rng(seed))

    /// Advances the state by one step. Int64 arithmetic wraps, which is what an LCG wants.
    def advance(r: Rng): Rng = match r {
        case Rng.Rng(state) => Rng.Rng(state * multiplier() + increment())
    }

    ///
    /// Returns the next 64-bit value and the advanced generator.
    ///
    pub def nextInt64(r: Rng): (Int64, Rng) = {
        let next = advance(r);
        match next {
            case Rng.Rng(state) => (state, next)
        }
    }

    ///
    /// Returns a non-negative 64-bit value and the advanced generator.
    ///
    /// Negatives are folded rather than negated, because negating `Int64.minValue` would
    /// overflow back to itself.
    ///
    pub def nextNonNegative(r: Rng): (Int64, Rng) = {
        let (value, next) = nextInt64(r);
        let folded = if (value < 0i64) -(value + 1i64) else value;
        (folded, next)
    }

    ///
    /// Returns a value in `0 ..< bound` and the advanced generator.
    ///
    /// A `bound` of zero or less yields `0`, so callers never have to guard.
    ///
    pub def nextInt32Below(bound: Int32, r: Rng): (Int32, Rng) =
        if (bound <= 0) (0, advance(r))
        else {
            let (value, next) = nextNonNegative(r);
            let scaled = Int64.remainder(value, Int32.toInt64(bound));
            // `scaled` is already in 0 ..< bound, so it always fits; the default is unreachable.
            (Option.getWithDefault(0, Int64.tryToInt32(scaled)), next)
        }

    ///
    /// Returns `true` with probability `1 / oneIn`, and the advanced generator.
    ///
    pub def chance(oneIn: Int32, r: Rng): (Bool, Rng) = {
        let (value, next) = nextInt32Below(oneIn, r);
        (value == 0, next)
    }

}
