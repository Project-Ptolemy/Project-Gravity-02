"""Render real shape trajectories as uneven debris, without a Roblox session.

Requires Lune 0.10+ and Pillow. Run from the repository root:
  python tools/preview_shapes.py --parts 768 --output docs/shape-gallery.png
  python tools/preview_shapes.py --all --frames 72 --duration 6 --output docs/motion
  python tools/preview_shapes.py --shape "Ghost Galleon" --frames 60 --output ship.gif
Use --lune PATH or the LUNE environment variable if Lune is not on PATH.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont, ImageSequence
from shape_catalog import CAPTIONS, DISASTER_SHAPES, GROUPS, NEW_SHAPES, PRESETS, VAST_SHAPES, VIEWS

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = (13, 20, 31)
PALETTE = ((188, 169, 142), (153, 162, 171), (171, 182, 183), (144, 155, 176),
           (177, 146, 131), (127, 153, 162), (186, 179, 157), (142, 144, 150))
FACES = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
         (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))
FONT_CACHE = {}


def gif_palette():
    # Shared material colors prevent per-frame palette flicker. Include text
    # antialias shades as well, so labels remain smooth without GIF dithering.
    colors = [BACKGROUND, (134, 212, 228)]
    for base in (*PALETTE, (104, 201, 211)):
        colors.extend(tuple(int(v * (0.65 + 0.07 * face)) for v in base) for face in range(6))
    for base in ((235, 242, 248), (236, 243, 249), (119, 180, 192), (181, 197, 211),
                 (127, 149, 170), (127, 167, 182), (112, 135, 157), (36, 48, 64), (88, 175, 186)):
        colors.extend(tuple(round(a + (b - a) * step / 20) for a, b in zip(BACKGROUND, base)) for step in range(1, 21))
    colors = list(dict.fromkeys(colors))
    assert len(colors) <= 256
    colors.extend([BACKGROUND] * (256 - len(colors)))
    palette = Image.new("P", (1, 1))
    palette.putpalette([channel for color in colors for channel in color])
    return palette


def font(size):
    if size not in FONT_CACHE:
        for path in ("C:/Windows/Fonts/segoeui.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
            if Path(path).exists():
                FONT_CACHE[size] = ImageFont.truetype(path, size)
                break
        else:
            FONT_CACHE[size] = ImageFont.load_default()
    return FONT_CACHE[size]


def fit_font(text, width, preferred):
    for size in range(preferred, 10, -1):
        candidate = font(size)
        if candidate.getlength(text) <= width:
            return candidate
    return font(11)


def runtime_path(explicit=None):
    found = explicit or os.environ.get("LUNE") or shutil.which("lune")
    if not found:
        temporary = Path(tempfile.gettempdir()) / "gravity-lune-0.10.5" / "lune.exe"
        if temporary.is_file():
            found = str(temporary)
    if not found:
        raise SystemExit("Lune 0.10+ is required. Install lune-org/lune, or pass --lune PATH.")
    return str(found)


def source_path(name):
    for directory in ("shapes", "shapes-onreview"):
        path = ROOT / directory / f"{name}.lua"
        if path.is_file():
            return path
    raise ValueError(f"Unknown shape: {name}")


def sample(name, args, overrides):
    request = dict(name=name, parts=args.parts, time=args.time, mode=args.mode,
                   frames=args.frames, duration=args.duration, overrides=overrides,
                   fixtures=not args.no_fixtures)
    digest = hashlib.sha256(json.dumps(request, sort_keys=True).encode())
    for path in (source_path(name), ROOT / "config.lua", ROOT / "tools/sample_shapes.luau"):
        digest.update(path.read_bytes())
    digest.update(args.runtime_version.encode())
    fingerprint = digest.hexdigest()
    cache = Path(tempfile.gettempdir()) / "gravity-shape-previews" / f"{fingerprint}.json"
    if cache.is_file() and not args.no_cache:
        data = json.loads(cache.read_text(encoding="utf-8"))
    else:
        result = subprocess.run(
            [args.lune, "run", "tools/sample_shapes.luau", json.dumps(request)],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=240,
        )
        if result.returncode:
            raise RuntimeError(f"Sampling {name} failed:\n{result.stderr}\n{result.stdout}")
        data = json.loads(result.stdout)
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    data["fingerprint"] = fingerprint
    data["overrides"] = overrides
    if len(data["frames"]) != args.frames or any(len(frame) != args.parts for frame in data["frames"]):
        raise ValueError(f"Incorrect trajectory dimensions: {name}")
    if not all(math.isfinite(v) for frame in data["frames"] for point in frame for v in point):
        raise ValueError(f"Non-finite trajectory: {name}")
    return data


def rotate(x, y, z, yaw, pitch):
    x, z = x * math.cos(yaw) - z * math.sin(yaw), x * math.sin(yaw) + z * math.cos(yaw)
    y, z = y * math.cos(pitch) - z * math.sin(pitch), y * math.sin(pitch) + z * math.cos(pitch)
    return x, y, z


def fixed_camera(name, data):
    points = [point for cloud in data["frames"] for point in cloud]
    center = [(min(p[i] for p in points) + max(p[i] for p in points)) / 2 for i in range(3)]
    yaw, pitch = map(math.radians, VIEWS.get(name, (22, 15)))
    bounds = [float("inf"), float("-inf"), float("inf"), float("-inf")]
    radii = [math.sqrt(sum(v * v for v in size)) / 2 for size in data["sizes"]]
    for cloud in data["frames"]:
        for point, radius in zip(cloud, radii):
            x, y, _ = rotate(*(point[i] - center[i] for i in range(3)), yaw, pitch)
            bounds = [min(bounds[0], x - radius), max(bounds[1], x + radius),
                      min(bounds[2], y - radius), max(bounds[3], y + radius)]
    return center, bounds


def projected_cuboids(name, sizes):
    yaw, pitch = map(math.radians, VIEWS.get(name, (22, 15)))
    meshes = []
    for index, (sx, sy, sz) in enumerate(sizes):
        offsets = []
        for corner in range(8):
            offset = (sx * (0.5 if corner & 4 else -0.5), sy * (0.5 if corner & 2 else -0.5), sz * (0.5 if corner & 1 else -0.5))
            offset = rotate(*offset, index * 2.399963229728653, math.sin(index * 1.73) * 0.5)
            offsets.append(rotate(*offset, yaw, pitch))
        base = (104, 201, 211) if index % 53 == 5 else PALETTE[index % len(PALETTE)]
        colors = [tuple(int(v * (0.65 + 0.07 * face)) for v in base) for face in range(6)]
        meshes.append((offsets, colors))
    return meshes


def panel(name, data, frame, size, mode, time, camera, meshes):
    image = Image.new("RGB", (size, size), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.rectangle((8, 7, size - 8, size - 7), outline=(36, 48, 64), width=1)
    yaw, pitch = map(math.radians, VIEWS.get(name, (22, 15)))
    center, bounds = camera
    polygons, points = [], []
    for index, position in enumerate(data["frames"][frame]):
        x, y, z = position
        cx, cy, cz = x - center[0], y - center[1], z - center[2]
        cx, cy, cz = rotate(cx, cy, cz, yaw, pitch)
        if mode == "markers":
            points.append((cx, cy, cz))
            continue
        # The same irregular orientations and part identities in every frame.
        offsets, colors = meshes[index]
        vertices = [(cx + dx, cy + dy, cz + dz) for dx, dy, dz in offsets]
        for face_index, face in enumerate(FACES):
            poly = [vertices[i] for i in face]
            polygons.append((sum(v[2] for v in poly) / 4, poly, colors[face_index]))
    min_x, max_x, min_y, max_y = bounds
    scale = min((size - 56) / max(1, max_x - min_x), (size - 142) / max(1, max_y - min_y))

    def screen(point):
        return (size / 2 + (point[0] - (min_x + max_x) / 2) * scale,
                (size + 28) / 2 - (point[1] - (min_y + max_y) / 2) * scale)

    if mode == "markers":
        for point in sorted(points, key=lambda v: v[2]):
            x, y = screen(point)
            draw.ellipse((x - 1.4, y - 1.4, x + 1.4, y + 1.4), fill=(134, 212, 228))
    else:
        for _, poly, color in sorted(polygons, key=lambda v: v[0]):
            draw.polygon([screen(p) for p in poly], fill=color)
    draw.text((22, 17), name, font=fit_font(name, size - 44, 22), fill=(235, 242, 248))
    tag = "REVIEW" if data["review"] else ("NEW" if name in (*NEW_SHAPES, *DISASTER_SHAPES, *VAST_SHAPES) else "ACTIVE")
    label = data["labels"][frame]
    if label == "Fixed core":
        label = "Active motion" if data["continuous_motion"] else "Fixed core"
    info = f"{tag}  /  {label}"
    draw.text((22, 48), info, font=fit_font(info, size - 44, 12), fill=(119, 180, 192))
    caption = CAPTIONS.get(name, "Shape motion")
    draw.text((22, size - 53), caption, font=fit_font(caption, size - 44, 13), fill=(181, 197, 211))
    detail = f"{len(data['sizes'])} {'mixed pieces' if mode == 'debris' else 'target markers'}"
    draw.text((22, size - 31), detail, font=font(11), fill=(127, 149, 170))
    stamp = f"{time:.2f} s"
    draw.text((size - 22 - font(11).getlength(stamp), size - 31), stamp, font=font(11), fill=(127, 149, 170))
    return image


def render(names, data, args, path, title):
    cols, rows = min(3, len(names)), math.ceil(len(names) / 3)
    width, height = cols * args.cell, rows * args.cell + 92
    cameras = {name: fixed_camera(name, data[name]) for name in names}
    meshes = {name: projected_cuboids(name, data[name]["sizes"]) for name in names}
    images = []
    for frame in range(args.frames):
        time = args.time + (args.duration * frame / args.frames if args.frames > 1 else 0)
        sheet = Image.new("RGB", (width, height), BACKGROUND)
        draw = ImageDraw.Draw(sheet)
        draw.text((22, 12), title, font=fit_font(title, width - 44, 25), fill=(236, 243, 249))
        subtitle = "PROJECT GRAVITY  /  Mixed disaster debris  /  Fixed cameras"
        draw.text((22, 46), subtitle, font=fit_font(subtitle, width - 44, 12), fill=(127, 167, 182))
        for index, name in enumerate(names):
            tile = panel(name, data[name], frame, args.cell, args.mode, time, cameras[name], meshes[name])
            sheet.paste(tile, ((index % cols) * args.cell, 70 + (index // cols) * args.cell))
        note = "Offline module trajectories / illustrative materials and orientations"
        if args.frames > 1:
            note += " / excerpt resets on repeat"
            draw.rectangle((22, height - 4, 22 + (width - 44) * (frame + 1) / args.frames, height - 3), fill=(88, 175, 186))
        draw.text((22, height - 21), note, font=fit_font(note, width - 44, 10), fill=(112, 135, 157))
        images.append(sheet)
    path.parent.mkdir(parents=True, exist_ok=True)
    if len(images) > 1:
        # GIF uses 10 ms ticks. Alternate delays to preserve total playback time.
        durations = [10 * (round((i + 1) * args.duration * 100 / args.frames)
                           - round(i * args.duration * 100 / args.frames)) for i in range(args.frames)]
        if path.suffix.lower() == ".gif":
            palette = gif_palette()
            encoded = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in images]
        else:
            encoded = images
        encoded[0].save(path, save_all=True, append_images=encoded[1:], loop=0,
                        duration=durations, optimize=False, disposal=1)
    else:
        images[0].save(path)
    print(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path, flush=True)
    return images


def trajectory_stats(data):
    if "stats" in data:
        return data["stats"]
    first = data["frames"][0]
    movement = [max(math.dist(first[i], frame[i]) for frame in data["frames"]) for i in range(len(first))]
    unique = len({hashlib.sha256(json.dumps(frame).encode()).hexdigest() for frame in data["frames"]})
    return dict(moving_parts=sum(distance > 0.01 for distance in movement),
                max_displacement=round(max(movement), 3), distinct_frames=unique)


def write_gallery_index(directory, entries, args):
    total = sum(len(names) for _, names, _, _ in entries)
    reviews = sum(item["review"] for _, _, data, _ in entries for item in data.values())
    lines = ["# Shape motion gallery", "", f"All **{total} shapes**, in **{len(entries)} GIFs with up to six shapes each**: {total - reviews} active and {reviews} review modules.", "",
             f"Each clip shows {args.duration:g} seconds at {args.frames / args.duration:g} fps, using {args.parts} uneven pieces per shape. "
             "Bricks, planks, beams and wall panels keep the same identities and illustrative orientations throughout. Cyan pieces help track the motion.", "",
             "The sampler executes the actual Lua modules with persistent records and 60 Hz updates. Cameras stay fixed across each clip. "
             "These are offline shape trajectories; collisions, inertia and live network ownership are not simulated. "
             "Velocity-only tools use an approximate integrator. Each excerpt starts again when the GIF repeats.", "",
             "Interactive panels label their scripted input. Mech Suit and Platform follow an animated R6 rig; "
             "Broom, lightning and Twin Core Beam receive cursor input; Raigo launches on a timer; "
             "Sculptor drags a selected block of debris; Point Impact and Red follow a moving core. "
             "Mugen Train and Dragons Teeth follow a recorded core trail; Meteor Hammer and Mochi follow a swinging core. "
             "Drop is reselected every 2.5 seconds, then released into a gravity-and-floor fixture. "
             "Ymir and Orochi probe a synthetic room with a doorway. Review shapes remain in `shapes-onreview/`.", "",
             "[New formations and math changes](../FORMATIONS.md) · [Gallery contact sheet](contact-sheet.png)", ""]
    manifest = dict(runtime=args.runtime_version, frames=args.frames, duration=args.duration,
                    parts=args.parts, mode=args.mode, cell=args.cell, time=args.time,
                    simulation_hz=60, sample_stride=1, groups=[])
    for index, (title, names, data, path) in enumerate(entries, 1):
        lines.extend([f"## {index:02d}. {title}", "", f"![{title}: {', '.join(names)}]({path.name})", "",
                      "| Shape | Motion |", "| --- | --- |"])
        records = []
        for name in names:
            item = data[name]
            mark = " (review)" if item["review"] else (" (new)" if name in (*NEW_SHAPES, *DISASTER_SHAPES, *VAST_SHAPES) else "")
            lines.append(f"| {name}{mark} | {CAPTIONS[name]} |")
            records.append(dict(name=name, source=source_path(name).relative_to(ROOT).as_posix(),
                                review=item["review"], fixture=item["fixture"], method=item["method"],
                                overrides=item["overrides"], config=item["config"],
                                source_fingerprint=item["fingerprint"], **trajectory_stats(item)))
        changed = [f"{name}: " + ", ".join(f"`{key}={value}`" for key, value in data[name]["overrides"].items())
                   for name in names if data[name]["overrides"]]
        if changed:
            lines.extend(["", "Gallery settings: " + "; ".join(changed) + ". All other controls use module/config defaults."])
        lines.append("")
        manifest["groups"].append(dict(title=title, gif=path.name, shapes=records))
    lines.extend(["## Rebuild", "", "Install [Lune](https://github.com/lune-org/lune) and Pillow, then run from the repository root:", "", "```powershell",
                  f"python tools/preview_shapes.py --all --parts {args.parts} --cell {args.cell} --frames {args.frames} --duration {args.duration:g} --output docs/motion",
                  "```", "", "Use `--lune PATH` if needed. `--no-cache` resamples; `--no-fixtures` disables scripted interactions. "
                  "Per-shape settings, source fingerprints and motion checks are in [manifest.json](manifest.json).", ""])
    (directory / "index.md").write_text("\n".join(lines), encoding="utf-8")
    (directory / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def existing_gallery(args):
    manifest = json.loads((args.output / "manifest.json").read_text(encoding="utf-8"))
    for key in ("frames", "duration", "parts", "mode", "cell", "time"):
        if manifest[key] != getattr(args, key):
            raise ValueError(f"--group must preserve the existing gallery's {key}={manifest[key]}")
    if len(manifest["groups"]) != len(GROUPS):
        raise ValueError("Rebuild the whole gallery after changing the catalog")
    entries = []
    for old, (title, catalog) in zip(manifest["groups"], GROUPS):
        names = [name for name, _ in catalog]
        if [item["name"] for item in old["shapes"]] != names:
            raise ValueError("Rebuild the whole gallery after changing the catalog")
        data = {item["name"]: {**item, "fingerprint": item["source_fingerprint"],
                              "stats": {key: item[key] for key in ("moving_parts", "max_displacement", "distinct_frames")}}
                for item in old["shapes"]}
        entries.append((title, names, data, args.output / old["gif"]))
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--shape", action="append", help="Repeat for selected shapes; defaults to the 15 additions")
    selection.add_argument("--all", action="store_true", help="Export every active and review module, six per GIF")
    parser.add_argument("--group", action="append", type=int, choices=range(1, len(GROUPS) + 1),
                        help="With --all, rebuild only selected groups in an existing gallery")
    parser.add_argument("--parts", type=int, default=384)
    parser.add_argument("--time", type=float, default=0)
    parser.add_argument("--mode", choices=("debris", "markers"), default="debris")
    parser.add_argument("--set", action="append", default=[], metavar="KEY=VALUE")
    parser.add_argument("--cell", type=int, default=384)
    parser.add_argument("--frames", type=int)
    parser.add_argument("--duration", type=float, default=6)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--lune")
    parser.add_argument("--no-fixtures", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    args = parser.parse_args()
    args.frames = args.frames if args.frames is not None else (72 if args.all else 1)
    args.output = (args.output or ROOT / "docs" / ("motion" if args.all else "shape-preview.png")).resolve()
    if not 1 <= args.parts <= 10000 or args.cell < 240:
        parser.error("parts must be 1..10000 and cell must be at least 240")
    if not 1 <= args.frames <= 120 or not math.isfinite(args.duration) or not math.isfinite(args.time) or args.duration <= 0 or args.time < 0:
        parser.error("frames must be 1..120, duration positive, and time nonnegative")
    if args.all and args.frames < 2:
        parser.error("--all produces GIFs; use at least two frames")
    if args.group and not args.all:
        parser.error("--group requires --all and an existing complete gallery")
    if not args.all and args.frames > 1 and args.output.suffix.lower() not in (".gif", ".webp"):
        parser.error("animated output requires a .gif or .webp extension")
    overrides = {}
    for item in args.set:
        key, separator, value = item.partition("=")
        if not separator:
            parser.error("--set expects KEY=VALUE")
        try:
            overrides[key] = json.loads(value)
        except json.JSONDecodeError:
            overrides[key] = value
    args.lune = runtime_path(args.lune)
    args.runtime_version = subprocess.check_output([args.lune, "--version"], text=True).strip()
    groups = GROUPS if args.all else (("New formations" if not args.shape else "Shape motion", [(name, "") for name in (args.shape or NEW_SHAPES)]),)
    if args.all:
        catalog = [name for _, shapes in GROUPS for name, _ in shapes]
        files = [p.stem for folder in ("shapes", "shapes-onreview") for p in (ROOT / folder).glob("*.lua")]
        if len(catalog) != len(set(catalog)) or set(catalog) != set(files) or any(not 1 <= len(entries) <= 6 for _, entries in GROUPS):
            raise SystemExit(f"Update shape_catalog.py: missing={set(files) - set(catalog)}, extra={set(catalog) - set(files)}")
    entries, covers = existing_gallery(args) if args.group else [], []
    for index, (title, shapes) in enumerate(groups, 1):
        if args.group and index not in args.group:
            continue
        names = [name for name, _ in shapes]
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = {name: executor.submit(sample, name, args, {**(PRESETS.get(name, {}) if args.all else {}), **overrides}) for name in names}
            data = {name: future.result() for name, future in futures.items()}
        path = args.output / f"shapes-{index:02d}.gif" if args.all else args.output
        images = render(names, data, args, path, f"{index:02d} / {title}" if args.all else title)
        if args.all:
            with Image.open(path) as gif:
                if gif.n_frames != args.frames:
                    raise ValueError(f"GIF lost frames: {path}")
                total = sum(frame.info.get("duration", 0) for frame in ImageSequence.Iterator(gif))
                if abs(total - args.duration * 1000) > 10:
                    raise ValueError(f"Incorrect GIF playback duration: {path}")
            for name in names:
                if trajectory_stats(data[name])["distinct_frames"] < 2:
                    raise ValueError(f"No motion sampled for {name}")
            cover = images[len(images) // 2].resize((576, 430), Image.Resampling.LANCZOS)
            covers.append(cover)
            review = Image.new("RGB", (576 * 3, 430), BACKGROUND)
            for i, frame in enumerate((images[0], images[len(images) // 2], images[-1])):
                review.paste(frame.resize((576, 430), Image.Resampling.LANCZOS), (i * 576, 0))
            review_dir = ROOT / "docs/.motion-review"
            review_dir.mkdir(parents=True, exist_ok=True)
            review.save(review_dir / f"review-{index:02d}.png")
            metadata = {name: {**{k: v for k, v in data[name].items() if k not in ("frames", "sizes", "labels", "centers")},
                                "stats": trajectory_stats(data[name])} for name in names}
            entry = (title, names, metadata, path)
            if args.group:
                entries[index - 1] = entry
            else:
                entries.append(entry)
    if args.all:
        if args.group:
            covers = []
            for _, _, _, path in entries:
                with Image.open(path) as gif:
                    gif.seek(gif.n_frames // 2)
                    covers.append(gif.convert("RGB").resize((576, 430), Image.Resampling.LANCZOS))
        contact = Image.new("RGB", (576 * 3, math.ceil(len(covers) / 3) * 430), BACKGROUND)
        for i, cover in enumerate(covers):
            contact.paste(cover, ((i % 3) * 576, (i // 3) * 430))
        contact.save(args.output / "contact-sheet.png")
        write_gallery_index(args.output, entries, args)
        print(f"Verified {len(entries)} GIFs / {sum(len(e[1]) for e in entries)} shapes.", flush=True)


if __name__ == "__main__":
    main()
