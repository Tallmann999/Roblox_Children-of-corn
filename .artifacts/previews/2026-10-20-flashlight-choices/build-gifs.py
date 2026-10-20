"""Assemble unmodified native Roblox preview crops into three labelled GIFs.

Input: capture-metadata.json and mode-N/frame-*.jpg (or PNG) in this folder.
Only the explicit central capture ROI is used. Captions sit outside that ROI.
No exposure, contrast, glow, simulated light, interpolation or motion is added.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont, ImageOps


HERE = Path(__file__).resolve().parent
DEFAULT_TITLES = (
    "1. Узкий направленный луч",
    "2. Луч с мягкими краями",
    "3. Широкий свет фонаря",
)
FONT_PATHS = (
    Path("C:/Windows/Fonts/arial.ttf"),
    Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_PATHS:
        if path.is_file():
            return ImageFont.truetype(str(path), size)
    raise FileNotFoundError("A Cyrillic-capable Arial or DejaVu Sans font is required")


def get_mode_metadata(metadata: dict[str, Any], number: int) -> dict[str, Any]:
    modes = metadata.get("modes", [])
    if isinstance(modes, dict):
        return dict(modes.get(str(number), modes.get(f"mode-{number}", {})))
    for item in modes:
        if str(item.get("id", item.get("mode", ""))).removeprefix("mode-") == str(number):
            return dict(item)
    if len(modes) >= number:
        return dict(modes[number - 1])
    return {}


def source_frames(folder: Path) -> list[Path]:
    paths = sorted(
        path
        for path in folder.glob("frame-*")
        if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
    )
    if len(paths) < 2:
        raise ValueError(f"At least two native frames are required in {folder}")
    return paths


def roi_for(metadata: dict[str, Any], mode: dict[str, Any], size: tuple[int, int]) -> tuple[int, int, int, int]:
    roi = mode.get("roi", metadata.get("roi"))
    if isinstance(roi, (list, tuple)) and len(roi) == 4:
        box = tuple(int(value) for value in roi)
    else:
        roi_dict = roi if isinstance(roi, dict) else {}
        width = int(roi_dict.get("width", mode.get("roi_width", metadata.get("roi_width", 640))))
        height = int(roi_dict.get("height", mode.get("roi_height", metadata.get("roi_height", 360))))
        x = int(roi_dict.get("x", (size[0] - width) // 2))
        y = int(roi_dict.get("y", (size[1] - height) // 2))
        box = (x, y, x + width, y + height)
    if not (0 <= box[0] < box[2] <= size[0] and 0 <= box[1] < box[3] <= size[1]):
        raise ValueError(f"Capture ROI {box} is outside native image dimensions {size}")
    return box


def label_frame(image: Image.Image, title: str) -> Image.Image:
    bar_height = max(34, round(image.width * 0.061))
    result = Image.new("RGB", (image.width, image.height + bar_height), (12, 14, 17))
    result.paste(image, (0, 0))
    draw = ImageDraw.Draw(result)
    label_font = font(max(15, round(image.width * 0.031)))
    while draw.textbbox((0, 0), title, font=label_font)[2] > image.width - 24:
        label_font = font(label_font.size - 1)
    draw.text((12, image.height + bar_height // 2), title, font=label_font, fill=(229, 232, 235), anchor="lm")
    return result


def make_global_palette(all_frames: list[Image.Image]) -> Image.Image:
    # Every frame contributes equally; one palette prevents adaptive colour flicker.
    sample_size = (160, 100)
    samples = Image.new("RGB", (sample_size[0] * 8, sample_size[1] * ((len(all_frames) + 7) // 8)))
    for index, frame in enumerate(all_frames):
        thumb = ImageOps.contain(frame, sample_size, Image.Resampling.LANCZOS)
        samples.paste(thumb, ((index % 8) * sample_size[0], (index // 8) * sample_size[1]))
    return samples.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def durations(count: int, metadata: dict[str, Any], mode: dict[str, Any]) -> list[int]:
    explicit = mode.get("frame_durations_ms", metadata.get("frame_durations_ms"))
    if explicit is not None:
        if len(explicit) != count:
            raise ValueError("frame_durations_ms must match native frame count")
        return [max(20, round(float(value) / 10) * 10) for value in explicit]
    fps = float(mode.get("fps", metadata.get("fps", count / 2.8)))
    if not 0 < fps <= 50:
        raise ValueError("GIF fps must be finite, positive and at most 50")
    # GIF times are 10-ms ticks. Distribute rounding instead of accumulating drift.
    boundaries = [round(index * 100 / fps) * 10 for index in range(count + 1)]
    return [max(20, boundaries[index + 1] - boundaries[index]) for index in range(count)]


def verify_gif(path: Path, expected_frames: int, expected_duration: int, expected_size: tuple[int, int]) -> dict[str, Any]:
    with Image.open(path) as image:
        if image.size != expected_size or image.info.get("loop") != 0:
            raise AssertionError(f"Incorrect GIF dimensions or looping: {path}")
        duration = 0
        image_hashes: list[str] = []
        for index in range(image.n_frames):
            image.seek(index)
            duration += int(image.info.get("duration", 0))
            image_hashes.append(hashlib.sha256(image.convert("RGB").tobytes()).hexdigest())
        if duration != expected_duration:
            raise AssertionError(f"GIF duration changed: {duration} vs {expected_duration}")
        if len(set(image_hashes)) < 2:
            raise AssertionError(f"Preview is static: {path}")
        if image.n_frames > expected_frames:
            raise AssertionError(f"Unexpected generated frames: {path}")
        return {
            "decoded_frames": image.n_frames,
            "distinct_decoded_frames": len(set(image_hashes)),
            "duration_ms": duration,
            "loop": image.info.get("loop"),
            "dimensions": list(image.size),
        }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=HERE)
    args = parser.parse_args()
    directory = args.directory.resolve()
    metadata_path = directory / "capture-metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8-sig"))
    built: list[dict[str, Any]] = []
    all_frames: list[Image.Image] = []
    for number in range(1, 4):
        mode = get_mode_metadata(metadata, number)
        titles = metadata.get("titles", DEFAULT_TITLES)
        title = str(mode.get("title", titles[number - 1]))
        paths = source_frames(directory / f"mode-{number}")
        frames: list[Image.Image] = []
        source_records = []
        for path in paths:
            with Image.open(path) as image:
                box = roi_for(metadata, mode, image.size)
                cropped = image.convert("RGB").crop(box)
                source_records.append({"file": str(path.relative_to(directory)), "sha256": digest(path), "native_size": list(image.size), "crop_box": list(box)})
                frames.append(label_frame(cropped, title))
        if len({frame.size for frame in frames}) != 1:
            raise ValueError(f"Native cropped frame dimensions vary in mode {number}")
        timing = durations(len(frames), metadata, mode)
        built.append({"number": number, "title": title, "frames": frames, "timing": timing, "sources": source_records})
        all_frames.extend(frames)
    palette = make_global_palette(all_frames)
    reports = []
    for mode in built:
        output = directory / f"option-{mode['number']}.gif"
        quantized = [frame.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for frame in mode["frames"]]
        quantized[0].save(output, format="GIF", save_all=True, append_images=quantized[1:], duration=mode["timing"], loop=0, disposal=1, optimize=False)
        verification = verify_gif(output, len(quantized), sum(mode["timing"]), quantized[0].size)
        reports.append({"option": mode["number"], "title": mode["title"], "file": output.name, "bytes": output.stat().st_size, "sha256": digest(output), "native_input_frames": len(quantized), "verification": verification, "sources": mode["sources"]})
    panel_width = 480
    panel_height = 0
    panels = []
    for mode in built:
        selected = [mode["frames"][0], mode["frames"][len(mode["frames"]) // 2]]
        thumbs = [ImageOps.contain(frame, (panel_width, 330), Image.Resampling.LANCZOS) for frame in selected]
        height = sum(frame.height for frame in thumbs)
        panel = Image.new("RGB", (panel_width, height), (12, 14, 17))
        y = 0
        for thumb in thumbs:
            panel.paste(thumb, ((panel_width - thumb.width) // 2, y))
            y += thumb.height
        panels.append(panel)
        panel_height = max(panel_height, height)
    sheet = Image.new("RGB", (panel_width * 3, panel_height), (12, 14, 17))
    for index, panel in enumerate(panels):
        sheet.paste(panel, (index * panel_width, 0))
    sheet_path = directory / "contact-sheet.png"
    sheet.save(sheet_path)
    manifest = {
        "complete": True,
        "kind": "Illustrative 3D flashlight choice previews; not Roblox runtime captures" if metadata.get("illustrative") else "native Roblox runtime flashlight choice previews",
        "processing": "World-space spotlight illustrations from render-illustrative-previews.py; exact frame ROI plus external caption; common 256-colour GIF palette" if metadata.get("illustrative") else "Exact native ROI crop plus external caption; common 256-colour GIF palette; no synthetic lighting or exposure changes",
        "metadata_sha256": digest(metadata_path),
        "options": reports,
        "contact_sheet": {"file": sheet_path.name, "sha256": digest(sheet_path), "dimensions": list(sheet.size)},
    }
    manifest_path = directory / "gif-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"complete": True, "options": [{key: item[key] for key in ("option", "file", "bytes", "verification")} for item in reports], "manifest": str(manifest_path), "contact_sheet": str(sheet_path)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
