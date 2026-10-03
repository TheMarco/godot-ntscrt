# Demo media

`tv-test-card.png` is the unmodified 330×248 TV test-card image supplied by the repository owner during extraction on 2026-10-03. No original author, source URL or license accompanied the upload; no additional rights are asserted here. Establish its provenance before including it in a public release, or remove the supplied-image example and use the original generated chart instead.

The addon itself does not depend on this image. The second demo mode is drawn procedurally by `demo/test_card.gd`.


## Original moving samples

`hallway.ogv` and `security.ogv` are original, generated 3D footage distributed
under this project's MIT license. They use only procedural geometry, materials,
lighting and Godot's default font; they contain no Liminal assets or third-party
footage. Each silent loop is 8 seconds at 720×540, 30 fps, Ogg Theora. No NTSCRT
filters are baked in. Together they occupy about 4 MB.

The hallway has a moving camera, bright fixtures, colored shelving and fine
edges. The security view uses a fixed camera, deep shadows and a moving cart.
These are synthetic reference scenes, not recordings from real vintage cameras.
Use **Open .ogv…** in the demo to evaluate your own camera footage instead.

To rebuild, run from the repository root with a native Godot renderer:

```sh
godot --path . --script tools/render_sample_footage.gd -- --output-dir=/tmp/ntscrt-frames
ffmpeg -framerate 30 -i /tmp/ntscrt-frames/hallway/%04d.png -c:v libtheora -q:v 9 -pix_fmt yuv420p -an demo/assets/hallway.ogv
ffmpeg -framerate 30 -i /tmp/ntscrt-frames/security/%04d.png -c:v libtheora -q:v 9 -pix_fmt yuv420p -an demo/assets/security.ogv
```

The optional rebuild requires an FFmpeg build with the `libtheora` encoder.
Playing the included clips requires only Godot. The scene and deterministic
camera path are in `demo/sample_room.gd`; the renderer also accepts `--preview`
to produce one frame per source.

## Supplied abandoned-mall footage

`abandoned-mall.ogv` is the test clip supplied by the repository owner on
2026-10-03, converted from
`dreamina-2026-10-03-6565-footage walking through a abandoned mall....mp4`.
It retains the source's 1280×720 resolution, 60 fps and audio, for approximately
30 seconds of looping playback. No additional video effects are baked in by
this conversion. It is separate from the MIT procedural samples above; this
note records its supplied provenance and does not assert additional media rights.

Convert the supplied MP4 with an FFmpeg build containing `libtheora` and `libvorbis`:

```sh
ffmpeg -i 'dreamina-2026-10-03-6565-footage walking through a abandoned mall....mp4' -c:v libtheora -q:v 7 -pix_fmt yuv420p -c:a libvorbis -q:a 4 demo/assets/abandoned-mall.ogv
```

Only the converted OGV is included in the demo; the runtime addon has no dependency
on it. Select **Abandoned mall walkthrough** under **Preview footage**. Pause,
replay, A/B comparison and preset source capture work the same as for the other clips.
