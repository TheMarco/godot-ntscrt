#!/usr/bin/env python3
"""Check runtime isolation and byte-for-byte upstream CRT provenance."""
import hashlib
import json
import re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
addon=root/'addons/ntscrt'
errors=[]
for path in addon.rglob('*'):
    if path.suffix not in ('.gd','.gdshader','.glsl'): continue
    text=path.read_text()
    for symbol in ('GameSettings','GraphicsQuality','PostProcessController','VhsOsd','GameInput'):
        if re.search(r'\b'+symbol+r'\b',text): errors.append(f'{path.relative_to(root)}: game dependency {symbol}')
    for target in re.findall(r'"(res://[^"\n]+)"',text):
        if not target.startswith('res://addons/ntscrt/'): errors.append(f'Outside addon: {target}')
        elif not (root/target.removeprefix('res://')).exists(): errors.append(f'Missing dependency: {target}')
manifest=json.loads((addon/'third_party/slang/presets.json').read_text())
for relative,expected in manifest['files'].items():
    path=addon/'third_party/slang/upstream'/relative
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
        errors.append(f'Upstream hash mismatch: {relative}')
assert len(manifest['presets'])==7
for error in errors: print(error)
print(f'PORTABILITY {"FAIL" if errors else "PASS"}: isolated addon, {len(manifest["files"])} original CRT files, seven models')
raise SystemExit(bool(errors))
