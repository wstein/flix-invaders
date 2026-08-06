<!-- flix-init: generated for Flix 0.75.1+fork.wstein.260802.2.104.g6ec07eccd.dirty. Rewritten by 'flix init --refresh'; delete this line to keep your own edits. -->

# Working on this project

A Flix project. The Flix version it targets is pinned in `flix.toml`.

## Commands

- `flix check` — type-check without generating code; the fast feedback loop
- `flix test` — run every `@Test` function under `test/`
- `flix run` — run `main`
- `flix build` — compile to `build/class`
- `flix doc` — write API documentation for the standard library and this project to `build/doc/`

## Layout

- `src/` — sources; `src/Main.flix` holds `main`
- `test/` — `@Test` functions
- `flix.toml` — package metadata, the Flix version, and dependencies
- `build/`, `artifact/`, `lib/` — generated; do not edit and do not commit

## Writing Flix

Your training data is probably older than this compiler. Read
https://doc.flix.dev/for-llms.html before writing Flix: it lists what changed. For the
standard library use https://api.flix.dev, or run `flix doc` and read `build/doc/`, which
matches this project's compiler exactly.

The mistakes that show up most often:

- `def main(): Unit \ IO = ...` — arguments come from `Env.getArgs()`, not from parameters
- effects are written with `\`, not `&`
- effect operations are called like ordinary functions; there is no `do` keyword
- handlers are `run { ... } with handler E { ... }`; chain them rather than nesting `run`
- annotations are uppercase: `@Test`, `@Lazy`, `@Parallel`, `@MustUse`
- Java types need a top-level `import`, and all Java interop carries `IO`

Prefer effects and handlers to callbacks or hand-written CPS, and standard library effects
to Java interop.
