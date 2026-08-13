# Working from the metric report

`metric.md` measures the shape of the code: how long a function is, how deeply it nests, how
many arguments it takes, how many tokens sit on one line, whether a public definition is
documented. Its work plan lists what is over a limit, worst first.

Every limit in it is a proxy. The thing actually wanted is code a person can read; the number
is a way of noticing where that has probably gone wrong. **That distinction is the whole of
this document**, because a proxy can be satisfied without delivering the thing, and this
project has done exactly that more than once.

What follows is what those attempts cost, and the rules that came out of them.

---

## The rule that outranks every other

**A change that satisfies a metric while changing behaviour is not a style change. It is a
bug with a tidy diff.**

On 2026-08-12 a formatting pass over nineteen files dropped `- w#playerX` from `Demo.intent`,
turning the bot's `goal` from a delta into an absolute coordinate. The bot walked to the wall
and stayed there. Ten tests failed, the demo averaged level 1.0 against 4.6, and a bot that
never misses cleared level one on none of six seeds.

Nothing about wrapping a line requires touching an expression. If the diff of a style change
contains anything but whitespace, line breaks, new bindings for existing subexpressions, and
comments, look again.

So, before committing anything the report asked for:

- `./flixw check` and `./flixw test` — both, every time.
- `bin/bench --defaults` if anything under `src/Invaders/` or `src/Bench.flix` moved. It
  prints per-seed levels, scores, deaths, kills and ticks; they must match seed for seed.
- A windowed run (`FLIX_SKETCH_MAX_FRAMES=120 bin/play --force`) if `Runtime/` moved. The
  headless suite never opens a window and never touches the sound card.
- If the change is to something whose *output* is not compared by any test -- `Game.digest`
  is the example, since the replay tests only compare digests to each other -- print the
  output before and after and diff it.

---

## What not to do

### Do not delete the reasoning

Splitting a function moves its code but not its comments. Three separate passes here left the
"why" behind: `Sketch.start`'s doc comment was deleted outright, leaving the runtime's only
public entry point undocumented; the two-player handover rationale, the `settings()`-only
rule, the `exitActual` override and the context-classloader note all vanished; and
`Animation.resolvePair`'s elastic-collision derivation ended up attached to a type alias.

A doc comment belongs to the function it describes. When that function splits in two, so does
its documentation. A comment that has drifted onto the declaration below it is worse than no
comment, because it now describes the wrong thing.

Watch for the specific failure of a doc block whose function was extracted from under it: the
prose stays, the `def` it explained is now somewhere else, and the report will duly list the
moved function as undocumented. Four of five "undocumented public function" findings in one
report were this, not genuinely undocumented code.

### Do not disable a test to make a number go down

The same pass replaced the body of `test/TestScoresFile.flix` with a stub reading *tests
temporarily disabled due to pending fixes*. That is the one test allowed to name `Fs.`, and
CI greps it for `withInMemoryFS`; `Fs.FileRead` and `Fs.FileWrite` carry `@DefaultHandler`
and the default is the real disk. Disabling it is how a suite quietly starts writing to the
machine that runs it.

If a test is in the way of a metric, the metric is wrong about that test.

### Do not add indirection that only the metric can see

`Sketch.start` was over no limit at all when a pass wrapped its `PApplet` subclass in a
zero-argument local called on the very next line. It shortened the function by a line count
and cost every reader a hop. The report noticed too, and listed the new local as a smell of
its own.

Extract a function when it has a name worth having -- `formationTooThin`, `meetBomb`,
`readKeyboard`. A helper called once, immediately, named after its position rather than its
job, is a worse function *and* a worse number.

### Do not flatten what the language needs

Two Flix specifics have broken this codebase during metric work:

- A record update splits as `{ a = 1,\n  b = 2 | w }`. Putting the `| w` on its own line
  after the closing brace is a parse error, and a parse error inside one function makes the
  compiler report every *other* function as an unused definition. The file that is broken is
  the one it says least about.
- A type alias that shortens a signature needs kind annotations on its parameters:
  `type alias CmdCollector[a: Type, b: Type, ef: Eff]`. Without them the effect parameter is
  inferred as a type and the error arrives three files away.

`run`, `spawn`, `from`, `where`, `into` and `Static` are reserved. `where` in particular is
an inviting name for the binding you just extracted from a long line, and the error it
produces points at the token after it.

### Do not lose the shape of a table

`Canvas.paint`'s match arms and the `Canvas` handler operations were aligned columns. Where
an arm has to be split, split it the same way as its neighbours rather than leaving one
ragged line in an otherwise square block. Alignment is not decoration in a dispatch table --
it is what lets the eye check that every case is handled the same way.

---

## What to do instead

The limits are usually pointing at something real. The fix that satisfies the number *and*
the intent is nearly always one of:

| the finding | what it usually means |
| --- | --- |
| `density` (tokens on a line) | an expression is doing several things; name the parts |
| `lineLength` | the same, or a string that should be built from pieces |
| `parameters` | the arguments travel together and want a record — `Loop`, `ShotPass`, `BenchState` |
| `nesting` | a guard clause, or a `match` on a tuple, is hiding inside an `if` ladder |
| `cognitive` | a repeated condition is a missing named predicate |
| `lines` | the function is a pipeline; each stage probably has a name |
| undocumented public | usually a doc comment that slid off during an earlier extraction |
| module with no dependents | often an entry point (`Still`, `Animation`) — it wants a test, not deletion |

`Game.digest` is the worked example. Its header line scored 32 by packing five interpolations
into one string. Breaking the line would have satisfied the tool; naming the repeated shape --
`group` for one `|label(field,field,...)` entry, `eachOf`/`eachIn` for rendering a whole
collection -- turned five near-identical folds into five one-line calls and left every line
comfortably under the limit as a side effect.

---

## The limits are not the standard

A clean report means nothing was measured as unusual. It does not mean the code is good, and
a finding does not mean the code is bad.

`Bunkers.absorb` keeps a hand-written recursion because it stops at the first bunker a shot
touches and a fold in a strict language cannot stop early. `Bench.one` keeps one because it
stops when the game ends rather than when a range does. `Sketch.park` keeps one because it is
waiting on another thread. Each says so in a comment. If a future limit flags them, the
comment is the answer, and the right response is to argue with the limit.

Equally, `docs/ARCHITECTURE.md` records several changes that were measured and **rejected** --
they made a number better and the game worse. That file, and this one, are the memory the
report does not have.
