#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture a full-resolution rear-camera JPEG with contrast autofocus."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import time
from typing import Any

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst

from yogabook_camera import (
    command,
    configure_hardware,
    discover_sensor_subdevice,
    load_config,
    normalized_bayer_buffer,
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture a full-resolution Yoga Book rear-camera JPEG"
    )
    parser.add_argument("output", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--capture-device", default="/dev/video0")
    parser.add_argument("--media-device", default="/dev/media0")
    parser.add_argument("--focus-position", type=int)
    parser.add_argument("--no-autofocus", action="store_true")
    return parser.parse_args()


class RearStillCapture:
    def __init__(self, arguments: argparse.Namespace, profile: dict[str, Any]):
        self.arguments = arguments
        self.profile = profile
        self.still = profile["still"]
        self.width = int(self.still["width"])
        self.height = int(self.still["height"])
        self.capture_width = int(self.still.get("capture_width", self.width))
        self.capture_height = int(self.still.get("capture_height", self.height))
        self.source_stride = int(self.still["bytes_per_line"])
        self.focus_settle_seconds = int(self.still["focus_settle_ms"]) / 1000
        caps = (
            f"video/x-bayer,format={self.still['bayer_format']},"
            f"width={self.capture_width},height={self.capture_height},framerate=30/1"
        )
        self.capture_description = (
            f"v4l2src device={arguments.capture_device} io-mode=2 do-timestamp=true ! "
            f"{caps} ! appsink name=capture sync=false max-buffers=1 drop=false"
        )
        self.lens_device = discover_sensor_subdevice(arguments.media_device, "wv517s")

    def _capture_once(self) -> Gst.Buffer:
        # AtomISP full-resolution capture is one-shot on this platform. Keeping
        # the stream alive while moving the WV517S lens stalls frame delivery,
        # so every focus sample gets a new pipeline after the lens is idle.
        capture = Gst.parse_launch(self.capture_description)
        sink = capture.get_by_name("capture")
        sample = None
        try:
            result = capture.set_state(Gst.State.PLAYING)
            if result == Gst.StateChangeReturn.FAILURE:
                raise RuntimeError("cannot start rear-camera capture pipeline")
            sample = sink.emit("try-pull-sample", 10 * Gst.SECOND)
            if sample is None:
                error = capture.get_bus().pop_filtered(Gst.MessageType.ERROR)
                if error:
                    parsed, debug = error.parse_error()
                    raise RuntimeError(f"rear capture failed: {parsed}: {debug or ''}")
                raise RuntimeError("timed out waiting for a rear-camera frame")
            normalized = normalized_bayer_buffer(
                sample.get_buffer(),
                width=self.width,
                height=self.height,
                capture_width=self.capture_width,
                capture_height=self.capture_height,
                source_stride=self.source_stride,
            )
            if normalized is None:
                raise RuntimeError("cannot normalize full-resolution rear Bayer frame")
            return normalized
        finally:
            capture.set_state(Gst.State.NULL)
            capture.get_state(5 * Gst.SECOND)
            sample = None
            sink = None

    def _set_focus(self, position: int) -> None:
        if not 0 <= position <= 1023:
            raise ValueError(f"focus position outside 0..1023: {position}")
        command(
            "v4l2-ctl",
            "-d",
            self.lens_device,
            f"--set-ctrl=focus_absolute={position}",
        )

    def _capture_at_focus(self, position: int) -> Gst.Buffer:
        self._set_focus(position)
        time.sleep(self.focus_settle_seconds)
        return self._capture_once()

    def _focus_metric(self, buffer: Gst.Buffer) -> float:
        mapped, info = buffer.map(Gst.MapFlags.READ)
        if not mapped:
            raise RuntimeError("cannot map rear Bayer frame for autofocus")
        try:
            data = memoryview(info.data)
            x_start = (self.width // 4) & ~1
            x_end = (self.width * 3 // 4) & ~1
            y_start = (self.height // 4) & ~1
            y_end = (self.height * 3 // 4) & ~1
            total = 0
            count = 0
            # Sample one of the two green BGGR planes. Two-pixel differences
            # compare the same color without requiring a demosaic operation.
            for y in range(y_start, y_end - 2, 4):
                row = y * self.width * 2
                next_row = (y + 2) * self.width * 2
                for x in range(x_start + 1, x_end - 2, 4):
                    offset = row + x * 2
                    right = offset + 4
                    below = next_row + x * 2
                    center_value = data[offset] | (data[offset + 1] << 8)
                    right_value = data[right] | (data[right + 1] << 8)
                    below_value = data[below] | (data[below + 1] << 8)
                    total += abs(center_value - right_value)
                    total += abs(center_value - below_value)
                    count += 2
            return total / max(count, 1)
        finally:
            buffer.unmap(info)

    def _scan(self, positions: list[int]) -> tuple[int, float]:
        best_position = positions[0]
        best_metric = -1.0
        for position in positions:
            frame = self._capture_at_focus(position)
            metric = self._focus_metric(frame)
            print(f"CAMERA_AF position={position} metric={metric:.3f}", flush=True)
            if metric > best_metric:
                best_position = position
                best_metric = metric
        return best_position, best_metric

    def autofocus(self) -> int:
        positions = [int(value) for value in self.still["focus_positions"]]
        coarse_position, _ = self._scan(positions)
        radius = int(self.still["focus_fine_radius"])
        step = int(self.still["focus_fine_step"])
        fine_positions = list(
            range(max(0, coarse_position - radius), min(1023, coarse_position + radius) + 1, step)
        )
        fine_position, metric = self._scan(fine_positions)
        print(
            f"CAMERA_AF_RESULT position={fine_position} metric={metric:.3f}",
            flush=True,
        )
        return fine_position

    def capture_frame(self) -> Gst.Buffer:
        if self.arguments.focus_position is not None:
            focus_position = self.arguments.focus_position
        elif self.arguments.no_autofocus:
            focus_position = 300
        else:
            focus_position = self.autofocus()
        return self._capture_at_focus(focus_position)

    def encode(self, frame: Gst.Buffer, destination: Path) -> None:
        processing = self.profile["processing"]
        quality = int(self.still["jpeg_quality"])
        caps = (
            f"video/x-bayer,format={self.still['bayer_format']},"
            f"width={self.width},height={self.height},framerate=1/1"
        )
        pipeline = Gst.parse_launch(
            f"appsrc name=source is-live=false format=time caps=\"{caps}\" ! "
            "bayer2rgb ! videoconvert n-threads=4 ! "
            f"videobalance contrast={processing['contrast']} brightness=0.0 "
            f"saturation={processing['saturation']} ! "
            f"gamma gamma={processing['gamma']} ! "
            "videoconvert n-threads=4 ! video/x-raw,format=RGBA ! "
            f"frei0r-filter-coloradj-rgb action=1.0 r={processing['rgb_red']} "
            f"g={processing['rgb_green']} b={processing['rgb_blue']} keep-luma=false ! "
            f"frei0r-filter-hqdn3d spatial={processing['denoise_spatial']} "
            f"temporal={processing['denoise_temporal']} ! "
            "videoconvert n-threads=4 ! video/x-raw,format=I420 ! "
            f"jpegenc quality={quality} ! filesink name=output"
        )
        source = pipeline.get_by_name("source")
        pipeline.get_by_name("output").set_property("location", str(destination))
        if pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("cannot start rear JPEG encoder")
        try:
            flow = source.emit("push-buffer", frame)
            if flow != Gst.FlowReturn.OK:
                raise RuntimeError(f"rear JPEG encoder rejected frame: {flow.value_nick}")
            source.emit("end-of-stream")
            message = pipeline.get_bus().timed_pop_filtered(
                30 * Gst.SECOND,
                Gst.MessageType.ERROR | Gst.MessageType.EOS,
            )
            if message is None:
                raise RuntimeError("timed out encoding rear JPEG")
            if message.type == Gst.MessageType.ERROR:
                error, debug = message.parse_error()
                raise RuntimeError(f"rear JPEG encoding failed: {error}: {debug or ''}")
        finally:
            pipeline.set_state(Gst.State.NULL)


def capture_to_path(arguments: argparse.Namespace, profile: dict[str, Any]) -> Path:
    destination = arguments.output.expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.tmp")
    temporary.unlink(missing_ok=True)
    os.environ.setdefault("GST_GL_PLATFORM", "egl")
    os.environ.setdefault("GST_GL_WINDOW", "surfaceless")
    os.environ.setdefault("GST_GL_API", "gles2")
    Gst.init(None)
    configure_hardware(arguments.capture_device, arguments.media_device, profile)
    capture = RearStillCapture(arguments, profile)
    try:
        frame = capture.capture_frame()
        capture.encode(frame, temporary)
        if temporary.stat().st_size < 100_000:
            raise RuntimeError(f"encoded JPEG is unexpectedly small: {temporary.stat().st_size} bytes")
        temporary.replace(destination)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    print(f"CAMERA_STILL path={destination} bytes={destination.stat().st_size}")
    return destination


def main() -> int:
    arguments = parse_arguments()
    profile = load_config(arguments.config, "rear")
    capture_to_path(arguments, profile)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error
