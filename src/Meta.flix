///
/// What this build calls itself.
///
/// One string, and the only place the game states its own version. It is asserted against
/// `flix.toml` on every CI run and against the git tag on every release, because three places
/// naming a version is three places to disagree -- `flix.toml` had drifted three releases
/// behind the tags before this existed, and nothing noticed.
///
mod Meta {

    pub def version(): String = "0.1.6"

    /// The version as it appears on screen.
    pub def label(): String = "v${version()}"

}
