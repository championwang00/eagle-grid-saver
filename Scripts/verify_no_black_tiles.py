#!/usr/bin/env python3
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import struct
import zlib


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


def write_ppm(path, color):
    w, h = 640, 420
    r, g, b = color
    with open(path, "wb") as f:
        f.write(f"P6\n{w} {h}\n255\n".encode())
        f.write(bytes([r, g, b]) * w * h)


def read_png_rgb(path):
    data = pathlib.Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")

    offset = 8
    width = height = color_type = bit_depth = None
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk_type = data[offset + 4:offset + 8]
        chunk_data = data[offset + 8:offset + 8 + length]
        offset += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _compression, _filter, _interlace = struct.unpack(">IIBBBBB", chunk_data)
            if bit_depth != 8 or color_type not in (2, 6):
                raise SystemExit(f"unsupported PNG format bitDepth={bit_depth} colorType={color_type}")
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if width is None or height is None:
        raise SystemExit("missing PNG header")

    channels = 4 if color_type == 6 else 3
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))
    rows = []
    previous = [0] * stride
    cursor = 0
    for _y in range(height):
        filter_type = raw[cursor]
        cursor += 1
        row = list(raw[cursor:cursor + stride])
        cursor += stride
        recon = [0] * stride
        for index, value in enumerate(row):
            left = recon[index - channels] if index >= channels else 0
            up = previous[index]
            up_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                predicted = 0
            elif filter_type == 1:
                predicted = left
            elif filter_type == 2:
                predicted = up
            elif filter_type == 3:
                predicted = (left + up) // 2
            elif filter_type == 4:
                p = left + up - up_left
                pa = abs(p - left)
                pb = abs(p - up)
                pc = abs(p - up_left)
                predicted = left if pa <= pb and pa <= pc else up if pb <= pc else up_left
            else:
                raise SystemExit(f"unsupported PNG filter {filter_type}")
            recon[index] = (value + predicted) & 0xFF
        rows.append(recon)
        previous = recon
    return width, height, channels, rows


def black_pixel_ratio(path):
    width, height, channels, rows = read_png_rgb(path)
    black = 0
    total = width * height
    for row in rows:
        for x in range(width):
            index = x * channels
            r, g, b = row[index], row[index + 1], row[index + 2]
            if r < 6 and g < 6 and b < 6:
                black += 1
    return black / total


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    tmp = pathlib.Path("/tmp/EagleGridSaverVerify.library")
    if tmp.exists():
        shutil.rmtree(tmp)
    images = tmp / "images"
    images.mkdir(parents=True)

    colors = [(220, 60, 60), (60, 160, 220), (245, 180, 40), (80, 190, 110)]
    for idx, color in enumerate(colors):
        folder = images / f"ITEM{idx}.info"
        folder.mkdir()
        ppm = folder / f"item{idx}.ppm"
        jpg = folder / f"item{idx}.jpg"
        write_ppm(ppm, color)
        run(["sips", "-s", "format", "jpeg", str(ppm), "--out", str(jpg)], project)
        ppm.unlink()
        (folder / "metadata.json").write_text(json.dumps({
            "name": f"item{idx}",
            "width": 640,
            "height": 420,
        }))

    video_folder = images / "VIDEO.info"
    video_folder.mkdir()
    poster = video_folder / "video_thumbnail.jpg"
    write_ppm(video_folder / "video_thumbnail.ppm", (190, 80, 230))
    run(["sips", "-s", "format", "jpeg", str(video_folder / "video_thumbnail.ppm"), "--out", str(poster)], project)
    (video_folder / "video_thumbnail.ppm").unlink()
    missing_video = video_folder / "missing.mp4"
    missing_video.write_bytes(b"not a real video")
    (video_folder / "metadata.json").write_text(json.dumps({
        "name": "missing video",
        "width": 640,
        "height": 420,
    }))

    support = pathlib.Path.home() / "Library/Application Support/EagleGridSaver"
    cache = support / "DisplayCache"
    backup = pathlib.Path(tempfile.mkdtemp(prefix="EagleGridSaverCacheBackup-")) / "DisplayCache"
    defaults_backup = backup_defaults(project)
    had_cache = cache.exists()
    if had_cache:
        shutil.move(str(cache), str(backup))
    cache.mkdir(parents=True, exist_ok=True)

    run(["./Scripts/build.sh"], project)
    app = project / "dist/Eagle Grid Saver.app/Contents/MacOS/EagleGridSaverApp"
    # The app does not expose a CLI index command, so build a compatible manifest directly.
    items = []
    for file in sorted(images.glob("*.info/*")):
        if file.name == "metadata.json" or file.name.endswith(".ppm"):
            continue
        if file.suffix.lower() not in [".jpg", ".mp4"]:
            continue
        cache_name = f"4-verify-{file.stem}.jpg"
        output = cache / cache_name
        source = poster if file.suffix.lower() == ".mp4" else file
        shutil.copyfile(source, output)
        items.append({
            "cachePath": cache_name,
            "sourcePath": str(file) + ".does-not-exist" if file.suffix.lower() == ".mp4" else str(file),
            "title": file.stem,
            "width": 640,
            "height": 420,
            "isVideo": file.suffix.lower() == ".mp4",
        })

    (cache / "manifest.json").write_text(json.dumps({
        "version": "4",
            "libraryPath": "/Previous/Computer/Neo.library",
        "generatedAt": 0,
        "items": items,
    }))

    try:
        subprocess.run(["defaults", "write", "com.chaopi.EagleGridSaver", "EagleGridSaver.libraryPath", str(tmp)], check=True)
        output_png = project / "outputs/verify-no-black-tiles.png"
        output_png.parent.mkdir(exist_ok=True)
        run(["clang", "-fobjc-arc", "-framework", "Cocoa", "-framework", "QuartzCore", "-framework", "ScreenSaver", "Scripts/render_preview.m", "-o", "dist/render_preview"], project)
        ratios = []
        for frames in (80, 420, 900):
            frame_png = output_png.with_name(f"{output_png.stem}-{frames}.png")
            run(["dist/render_preview", "dist/EagleGridSaver.saver", str(frame_png), str(frames)], project)
            ratio = black_pixel_ratio(frame_png)
            ratios.append(ratio)
            print(f"frames={frames} black_pixel_ratio={ratio:.6f} output={frame_png}")
        if max(ratios) > 0.01:
            raise SystemExit("black tile check failed")
    finally:
        restore_defaults(project, defaults_backup)
        shutil.rmtree(cache, ignore_errors=True)
        if had_cache:
            shutil.move(str(backup), str(cache))


if __name__ == "__main__":
    main()
