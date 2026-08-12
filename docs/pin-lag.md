# Pin lag

A field log for one question: **does pinning an exact Flix compiler cost more than it
saves?**

`flix.toml` pins a compiler and `.flixw/lock.toml` binds it to a digest, so this
project no longer tracks Flix head. That is a deliberate trade — reproducibility bought
with upgrade pressure — and the Flix Community Build exists precisely because pinning
weakens the migration signal a pre-1.0 language depends on. The trade cannot be settled by
argument, only by keeping score.

So: one row per Flix release, added when the release appears, whether or not this project
moves to it. The column that matters is **lag** — how long this project sat on an older
compiler — and the one that decides the experiment is **what broke**.

## How to add a row

When a Flix release appears:

```console
./flixw pin <version>     # rewrites [package].flix and the lock, re-verifies the digest
./flixw check
./flixw test
```

Then record the outcome below, including the boring ones. A run of "nothing broke" is the
result that would retire this wrapper, and it only counts if it was written down at the
time rather than remembered afterwards.

If the upgrade is deferred, say why in **What broke** and leave **Adopted** empty — a
deferral is the expensive case this log exists to measure.

## Log

| Release | Released | Adopted | Lag | What broke |
|---|---|---|---|---|
| 0.75.1 | 2026-07-09 | 2026-08-06 | — | The project's first pin. It did not exist when 0.75.1 shipped, so this is a start date, not a lag. |
| 0.75.2 | 2026-08-07 | 2026-08-07 | **0 days** | Nothing. Adopted on release day, by hand, before the wrapper existed — this is the pre-wrapper baseline the experiment has to beat, or at least not lose to. `./flixw` took over the same pin on 2026-08-11 and re-verified it against `a2697d87…`; 441 tests green, no source change. |

## Notes

- **The baseline is same-day.** Before any of this, 0.75.2 was adopted the day it shipped.
  If lag grows now that a digest has to be repinned to move, that growth *is* the cost of
  pinning, and it is the number this log exists to expose rather than excuse.
- **Lag is measured from release to adoption**, not from release to *noticing*. A release
  nobody looked at for three weeks lagged three weeks.
- **Record the failure, not the fix.** "`Sketch.start` lost its `hz` parameter" is
  evidence; "upgraded, fixed some things" is not.
- **A pin that could not be repaired is the headline result.** If `./flixw pin` succeeds but
  `check` fails and the change is not worth making, that is the migration debt this
  experiment predicted, and it belongs in the table in full.
- The wrapper itself is a variable too. If a Flix release breaks the *wrapper* rather than
  the project — a changed release-asset name, a `--help` format the verb capture cannot
  parse — record it here as well and open an issue against `wstein/flixw`; that is the
  evidence that repository is missing.
