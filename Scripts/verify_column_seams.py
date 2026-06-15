#!/usr/bin/env python3
import json
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
            ppm = cache / f"seam-{idx}.ppm"
            jpg = cache / f"seam-{idx}.jpg"
            write_ppm(ppm, colors[idx % len(colors)])
            run(["sips", "-s", "format", "jpeg", str(ppm), "--out", str(jpg)], project)
            ppm.unlink()
            items.append({
                "cachePath": jpg.name,
                "sourcePath": str(jpg),
                "title": f"seam-{idx}",
                "width": 640,
                "height": 120,
                "isVideo": False,
            })

        (cache / "manifest.json").write_text(json.dumps({
            "version": "4",
            "libraryPath": "/tmp/EagleGridSaverColumnSeams.library",
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
        output = subprocess.check_output([str(inspect), "dist/EagleGridSaver.saver"], cwd=project, text=True)
        print(output)
        seam_lines = [line for line in output.splitlines() if line.startswith("columnSeams=")]
        if len(seam_lines) != 6:
            raise SystemExit(f"expected seam diagnostics for 6 columns, got {len(seam_lines)}")
        if any(not line.startswith("columnSeams=ok ") for line in seam_lines):
            raise SystemExit("column seam check failed")
    finally:
        shutil.rmtree(cache, ignore_errors=True)
        if had_cache:
            shutil.rmtree(cache, ignore_errors=True)
            shutil.move(str(backup), str(cache))


if __name__ == "__main__":
    main()
