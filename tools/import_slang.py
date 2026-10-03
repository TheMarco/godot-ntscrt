#!/usr/bin/env python3
"""Vendor the seven NTSCRT CRT presets from its pinned slang-shaders revision.

Original files remain byte-for-byte intact. The generated manifest splits the
combined GLSL stages and moves push constants to a free std140 binding,
avoiding device-specific push-constant size limits.
"""
import argparse
import hashlib
import json
import re
import shlex
import shutil
import subprocess
from pathlib import Path

REVISION = "cb01f2f238700eed7ec1c859be1737a9fbcdcb7c"
PRESETS = {
    "aperture": "crt/crt-aperture.slangp",
    "easymode": "crt/crt-easymode.slangp",
    "glow_gauss": "crt/crtglow_gauss.slangp",
    "glow_lanczos": "crt/crtglow_lanczos.slangp",
    "hyllian": "crt/crt-hyllian.slangp",
    "royale": "crt/crt-royale.slangp",
    "sim": "crt/crtsim.slangp",
}


def describe_bindings(source: str) -> dict:
    """The selected presets use only std140 scalar, vec4 and mat4 members."""
    bindings = {}
    for match in re.finditer(r'layout\s*\(([^)]*)\)\s*uniform\s+(\w+)\s*\{([^}]+)\}\s*(\w+)\s*;', source):
        layout, _, body, name = match.groups()
        binding = int(re.search(r'binding\s*=\s*(\d+)', layout)[1])
        fields, offset = [], 0
        for declaration in body.split(';'):
            if not declaration.strip():
                continue
            kind, field = declaration.strip().split()
            alignment, size = {"float": (4, 4), "uint": (4, 4), "int": (4, 4), "vec4": (16, 16), "mat4": (16, 64)}[kind]
            offset = (offset + alignment - 1) // alignment * alignment
            fields.append({"name": field, "type": kind, "offset": offset})
            offset += size
        description = {"kind": "buffer", "name": name, "size": (offset + 15) // 16 * 16, "fields": fields}
        if binding in bindings and bindings[binding] != description:
            raise ValueError(f"Conflicting uniform buffer binding {binding}")
        bindings[binding] = description
    for match in re.finditer(r'layout\s*\(([^)]*)\)\s*uniform\s+sampler2D\s+(\w+)\s*;', source):
        binding = int(re.search(r'binding\s*=\s*(\d+)', match[1])[1])
        description = {"kind": "sampler", "name": match[2]}
        if binding in bindings and bindings[binding] != description:
            raise ValueError(f"Conflicting texture binding {binding}")
        bindings[binding] = description
    return {str(binding): description for binding, description in sorted(bindings.items())}


def import_presets(source: Path, destination: Path) -> dict:
    source, destination = source.resolve(), destination.resolve()
    dependencies = set()

    def collect(path: Path) -> Path:
        path = path.resolve()
        path.relative_to(source)  # Reject dependencies escaping the source tree.
        if not path.is_file():
            raise ValueError(f"Missing preset dependency: {path}")
        dependencies.add(path)
        return path

    def expand(path: Path, stack=()) -> str:
        path = collect(path)
        if path in stack:
            raise ValueError(f"Cyclic include: {path}")
        result = []
        for line in path.read_text().splitlines():
            include = re.match(r'\s*#include\s+"([^"]+)"', line)
            result.append(expand(path.parent / include[1], (*stack, path)) if include else line)
        return "\n".join(result) + "\n"

    manifest = {"upstream": "https://github.com/libretro/slang-shaders", "revision": REVISION, "presets": {}}
    for name, relative in PRESETS.items():
        preset_path = collect(source / relative)
        config = {}
        for line in preset_path.read_text().splitlines():
            parts = shlex.split(line, comments=True)
            if parts:
                key, value = " ".join(parts).split("=", 1)
                config[key.strip()] = value.strip()
        preset = {"path": relative, "passes": [], "textures": {}, "parameters": {}}
        for i in range(int(config["shaders"])):
            path = preset_path.parent / config[f"shader{i}"]
            expanded = expand(path)
            # Conditional includes may contain alternate complete stage pairs.
            # Resolve those branches before splitting, as Slang's loader does.
            expanded = re.sub(r'^\s*#version[^\n]*', '', expanded, flags=re.M)
            expanded = subprocess.run(["clang", "-E", "-P", "-x", "c", "-undef", "-"], input=expanded, text=True, capture_output=True, check=True).stdout
            parameters = re.findall(r'^\s*#pragma parameter (\w+)\s+"([^"]+)"\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)', expanded, re.M)
            for key, label, default, minimum, maximum, step in parameters:
                preset["parameters"][key] = {"label": label, "default": float(config.get(key, default)), "min": float(minimum), "max": float(maximum), "step": float(step)}
            sections = {"common": [], "vertex": [], "fragment": []}
            section = "common"
            for line in expanded.splitlines():
                marker = re.fullmatch(r'\s*#pragma stage (vertex|fragment)\s*', line)
                if marker:
                    section = marker[1]
                else:
                    sections[section].append(line)
            common, vertex, fragment = ("\n".join(sections[key]) + "\n" for key in ("common", "vertex", "fragment"))
            if not vertex.strip() or not fragment.strip():
                raise ValueError(f"Missing shader stage: {path}")
            common = re.sub(r'^\s*#version[^\n]*', '', common, flags=re.M)
            buffer_binding = 1 + max(int(value) for value in re.findall(r'binding\s*=\s*(\d+)', common + vertex + fragment))
            common = re.sub(r'layout\s*\(\s*push_constant\s*\)', f'layout(std140, set = 0, binding = {buffer_binding})', common)
            stages = {}
            for stage, body in [("vertex", vertex), ("fragment", fragment)]:
                stages[stage] = "#version 450\n" + re.sub(r'^\s*#pragma[^\n]*', '', common + body, flags=re.M)
            shader_format = re.search(r'#pragma format\s+(\w+)', expanded)
            entry = {"path": str(path.resolve().relative_to(source)), "vertex": stages["vertex"], "fragment": stages["fragment"], "format": shader_format[1] if shader_format else "", "options": {}}
            entry["bindings"] = describe_bindings(stages["vertex"] + "\n" + stages["fragment"])
            for key in ["filter_linear", "wrap_mode", "mipmap_input", "float_framebuffer", "srgb_framebuffer", "scale_type", "scale_type_x", "scale_type_y", "scale", "scale_x", "scale_y", "alias", "frame_count_mod"]:
                if f"{key}{i}" in config:
                    entry["options"][key] = config[f"{key}{i}"]
            preset["passes"].append(entry)
        for texture in config.get("textures", "").split(";"):
            if not texture:
                continue
            path = collect(preset_path.parent / config[texture])
            preset["textures"][texture] = {"path": str(path.relative_to(source)), "linear": config.get(texture + "_linear", "true") == "true", "mipmap": config.get(texture + "_mipmap", "false") == "true", "wrap": config.get(texture + "_wrap_mode", "clamp_to_border")}
        manifest["presets"][name] = preset
    # Include license notices beside dependencies and in every parent directory.
    for path in list(dependencies):
        for parent in [path.parent, *path.parents]:
            if parent == source.parent:
                break
            for candidate in parent.iterdir():
                if candidate.is_file() and candidate.name.lower().startswith(("license", "copying", "copyright")):
                    dependencies.add(candidate)
    manifest["files"] = {}
    for path in sorted(dependencies):
        relative = path.relative_to(source)
        target = destination / "upstream" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        manifest["files"][str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
    (destination / "presets.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--destination", type=Path, default=Path(__file__).resolve().parents[1] / "addons/ntscrt/third_party/slang")
    args = parser.parse_args()
    result = import_presets(args.source, args.destination)
    print(json.dumps({"files": len(result["files"]), "presets": {name: {"passes": len(value["passes"]), "parameters": len(value["parameters"])} for name, value in result["presets"].items()}}, indent=2))
