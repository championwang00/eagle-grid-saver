#!/usr/bin/env python3
import pathlib


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    source = project / "Sources/EagleGridSaverObjC/EagleGridSaverView.m"
    text = source.read_text()

    required_symbols = [
        "VideoReadinessProbeInterval",
        "videoReadinessLastProbeTime",
        "videoReadinessLastProbeResult",
        "VideoUpdateInterval",
        "lastVideoUpdateTime",
    ]
    missing = [symbol for symbol in required_symbols if symbol not in text]
    if missing:
        raise SystemExit("missing scroll performance guard symbols: " + ", ".join(missing))

    if "[self prepareImageForCell:cell synchronously:YES]" not in text:
        raise SystemExit("visible recycled cells must synchronously prepare an image to avoid black tiles")

    if "synchronously:[self shouldPrepareCellSynchronously:cell]" not in text:
        raise SystemExit("new prefill cells must only synchronously prepare when they are visible")

    if "copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL" not in text:
        raise SystemExit("video readiness must still verify a real renderable frame before showing video")

    probe_position = text.find("copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL")
    guard_position = text.find("VideoReadinessProbeInterval")
    if guard_position == -1 or guard_position > probe_position:
        raise SystemExit("video pixel-buffer probing must be guarded before copying pixel buffers")

    print("scroll_performance_guards=ok")


if __name__ == "__main__":
    main()
