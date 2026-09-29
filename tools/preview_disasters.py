"""Render the moving NDS additions with real module trajectories.

python tools/preview_disasters.py
python tools/preview_disasters.py --collection vast
Requires Lune 0.10+ and Pillow, like preview_shapes.py.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace

from PIL import Image, ImageSequence
from preview_shapes import ROOT, render, runtime_path, sample, trajectory_stats
from shape_catalog import DISASTER_GROUPS, VAST_GROUPS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lune")
    parser.add_argument("--parts", type=int, default=512)
    parser.add_argument("--frames", type=int, default=96)
    parser.add_argument("--collection", choices=("disasters", "vast"), default="disasters")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    args.output = args.output or ROOT / "docs" / args.collection
    groups = VAST_GROUPS if args.collection == "vast" else DISASTER_GROUPS
    all_names = [name for _, entries in groups for name, _ in entries]
    heading = "Thirty vast formations" if args.collection == "vast" else "Twelve moving disasters"
    if not 1 <= args.parts <= 10000 or not 2 <= args.frames <= 120:
        parser.error("parts must be 1..10000 and frames 2..120")
    options = SimpleNamespace(
        lune=runtime_path(args.lune), parts=args.parts, frames=args.frames,
        duration=8, time=0, mode="debris", cell=384, no_cache=False, no_fixtures=True,
    )
    options.runtime_version = subprocess.check_output([options.lune, "--version"], text=True).strip()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = dict(runtime=options.runtime_version, parts=args.parts, frames=args.frames,
                    duration=options.duration, simulation_hz=60, groups=[])
    covers = {}
    for index, (title, entries) in enumerate(groups, 1):
        names = [name for name, _ in entries]
        with ThreadPoolExecutor(max_workers=3) as pool:
            data = dict(zip(names, pool.map(lambda name: sample(name, options, {}), names)))
        path = args.output / f"motion-{index:02d}.gif"
        images = render(names, data, options, path, title)
        with Image.open(path) as clip:
            assert clip.n_frames == args.frames
            assert sum(frame.info["duration"] for frame in ImageSequence.Iterator(clip)) == 8000
        records = []
        for name in names:
            item = data[name]
            stats = trajectory_stats(item)
            assert stats["moving_parts"] == args.parts and stats["distinct_frames"] == args.frames, name
            records.append(dict(name=name, config=item["config"], source_fingerprint=item["fingerprint"], **stats))
            # Keep the same frame and debris identities in the overview.
            covers[name] = {**item, "frames": [item["frames"][args.frames // 2]],
                            "labels": [item["labels"][args.frames // 2]]}
        manifest["groups"].append(dict(title=title, gif=path.name, shapes=records))
        # Four snapshots make the changing silhouettes inspectable without GIF playback.
        contact = Image.new("RGB", (images[0].width * 2, images[0].height * 2))
        for cell, frame in enumerate((0, args.frames // 3, 2 * args.frames // 3, args.frames - 1)):
            contact.paste(images[frame], ((cell % 2) * images[0].width, (cell // 2) * images[0].height))
        contact.save(args.output / f"contact-{index:02d}.png")
    options.frames, options.time = 1, 4
    render(all_names, covers, options, args.output / "gallery.png", heading)
    options.parts = 160
    with ThreadPoolExecutor(max_workers=3) as pool:
        sparse = dict(zip(all_names, pool.map(lambda name: sample(name, options, {}), all_names)))
    render(all_names, sparse, options, args.output / "gallery-sparse.png", heading + " / 160 pieces each")
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(all_names)} shapes, {args.parts} pieces, {args.frames} frames; sparse gallery uses 160 pieces.")


if __name__ == "__main__":
    main()
