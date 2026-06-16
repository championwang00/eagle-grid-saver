#!/usr/bin/env python3
import json
import pathlib
import shutil
import subprocess
import tempfile


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


def backup_defaults(project):
    backup = pathlib.Path(tempfile.mkdtemp(prefix="EagleGridSaverDefaultsBackup-")) / "com.chaopi.EagleGridSaver.plist"
    result = subprocess.run(["defaults", "export", "com.chaopi.EagleGridSaver", str(backup)], cwd=project)
    return backup if result.returncode == 0 else None


def restore_defaults(project, backup):
    if backup is not None and backup.exists():
        subprocess.run(["defaults", "import", "com.chaopi.EagleGridSaver", str(backup)], cwd=project, check=False)
    else:
        subprocess.run(["defaults", "delete", "com.chaopi.EagleGridSaver"], cwd=project, check=False)
    subprocess.run(["killall", "cfprefsd"], cwd=project, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def write_ppm(path, color, width=640, height=180):
    r, g, b = color
    with open(path, "wb") as f:
        f.write(f"P6\n{width} {height}\n255\n".encode())
        f.write(bytes([r, g, b]) * width * height)


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    library = pathlib.Path("/tmp/EagleGridSaverVideoLimit.library")
    if library.exists():
        shutil.rmtree(library)
    images = library / "images"
    images.mkdir(parents=True)

    support = pathlib.Path.home() / "Library/Application Support/EagleGridSaver"
    cache = support / "DisplayCache"
    backup = pathlib.Path(tempfile.mkdtemp(prefix="EagleGridSaverCacheBackup-")) / "DisplayCache"
    defaults_backup = backup_defaults(project)
    had_cache = cache.exists()
    if had_cache:
        shutil.move(str(cache), str(backup))
    cache.mkdir(parents=True, exist_ok=True)

    try:
        items = []
        colors = [
            (220, 60, 60),
            (60, 160, 220),
            (245, 180, 40),
            (80, 190, 110),
            (180, 90, 220),
            (90, 210, 170),
        ]
        for idx in range(12):
            info = images / f"VIDEO{idx}.info"
            info.mkdir()
            video = info / f"video{idx}.mp4"
            # The verifier only checks player allocation policy; decoding may fail.
            video.write_bytes(b"placeholder video bytes")
            poster_ppm = info / "video_thumbnail.ppm"
            poster = info / "video_thumbnail.jpg"
            write_ppm(poster_ppm, colors[idx % len(colors)])
            run(["sips", "-s", "format", "jpeg", str(poster_ppm), "--out", str(poster)], project)
            poster_ppm.unlink()
            (info / "metadata.json").write_text(json.dumps({
                "name": f"video{idx}",
                "width": 640,
                "height": 180,
            }))

            cache_name = f"limit-video-{idx}.jpg"
            shutil.copyfile(poster, cache / cache_name)
            items.append({
                "cachePath": cache_name,
                "sourcePath": str(video),
                "title": f"video{idx}",
                "width": 640,
                "height": 180,
                "isVideo": True,
            })

        (cache / "manifest.json").write_text(json.dumps({
            "version": "4",
            "libraryPath": str(library),
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

        subprocess.run(["defaults", "write", "com.chaopi.EagleGridSaver", "EagleGridSaver.libraryPath", str(library)], check=True)
        run(["./Scripts/build.sh"], project)
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
        result = subprocess.run([str(inspect), "dist/EagleGridSaver.saver"], cwd=project, text=True, capture_output=True)
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="")
        if result.returncode not in (0, 3):
            raise SystemExit(f"inspect_saver_state failed: {result.returncode}")

        values = {}
        for line in result.stdout.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
        visible = int(values.get("visibleVideoCells", "0"))
        active = int(values.get("activeVideoPlayers", "0"))
        print(f"video_player_limit visible={visible} active={active}")
        if visible <= 2:
            raise SystemExit("video limit fixture did not create more than two visible videos")
        if active > 2:
            raise SystemExit("too many active video players")
    finally:
        restore_defaults(project, defaults_backup)
        shutil.rmtree(cache, ignore_errors=True)
        if had_cache:
            shutil.rmtree(cache, ignore_errors=True)
            shutil.move(str(backup), str(cache))
        shutil.rmtree(library, ignore_errors=True)


if __name__ == "__main__":
    main()
