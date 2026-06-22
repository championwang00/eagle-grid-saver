#!/usr/bin/env python3
import pathlib
import re


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    source = project / "Sources/EagleGridSaverObjC/EagleGridSaverView.m"
    text = source.read_text()

    required_symbols = [
        "MaxActiveVideoPlayers",
        "ImageCacheTotalCostLimit",
        "MinDynamicDecodePixelSize",
        "MaxDynamicDecodePixelSize",
        "maxVisibleCellsForCurrentLayout",
        "decodeMaxPixelSizeForCell",
        "clearLayerImageForCell",
        "cacheCostForImage",
        "removeAllObjects",
    ]
    missing = [symbol for symbol in required_symbols if symbol not in text]
    if missing:
        raise SystemExit("missing memory guard symbols: " + ", ".join(missing))

    active_video_match = re.search(r"MaxActiveVideoPlayers\s*=\s*(\d+)", text)
    if active_video_match is None or int(active_video_match.group(1)) > 2:
        raise SystemExit("active video player limit must be present and <= 2")

    if "setObject:image forKey:cell.artwork.url cost:" not in text:
        raise SystemExit("image cache must store decoded images with memory cost")

    retained_image_assignments = [
        "cell.image = cached",
        "cell.image = image",
        "candidate.image = image",
    ]
    found_assignments = [assignment for assignment in retained_image_assignments if assignment in text]
    if found_assignments:
        raise SystemExit("cells must not retain decoded NSImage objects: " + ", ".join(found_assignments))

    if "cell.artwork.videoURL == nil || cell.videoPlaybackFailed || cell.image == nil" in text:
        raise SystemExit("video startup must not depend on retained cell.image")

    if "self.imageCache.totalCostLimit" not in text:
        raise SystemExit("image cache total cost limit is not configured")

    cache_limit_match = re.search(r"ImageCacheTotalCostLimit\s*=\s*(\d+)\s*\*\s*1024\s*\*\s*1024", text)
    if cache_limit_match is None or int(cache_limit_match.group(1)) > 96:
        raise SystemExit("image cache total cost limit must be <= 96 MB")

    max_decode_match = re.search(r"MaxDynamicDecodePixelSize\s*=\s*(\d+)\.0", text)
    if max_decode_match is None or int(max_decode_match.group(1)) > 900:
        raise SystemExit("dynamic decode max pixel size must be <= 900")

    if "decodedImageForArtwork:cell.artwork maxPixelSize:[self decodeMaxPixelSizeForCell:cell]" not in text:
        raise SystemExit("cell image decode must use the cell-specific pixel cap")

    if "cell.contentLayer.contents = nil" not in text:
        raise SystemExit("reused cells must clear old layer contents")

    if "maxVisibleCells = [self maxVisibleCellsForCurrentLayoutWithColumns:columns" not in text:
        raise SystemExit("layout still uses a fixed global cell cap")

    print("memory_guards=ok")


if __name__ == "__main__":
    main()
