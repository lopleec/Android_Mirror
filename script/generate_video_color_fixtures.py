#!/usr/bin/env python3
"""Generate synthetic 8-bit grayscale H.264 regression fixtures (requires FFmpeg/libx264)."""
import os
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
ffmpeg = os.environ.get("FFMPEG") or shutil.which("ffmpeg")
if not ffmpeg:
    raise SystemExit("FFmpeg with libx264 is required to regenerate the fixtures.")
width, height = 256, 32
for name, minimum, span, video_range in [
    ("gradient-limited", 16, 219, "tv"),
    ("gradient-full", 0, 255, "pc"),
]:
    # Feed YUV directly: no RGB conversion or unrelated phone data enters these fixtures.
    row = bytes(minimum + round(span * x / (width - 1)) for x in range(width))
    frame = row * height + bytes([128]) * (width * height // 2)
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo",
        "-pixel_format", "yuv420p", "-video_size", f"{width}x{height}", "-i", "pipe:0",
        "-frames:v", "1", "-c:v", "libx264", "-profile:v", "high", "-qp", "1", "-preset", "veryslow",
        "-color_range", video_range, "-colorspace", "bt709", "-color_primaries", "bt709",
        "-color_trc", "bt709", "-f", "h264",
        str(root / "Tests/AndroidMirrorTests/Fixtures" / f"{name}.h264"),
    ], input=frame, check=True)
