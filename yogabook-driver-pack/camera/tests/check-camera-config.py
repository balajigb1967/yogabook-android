#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Validate Yoga Book camera profiles without runtime camera dependencies."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


CAMERAS = {
    "front": {
        "input": 0,
        "sensor": "ov2740",
        "size": (1920, 1080),
        "capture_size": (1932, 1092),
        "bayer_format": "bggr10le",
        "kernel_bayer_formats": {
            "BG10": "bggr10le",
            "BA10": "grbg10le",
        },
    },
    "rear": {
        "input": 1,
        "sensor": "ov8858",
        "size": (1616, 1208),
        "capture_size": (1632, 1224),
        "bayer_format": "bggr10le",
        "kernel_bayer_formats": {"BG10": "bggr10le"},
    },
}
REQUIRED_CONTROLS = ("exposure", "analogue_gain", "digital_gain")
REQUIRED_PROCESSING = (
    "contrast",
    "saturation",
    "gamma",
    "rgb_red",
    "rgb_green",
    "rgb_blue",
    "denoise_spatial",
    "denoise_temporal",
    "target_luma",
    "target_red_green",
    "target_blue_green",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def number(value: Any, label: str) -> float:
    require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} must be numeric")
    return float(value)


def validate_profile(name: str, profile: dict[str, Any]) -> None:
    expected = CAMERAS[name]
    require(profile.get("input") == expected["input"], f"{name}: incorrect AtomISP input")
    require(profile.get("sensor") == expected["sensor"], f"{name}: incorrect sensor")
    require(
        (profile.get("width"), profile.get("height")) == expected["size"],
        f"{name}: incorrect streaming size",
    )
    require(
        profile.get("bayer_format") == expected["bayer_format"],
        f"{name}: incorrect Bayer order",
    )
    require(
        profile.get("kernel_bayer_formats") == expected["kernel_bayer_formats"],
        f"{name}: incorrect kernel Bayer format mapping",
    )
    require(
        (profile.get("capture_width"), profile.get("capture_height"))
        == expected["capture_size"],
        f"{name}: incorrect raw transport size",
    )

    width = int(profile["width"])
    capture_width = int(profile["capture_width"])
    stride = int(profile["bytes_per_line"])
    require(stride >= capture_width * 2, f"{name}: Bayer stride is smaller than a row")
    require(stride % 32 == 0, f"{name}: Bayer stride is not 32-byte aligned")
    require(profile.get("output_width") == 1280, f"{name}: output width must be 1280")
    require(profile.get("output_height") == 720, f"{name}: output height must be 720")

    controls = profile.get("sensor_controls")
    ranges = profile.get("control_ranges")
    require(isinstance(controls, dict), f"{name}: sensor_controls must be an object")
    require(isinstance(ranges, dict), f"{name}: control_ranges must be an object")
    for control in REQUIRED_CONTROLS:
        require(control in controls, f"{name}: missing {control} default")
        require(control in ranges, f"{name}: missing {control} range")
        bounds = ranges[control]
        require(
            isinstance(bounds, list) and len(bounds) == 2 and bounds[0] <= bounds[1],
            f"{name}: invalid {control} range",
        )
        require(
            bounds[0] <= controls[control] <= bounds[1],
            f"{name}: {control} default is outside its range",
        )

    processing = profile.get("processing")
    require(isinstance(processing, dict), f"{name}: processing must be an object")
    for key in REQUIRED_PROCESSING:
        require(key in processing, f"{name}: missing processing.{key}")
        number(processing[key], f"{name}: processing.{key}")
    require(0.0 < processing["target_luma"] < 1.0, f"{name}: invalid target luma")
    require(0.0 < processing["target_red_green"] < 2.0, f"{name}: invalid R/G target")
    require(0.0 < processing["target_blue_green"] < 2.0, f"{name}: invalid B/G target")

    if name == "front":
        require(profile.get("bytes_per_line") == 4096, "front: incorrect raw transport stride")
        require(controls.get("red_balance") == 1024, "front: sensor red balance must remain at unity")
        require(controls.get("blue_balance") == 1024, "front: sensor blue balance must remain at unity")
    else:
        require(
            controls["analogue_gain"] == 2047,
            "rear: initial analogue gain must match the physically validated maximum",
        )
        require(
            controls["digital_gain"] == 4095,
            "rear: initial digital gain must match the physically validated maximum",
        )
        require(
            ranges["digital_gain"] == [1024, 4095],
            "rear: digital gain range must match the OV8858 MWB control",
        )
        require(
            processing["gamma"] == 2.0,
            "rear: gamma must match the physically measured indoor candidate",
        )
        require(
            (
                processing["rgb_red"],
                processing["rgb_green"],
                processing["rgb_blue"],
            )
            == (0.65, 0.5, 0.6),
            "rear: RGB gains must match the same-frame neutral candidate",
        )
        still = profile.get("still")
        require(isinstance(still, dict), "rear: still must be an object")
        require(
            (still.get("width"), still.get("height")) == (3248, 2432),
            "rear: full-resolution still size must be 3248x2432",
        )
        require(
            (still.get("capture_width"), still.get("capture_height")) == (3264, 2448),
            "rear: incorrect full-resolution raw transport size",
        )
        require(still.get("bytes_per_line") == 6656, "rear: incorrect full-resolution stride")
        require(still.get("bayer_format") == "bggr10le", "rear: still must use BGGR10LE")
        require(1 <= still.get("jpeg_quality", 0) <= 100, "rear: invalid JPEG quality")
        require(
            10 <= still.get("focus_settle_ms", 0) <= 2000,
            "rear: invalid focus settling interval",
        )
        positions = still.get("focus_positions")
        require(isinstance(positions, list) and positions, "rear: focus scan is empty")
        require(
            positions == sorted(set(positions)) and all(0 <= value <= 1023 for value in positions),
            "rear: focus positions must be unique, sorted and within 0..1023",
        )
        require(still.get("focus_fine_radius", 0) > 0, "rear: invalid fine-focus radius")
        require(still.get("focus_fine_step", 0) > 0, "rear: invalid fine-focus step")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    arguments = parser.parse_args()
    with arguments.config.open(encoding="utf-8") as stream:
        config = json.load(stream)
    require(isinstance(config, dict), "configuration root must be an object")
    require(set(config) == set(CAMERAS), "configuration must contain exactly front and rear")
    for name in CAMERAS:
        require(isinstance(config[name], dict), f"{name}: profile must be an object")
        validate_profile(name, config[name])
    print("Yoga Book camera configuration: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
