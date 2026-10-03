# Extraction validation

Verified on 2026-10-03 with Godot 4.7.2, Forward+/Metal, on an Apple M3 Max.
Commands are in [tests/README.md](../tests/README.md).

- Standalone demo: tape/CRT independence, receiver, authored and procedural
  faults, pause, viewport resizing and renderer cleanup passed.
- All seven original CRT chains compiled and produced nonblank GPU output
  (38 passes across the seven models).
- Profile independence and resource persistence passed. The canonical controls
  check passed for all 79 descriptors, including UI events and silent refresh.
- The sizing check passed all 444 cases. Asset/export checks passed all 82 cases.
- All 71 bundled original CRT files matched their pinned SHA-256 hashes.
  Runtime references stayed inside the addon; no game singleton was required.
- The scrolling-static regression passed in both linear and nonlinear colour
  paths: maximum translated-frame correlation was 0.027233.
- An exported PCK ran from outside the source checkout. Its asset check and
  native demo smoke check passed, with all five compute shaders loaded through
  Godot's imported resources rather than raw GLSL files.
- The rendered TV test-card demo was inspected: the chart is filtered and the
  separate control panel remains crisp.

Headless macOS checks emitted a system-certificate lookup warning; their
explicit PASS results contained no script errors. Native rendering and the
exported native smoke check completed without that warning.

Windows, Linux, Vulkan, mobile devices and low-end hardware remain untested.
These checks establish extraction integrity on the tested configuration, not
hardware-wide frame-rate guarantees or pixel identity with upstream NTSCRT.
