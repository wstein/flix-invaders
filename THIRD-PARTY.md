# Third-party software

## Processing Core

- **Artifact:** `org.processing:core:4.5.6` (`core-4.5.6.jar`)
- **sha1:** `e51ed348c657dd24acfe77106563b472d0db04a8`
- **Source:** https://repo1.maven.org/maven2/org/processing/core/4.5.6/core-4.5.6.jar
- **Project:** https://processing.org — https://github.com/processing/processing4
- **License:** GNU Lesser General Public License, version 2.1
  (full text: [licenses/LGPL-2.1.txt](licenses/LGPL-2.1.txt))

Copyright (c) 2012-22 The Processing Foundation
Copyright (c) 2004-12 Ben Fry and Casey Reas
Copyright (c) 2001-04 Massachusetts Institute of Technology

### How this project uses it

Processing Core is used **unmodified**, as a **separate jar**, **dynamically linked at
runtime**, and is **replaceable by the user**. It is declared as a pinned
`[jar-dependencies]` entry in `flix.toml`, fetched from Maven Central at build time into
`lib/external/`, and never vendored into this repository or altered in any way. Replacing
`lib/external/processing-core.jar` with your own build of Processing Core is sufficient to
run this project against a modified library.

That arrangement is what satisfies LGPL-2.1 § 6 for this project.

### What is deliberately *not* used

- **No Processing documentation, reference prose, JavaDoc text, tutorials, or examples**
  have been copied into this repository. Processing's reference material is licensed
  CC-BY-NC-SA-4.0 (non-commercial), and it is embedded in the same `.java` source files as
  the LGPL-licensed code — so copying a method's JavaDoc along with its signature would
  import a *stricter*, non-commercial obligation. Nothing here is derived from it.
- **No PDE source.** Everything outside Processing's `core` module — the `app` and `java`
  modules, i.e. the Processing Development Environment — is GPL-2.0 and is not used,
  copied, or linked.
- **No JOGL / JogAmp.** This project uses only the `JAVA2D` renderer, which is pure
  AWT/Java2D. Verified with `-verbose:class`: no `com.jogamp` class is ever loaded.

### A note on distribution

`flix build-fatjar` would sweep `processing-core.jar` into a single shaded artifact. **Do
not use it for releases.** Shading converts dynamic linking into static linking and triggers
LGPL-2.1 § 6's relinking obligation, and it also strips `module-info.class` and signatures —
so the result would be a *modified* library distributed as if unmodified.

Distribute instead as this repository is meant to be run: the project's own classes plus the
untouched `processing-core.jar` alongside it.

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

The Flix compiler (`bin/flix` downloads `flix.jar` into the gitignored `.flix/`) is
Apache-2.0 licensed and is a **build tool** — it is not redistributed as part of this
project. See https://github.com/flix/flix.
