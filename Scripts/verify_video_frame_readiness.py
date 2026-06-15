#!/usr/bin/env python3
import pathlib
import re


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    source = project / "Sources/EagleGridSaverObjC/EagleGridSaverView.m"
    text = source.read_text()

    match = re.search(
        r"- \(BOOL\)videoHasRenderableFrameForCell:\(EagleCell \*\)cell \{(?P<body>.*?)\n\}",
        text,
        re.S,
    )
    if match is None:
        raise SystemExit("videoHasRenderableFrameForCell not found")

    body = match.group("body")
    if "averageBrightnessForPixelBuffer" in body or "brightness >=" in body:
        raise SystemExit("video frame readiness still rejects dark but valid frames")
    if "copyPixelBufferForItemTime" not in body or "return YES" not in body:
        raise SystemExit("video frame readiness does not require an actual decoded frame")

    print("video_frame_readiness=ok")


if __name__ == "__main__":
    main()
