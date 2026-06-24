#!/usr/bin/env python3
import pathlib
import subprocess
import struct
import zlib


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


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


def black_stats(path):
    width, height, channels, rows = read_png_rgb(path)
    black = [[False] * width for _ in range(height)]
    black_count = 0
    for y, row in enumerate(rows):
        for x in range(width):
            index = x * channels
            r, g, b = row[index], row[index + 1], row[index + 2]
            is_black = r < 8 and g < 8 and b < 8
            black[y][x] = is_black
            if is_black:
                black_count += 1

    visited = [[False] * width for _ in range(height)]
    largest = 0
    for y in range(height):
        for x in range(width):
            if visited[y][x] or not black[y][x]:
                continue
            stack = [(x, y)]
            visited[y][x] = True
            size = 0
            while stack:
                cx, cy = stack.pop()
                size += 1
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and not visited[ny][nx] and black[ny][nx]:
                        visited[ny][nx] = True
                        stack.append((nx, ny))
            largest = max(largest, size)

    total = width * height
    return black_count / total, largest / total


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    outputs = project / "outputs"
    outputs.mkdir(exist_ok=True)

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

    cases = [
        ("wide-early", 80, 3008, 1692),
        ("wide-mid", 420, 3008, 1692),
        ("wide-late", 900, 3008, 1692),
        ("studio-early", 80, 2560, 1440),
        ("studio-late", 900, 2560, 1440),
    ]
    for name, frames, width, height in cases:
        path = outputs / f"render-{name}.png"
        run(["dist/render_preview", "dist/EagleGridSaver.saver", str(path), str(frames), "full", str(width), str(height)], project)
        black_ratio, largest_black_component = black_stats(path)
        print(f"{name} black_ratio={black_ratio:.6f} largest_black_component={largest_black_component:.6f} output={path}")
    print("rendered screenshot samples written for visual review")


if __name__ == "__main__":
    main()
