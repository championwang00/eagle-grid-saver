#!/usr/bin/env python3
import json
import pathlib
import shutil
import subprocess
import tempfile

from verify_rendered_screenshots import black_stats


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


def write_ppm(path, color, width=640, height=420):
    r, g, b = color
    with open(path, "wb") as f:
        f.write(f"P6\n{width} {height}\n255\n".encode())
        f.write(bytes([r, g, b]) * width * height)


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    support = pathlib.Path.home() / "Library/Application Support/EagleGridSaver"
    cache = support / "DisplayCache"
    backup = pathlib.Path(tempfile.mkdtemp(prefix="EagleGridSaverCacheBackup-")) / "DisplayCache"
    had_cache = cache.exists()
    if had_cache:
        shutil.move(str(cache), str(backup))
    cache.mkdir(parents=True, exist_ok=True)

    try:
        run(["./Scripts/build.sh"], project)
        run([
            "clang",
            "-fobjc-arc",
            "-framework", "Cocoa",
            "-framework", "QuartzCore",
            "-framework", "ScreenSaver",
            "Scripts/render_preview.m",
            "-o", "dist/render_preview",
        ], project)

        colors = [
            (235, 90, 90), (90, 170, 235), (245, 200, 70), (95, 215, 135),
            (210, 120, 245), (90, 220, 210), (245, 140, 90), (170, 225, 95),
        ]
        items = []
        for idx in range(72):
            ppm = cache / f"bright-{idx}.ppm"
            jpg = cache / f"bright-{idx}.jpg"
            write_ppm(ppm, colors[idx % len(colors)])
            run(["sips", "-s", "format", "jpeg", str(ppm), "--out", str(jpg)], project)
            ppm.unlink()
            items.append({
                "cachePath": jpg.name,
                "sourcePath": str(jpg),
                "title": f"bright-{idx}",
                "width": 640,
                "height": 420,
                "isVideo": False,
            })

        (cache / "manifest.json").write_text(json.dumps({
            "version": "4",
            "libraryPath": "/tmp/EagleGridSaverBrightFixture.library",
            "generatedAt": 0,
            "items": items,
        }))
        (cache / "runtime-config.json").write_text(json.dumps({
            "version": 1,
            "scrollSpeedMultiplier": 10.0,
            "EagleGridSaver.scrollSpeedMultiplier": 10.0,
            "columnCount": 6,
            "EagleGridSaver.columnCount": 6,
            "updatedAt": 0,
        }))

        outputs = project / "outputs"
        outputs.mkdir(exist_ok=True)
        for frames in (1, 80, 420, 900, 1600):
            path = outputs / f"bright-wide-{frames}.png"
            run(["dist/render_preview", "dist/EagleGridSaver.saver", str(path), str(frames), "full", "3008", "1692"], project)
            black_ratio, largest_black_component = black_stats(path)
            print(f"frames={frames} black_ratio={black_ratio:.6f} largest_black_component={largest_black_component:.6f} output={path}")
            if black_ratio > 0.002 or largest_black_component > 0.001:
                raise SystemExit(f"bright fixture screenshot has black empty area: {path}")
    finally:
        shutil.rmtree(cache, ignore_errors=True)
        if had_cache:
            shutil.move(str(backup), str(cache))


if __name__ == "__main__":
    main()
