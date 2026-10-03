# Component licenses and release status

This repository combines original Godot integration work with translated and vendored upstream work. **The whole bundle is not MIT-licensed.** The root MIT grant is limited to the original integration, demo, documentation and test harness code. It does not grant rights to upstream material.

## Material requiring clarification before public redistribution

The checked-out [NTSCRT](https://github.com/finnmckenty/NTSCRT) revision `644e01b8d0285bdd5143c42491256ce0a4d315ff` contains no top-level LICENSE, COPYING or NOTICE file. Its original authors retain copyright. A publicly readable repository is not recorded here as a redistribution grant.

The extraction retains locally ported NTSCRT receiver/downscale/sizing code and selected preset animation data so the standalone local port is complete. Do not treat their presence here as license clearance. Resolve the upstream terms for these components before publishing this complete bundle:

- `addons/ntscrt/internal/ntscrt_receiver_gpu.gd` and `shaders/ntscrt_receiver_gpu/`.
- `addons/ntscrt/internal/ntscrt_downscale_gpu.gd` and `shaders/ntscrt_downscale_gpu/`.
- `addons/ntscrt/internal/ntscrt_preview_scaler.gd`.
- Receiver metadata in `addons/ntscrt/third_party/receiver_schema.json`.
- The selected NTSCRT timeline data in `addons/ntscrt/third_party/glitch_sequences.json` and associated upstream-derived sampling behavior.

This is a record of the pinned local source, not a claim about permission that may have been granted elsewhere. No repository was published by this extraction.

## ntsc-rs

The compute translation derives from [ntsc-rs](https://github.com/ntsc-rs/ntsc-rs) revision `add90f5bf1bf7e3c573e4e945a16f44a82941b51`. Its MIT, ISC and Apache-2.0 texts are retained in `addons/ntscrt/third_party/ntsc-rs-LICENSE-*.txt`; the port's original `LICENSE.ntsc-rs.txt` is also retained. The compute source records its upstream files and modifications. Upstream noise algorithms include Ralith/Clatter-derived work as noted in that source.

This covers the upstream-derived algorithm and metadata, not an assertion that every file in this combined repository has the same license.

## CRT shaders and lookup images

`addons/ntscrt/third_party/slang/upstream/` is the exact dependency set from [libretro/slang-shaders](https://github.com/libretro/slang-shaders) revision `cb01f2f238700eed7ec1c859be1737a9fbcdcb7c`. File-level notices remain intact, including GPL declarations, permissive/public-domain notices and Royale's full GPL text. Authors include EasyMode, Hyllian, TroggleMonkey and the wider CRT shader community.

The generated `slang/presets.json` contains translated/preprocessed shader code and is subject to the source shaders' terms. It does not become MIT by being JSON or being executed by Godot. Original source files, includes, presets, lookup images and SHA-256 provenance are bundled alongside it. Preserve them and their applicable terms when redistributing.

## Original integration

The new `effect.gd`, `profile.gd`, plugin/export adapter, demo, and original test harness work are covered by the root MIT grant. The original Godot RenderingDevice host/runtime plumbing extracted from Liminal retains the same grant for its original portions. Upstream-derived algorithms and data remain subject to the component notes above. No Swift application or librashader binary is bundled.
