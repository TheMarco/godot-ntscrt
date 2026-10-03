#!/usr/bin/env python3
"""Extract selected original NTSC animation tracks; retain timing and provenance."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]) if len(sys.argv) > 1 else root.parent / "NTSCRT"
tracks = ["bandwidth_scale", "composite_preemphasis", "vertical_scale",
          "vhs_chroma_loss", "vhs_edge_wave", "vhs_edge_wave_enabled",
          "vhs_edge_wave_frequency", "vhs_edge_wave_speed", "vhs_edge_wave_detail"]
result = {"source_revision": "644e01b8d0285bdd5143c42491256ce0a4d315ff", "sequences": {}}
for identifier, filename in [("glitch_pop", "Glitch pop.json"), ("two_blips", "Two blips loop.json")]:
    raw = (source / "presets" / filename).read_bytes()
    original = json.loads(raw)
    keys = original["timeline"]["keys"]
    varying = [key for key in tracks if len({json.dumps(k["ntsc"].get(key)) for k in keys}) > 1]
    result["sequences"][identifier] = {
        "source": "presets/" + filename,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "original_duration": original["timeline"]["duration"],
        "keys": [{"t": k["t"], "easing": k["easing"],
                  "ntsc": {key: k["ntsc"][key] for key in varying}} for k in keys],
    }
destination = root / "addons/ntscrt/third_party/glitch_sequences.json"
destination.write_text(json.dumps(result, indent=2) + "\n")
print(f"Imported {len(result['sequences'])} original animations into {destination}")
