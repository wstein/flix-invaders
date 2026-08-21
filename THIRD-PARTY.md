# Third-party software

The game itself links against nothing but the JDK: it draws through Swing and Java2D and
makes its noises through `javax.sound.sampled`. The only third-party artifact it carries is
a font, and the only other one it needs is the compiler that builds it.

## Press Start 2P

- **File:** `assets/PressStart2P-Regular.ttf` (118 204 bytes)
- **sha256:** `034c77f1f05ec89421e4a63f0e3a4ca1ecf852cc6d2bf611f126f275728e017d`
- **Source:** https://github.com/google/fonts/tree/main/ofl/pressstart2p
- **License:** SIL Open Font License 1.1
  (full text: [licenses/OFL-1.1.txt](licenses/OFL-1.1.txt))

Copyright 2012 The Press Start 2P Project Authors (cody@zone38.net),
with Reserved Font Name "Press Start 2P".

Vendored unmodified. The OFL reserves the name: a **modified** copy of this font may not be
distributed under the name "Press Start 2P". This project does not modify it, so the
requirement is met by shipping the licence text alongside it and leaving the file untouched.
The font is loaded at runtime from a file path and is not embedded in any build artifact.

## Flix compiler

The Flix compiler (`./flixw` downloads `flix.jar` into a digest-addressed user cache) is
Apache-2.0 licensed and is a **build tool** — it is not redistributed as part of this
project. See https://github.com/flix/flix.
