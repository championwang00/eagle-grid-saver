#!/usr/bin/env python3
import json
import pathlib
import shutil
import subprocess
import tempfile


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


def write_ppm(path, color):
    w, h = 320, 200
    r, g, b = color
    with open(path, "wb") as f:
        f.write(f"P6\n{w} {h}\n255\n".encode())
        f.write(bytes([r, g, b]) * w * h)


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    current_library = pathlib.Path("/tmp/EagleGridSaverRemapCurrent.library")
    previous_library = pathlib.Path("/Previous/Computer/EagleGridSaverRemapCurrent.library")
    if current_library.exists():
        shutil.rmtree(current_library)
    images = current_library / "images"
    info = images / "VIDEO.info"
    info.mkdir(parents=True)

    ppm = info / "poster.ppm"
    poster = info / "video_thumbnail.jpg"
    write_ppm(ppm, (80, 180, 240))
    run(["sips", "-s", "format", "jpeg", str(ppm), "--out", str(poster)], project)
    ppm.unlink()

    # A tiny placeholder is enough for this remap verifier: it checks that the
    # saver maps to the current computer's source path, not that AVFoundation
    # can decode this specific synthetic file.
    video = info / "demo.mp4"
    video.write_bytes(b"placeholder video bytes")
    (info / "metadata.json").write_text(json.dumps({
        "name": "demo",
        "width": 320,
        "height": 200,
    }))

    support = pathlib.Path.home() / "Library/Application Support/EagleGridSaver"
    cache = support / "DisplayCache"
    backup = pathlib.Path(tempfile.mkdtemp(prefix="EagleGridSaverCacheBackup-")) / "DisplayCache"
    had_cache = cache.exists()
    if had_cache:
        shutil.move(str(cache), str(backup))
    cache.mkdir(parents=True, exist_ok=True)

    try:
        cache_name = "4-remap-video.jpg"
        shutil.copyfile(poster, cache / cache_name)
        previous_video_path = str(previous_library / "images/VIDEO.info/demo.mp4")
        (cache / "manifest.json").write_text(json.dumps({
            "version": "4",
            "libraryPath": str(previous_library),
            "generatedAt": 0,
            "items": [{
                "cachePath": cache_name,
                "sourcePath": previous_video_path,
                "title": "demo",
                "width": 320,
                "height": 200,
                "isVideo": True,
            }],
        }))

        subprocess.run(["defaults", "write", "com.chaopi.EagleGridSaver", "EagleGridSaver.libraryPath", str(current_library)], check=True)
        run(["./Scripts/build.sh"], project)
        run([
            "clang", "-fobjc-arc",
            "-framework", "Cocoa",
            "-framework", "ScreenSaver",
            "Scripts/inspect_saver_state.m",
            "-o", "dist/inspect_saver_state",
        ], project)
        result = subprocess.run(["dist/inspect_saver_state", "dist/EagleGridSaver.saver"], cwd=project, text=True, capture_output=True)
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="")
        if result.returncode != 0:
            raise SystemExit(f"inspect_saver_state failed: {result.returncode}")
        if "videos=1" not in result.stdout or "playableVideoURLs=1" not in result.stdout:
            raise SystemExit("video remap verification failed")
    finally:
        shutil.rmtree(cache, ignore_errors=True)
        if had_cache:
            shutil.move(str(backup), str(cache))


if __name__ == "__main__":
    main()
