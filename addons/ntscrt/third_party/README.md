# NTSCRT rendering dependencies

`slang/upstream` contains the exact files needed by NTSCRT's seven CRT presets
from [libretro/slang-shaders](https://github.com/libretro/slang-shaders) revision
`cb01f2f238700eed7ec1c859be1737a9fbcdcb7c`. Original files are unmodified; their
license and attribution headers are retained, including GPL notices and Royale's
`LICENSE.TXT`. These files have their own upstream licenses.

`slang/presets.json` records SHA-256 hashes for all original files and contains
generated GLSL plus uniform-layout metadata. Regenerate it with:

```sh
python3 tools/import_slang.py /path/to/the/pinned/slang-shaders
```

The importer expands includes, resolves preprocessor branches, separates vertex
and fragment stages, and relocates push constants to a free std140 uniform-buffer
binding. The shader algorithms, parameter defaults, preset scales, lookup images,
framebuffer formats, feedback references, and sampling options come from upstream.

Godot executes the generated GLSL through its RenderingDevice. The application
supplies textures, parameters, frame count, mipmaps, and previous-pass feedback;
it does not load the Swift application or librashader.

The ntsc-rs compute translation is based on revision
`add90f5bf1bf7e3c573e4e945a16f44a82941b51`; its Apache-2.0 license is also
packaged here as `LICENSE.ntsc-rs.txt`. The receiver/downscaler/sizing ports
come from sibling NTSCRT revision `644e01b8d0285bdd5143c42491256ce0a4d315ff`.
The original NTSCRT authors retain copyright. Canonical control descriptors
are shipped beside this file so exported games do not depend on development tools.

`glitch_sequences.json` contains selected varying NTSC tracks from NTSCRT's
`presets/Glitch pop.json` and `presets/Two blips loop.json` at that revision.
It retains original key times, easing and source-file SHA-256 hashes. Regenerate
with `python3 tools/import_glitch_presets.py /path/to/NTSCRT`.
The game adapts their durations and caps values for readability and performance;
the remaining preset settings and the original editor are not imported.

The extracted repository records unresolved NTSCRT licensing in root LICENSING.md. No new license is granted for upstream material by this extraction.
