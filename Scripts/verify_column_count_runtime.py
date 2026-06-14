#!/usr/bin/env python3
import json
import pathlib
import shutil
import subprocess
import tempfile


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


def write_ppm(path, color):
    w, h = 640, 420
    r, g, b = color
    with open(path, "wb") as f:
        f.write(f"P6\n{w} {h}\n255\n".encode())
        f.write(bytes([r, g, b]) * w * h)


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
        for idx, color in enumerate([
            (220, 60, 60),
            (60, 160, 220),
            (245, 180, 40),
            (80, 190, 110),
            (180, 90, 220),
            (90, 210, 170),
        ]):
            ppm = cache / f"column-{idx}.ppm"
            jpg = cache / f"column-{idx}.jpg"
            write_ppm(ppm, color)
            run(["sips", "-s", "format", "jpeg", str(ppm), "--out", str(jpg)], project)
            ppm.unlink()
            items.append({
                "cachePath": jpg.name,
                "sourcePath": str(jpg),
                "title": f"column-{idx}",
                "width": 640,
                "height": 420,
                "isVideo": False,
            })

        (cache / "manifest.json").write_text(json.dumps({
            "version": "4",
            "libraryPath": "/tmp/EagleGridSaverVerify.library",
            "generatedAt": 0,
            "items": items,
        }))
        (cache / "runtime-config.json").write_text(json.dumps({
            "version": 1,
            "scrollSpeedMultiplier": 1.0,
            "EagleGridSaver.scrollSpeedMultiplier": 1.0,
            "columnCount": 4,
            "EagleGridSaver.columnCount": 4,
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
        if "columnCount=4" not in output:
            raise SystemExit("column count runtime config was not applied")
        if "visibleCellColumns=4" not in output:
            raise SystemExit("screen saver layout did not use four columns")
    finally:
        shutil.rmtree(cache, ignore_errors=True)
        if had_cache:
            shutil.rmtree(cache, ignore_errors=True)
            shutil.move(str(backup), str(cache))


if __name__ == "__main__":
    main()
