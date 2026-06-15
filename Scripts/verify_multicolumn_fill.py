#!/usr/bin/env python3
import json
import os
import pathlib
import shutil
import subprocess
import tempfile


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


def write_ppm(path, color, width=640, height=120):
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

        items = []
        colors = [
            (220, 60, 60),
            (60, 160, 220),
            (245, 180, 40),
            (80, 190, 110),
            (180, 90, 220),
            (90, 210, 170),
        ]
        for idx in range(36):
            ppm = cache / f"multi-{idx}.ppm"
            jpg = cache / f"multi-{idx}.jpg"
            write_ppm(ppm, colors[idx % len(colors)])
            run(["sips", "-s", "format", "jpeg", str(ppm), "--out", str(jpg)], project)
            ppm.unlink()
            items.append({
                "cachePath": jpg.name,
                "sourcePath": str(jpg),
                "title": f"multi-{idx}",
                "width": 640,
                "height": 120,
                "isVideo": False,
            })

        (cache / "manifest.json").write_text(json.dumps({
            "version": "4",
            "libraryPath": "/tmp/EagleGridSaverMultiColumn.library",
            "generatedAt": 0,
            "items": items,
        }))
        (cache / "runtime-config.json").write_text(json.dumps({
            "version": 1,
            "scrollSpeedMultiplier": 1.0,
            "EagleGridSaver.scrollSpeedMultiplier": 1.0,
            "columnCount": 6,
            "EagleGridSaver.columnCount": 6,
            "updatedAt": 0,
        }))

        inspect = project / "dist/inspect_saver_state"
        run([
            "clang",
            "-fobjc-arc",
            "-framework", "Cocoa",
            "-framework", "QuartzCore",
            "-framework", "ScreenSaver",
            "Scripts/inspect_saver_state.m",
            "-o", str(inspect),
        ], project)
        env = os.environ.copy()
        env["EAGLE_INSPECT_FRAMES"] = "0"
        output = subprocess.check_output([str(inspect), "dist/EagleGridSaver.saver"], cwd=project, text=True, env=env)
        print(output)

        covered_columns = 0
        for line in output.splitlines():
            if not line.startswith("column="):
                continue
            parts = dict(part.split("=", 1) for part in line.split())
            min_y = float(parts["minY"])
            max_y = float(parts["maxY"])
            cell_count = int(parts["cells"])
            hidden_visible = int(parts["hiddenVisible"])
            if min_y <= 0.0 and max_y >= 900.0 and cell_count >= 6 and hidden_visible == 0:
                covered_columns += 1
        if covered_columns != 6:
            raise SystemExit(f"multi-column layout only filled visible artwork in {covered_columns}/6 columns")
    finally:
        shutil.rmtree(cache, ignore_errors=True)
        if had_cache:
            shutil.rmtree(cache, ignore_errors=True)
            shutil.move(str(backup), str(cache))


if __name__ == "__main__":
    main()
