#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Raw Bayer userspace ISP for Lenovo Yoga Book YB1-X91L cameras."""

from __future__ import annotations

import argparse
import ctypes
import gc
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import struct
import sys
import time
from typing import Any

import gi

gi.require_version("Gst", "1.0")
from gi.repository import GLib, Gst


DEFAULT_CONFIG_PATHS = (
    Path("/etc/yogabook-camera/cameras.json"),
    Path(__file__).resolve().parents[1] / "config" / "cameras.json",
)

ACTIVE_POLL_INTERVAL_MS = 1000
IDLE_POLL_INTERVAL_MS = 5000
DEFAULT_IDLE_DELAY_SECONDS = 3.0
DEFAULT_MAX_TEMPERATURE_CELSIUS = 85.0
DEFAULT_RESUME_TEMPERATURE_CELSIUS = 75.0
DEFAULT_THERMAL_ROOT = Path("/sys/class/thermal")
INTERVIDEO_LAST_FRAME_TIMEOUT_NS = 365 * 24 * 60 * 60 * 1_000_000_000
IN_CLOSE_WRITE = 0x00000008
IN_CLOSE_NOWRITE = 0x00000010
IN_OPEN = 0x00000020
IN_Q_OVERFLOW = 0x00004000
INOTIFY_EVENT = struct.Struct("iIII")

FRONT_FRAGMENT_SHADER = r"""
precision mediump float;
varying vec2 v_texcoord;
uniform sampler2D tex;
void main() {
    vec4 pixel = texture2D(tex, v_texcoord);
    vec2 texel = vec2(1.0 / 1280.0, 1.0 / 720.0);
    vec3 neighbours =
        texture2D(tex, v_texcoord + vec2(texel.x, 0.0)).rgb +
        texture2D(tex, v_texcoord - vec2(texel.x, 0.0)).rgb +
        texture2D(tex, v_texcoord + vec2(0.0, texel.y)).rgb +
        texture2D(tex, v_texcoord - vec2(0.0, texel.y)).rgb;
    vec3 c = pixel.rgb + 0.16 * (pixel.rgb - 0.25 * neighbours);

    /* Correct the measured OV2740 left-edge color shading. */
    float left = clamp((0.55 - v_texcoord.x) / 0.55, 0.0, 1.0);
    float right = clamp((v_texcoord.x - 0.55) / 0.45, 0.0, 1.0);
    c *= vec3(1.0 + 0.17 * left + 0.15 * right,
              1.0 + 0.10 * left,
              1.0 - 0.12 * right);

    /* Preserve neutral tones while removing excess blue from warm colors. */
    c.b -= 0.70 * max(c.r - c.g, 0.0);

    gl_FragColor = vec4(clamp(c, 0.0, 1.0), pixel.a);
}
"""

IDENTITY_FRAGMENT_SHADER = r"""
precision mediump float;
varying vec2 v_texcoord;
uniform sampler2D tex;
void main() {
    gl_FragColor = texture2D(tex, v_texcoord);
}
"""


def notify_systemd(message: str) -> None:
    address = os.environ.get("NOTIFY_SOCKET")
    if not address:
        return
    if address.startswith("@"):
        address = f"\0{address[1:]}"
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notifier:
        notifier.connect(address)
        notifier.sendall(message.encode())


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Expose a corrected Yoga Book camera through V4L2 loopback"
    )
    parser.add_argument("--camera", choices=("auto", "front", "rear"), default="auto")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--capture-device", default="/dev/video0")
    parser.add_argument("--front-output-device", default="/dev/video10")
    parser.add_argument("--rear-output-device", default="/dev/video11")
    parser.add_argument("--media-device", default="/dev/media0")
    parser.add_argument(
        "--switch-dwell",
        type=float,
        default=1.0,
        help="seconds a single virtual camera must remain open before switching",
    )
    parser.add_argument(
        "--idle-delay",
        type=float,
        default=DEFAULT_IDLE_DELAY_SECONDS,
        help="seconds without a camera client before suspending image processing",
    )
    parser.add_argument(
        "--max-temperature",
        type=float,
        default=DEFAULT_MAX_TEMPERATURE_CELSIUS,
        help="highest system temperature allowed while camera processing is active",
    )
    parser.add_argument(
        "--resume-temperature",
        type=float,
        default=DEFAULT_RESUME_TEMPERATURE_CELSIUS,
        help="temperature below which a thermally suspended camera may resume",
    )
    parser.add_argument("--no-auto", action="store_true", help="disable adaptive tone and white balance")
    parser.add_argument("--print-pipeline", action="store_true")
    return parser.parse_args()


def load_config(path: Path | None, camera: str) -> dict[str, Any]:
    candidates = (path,) if path else DEFAULT_CONFIG_PATHS
    for candidate in candidates:
        if candidate and candidate.is_file():
            with candidate.open(encoding="utf-8") as stream:
                data = json.load(stream)
            try:
                return data[camera]
            except KeyError as error:
                raise SystemExit(f"camera profile {camera!r} is missing from {candidate}") from error
    rendered = ", ".join(str(item) for item in candidates if item)
    raise SystemExit(f"camera configuration not found; checked: {rendered}")


def resolve_camera(camera: str) -> str:
    if camera != "auto":
        return camera
    selection = selection_path()
    try:
        selected = selection.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return "front"
    if selected not in ("front", "rear"):
        raise SystemExit(f"invalid camera selection in {selection}: {selected!r}")
    return selected


def selection_path() -> Path:
    root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return root / "yogabook-camera" / "active-camera"


def persist_camera(camera: str) -> None:
    destination = selection_path()
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(f"{camera}\n", encoding="utf-8")
    temporary.replace(destination)


def runtime_camera_path() -> Path:
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    return runtime / "yogabook-camera" / "active-camera"


def publish_runtime_camera(camera: str) -> None:
    destination = runtime_camera_path()
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(f"{camera}\n", encoding="utf-8")
    temporary.replace(destination)


def externally_open_cameras(
    devices: dict[str, str],
    *,
    proc_root: Path = Path("/proc"),
    own_pid: int | None = None,
) -> set[str]:
    """Return camera endpoints held open outside the processor itself."""
    if own_pid is None:
        own_pid = os.getpid()
    device_paths = {
        str(Path(device).resolve(strict=True)): camera
        for camera, device in devices.items()
    }
    own_uid = os.getuid()
    opened: set[str] = set()
    try:
        processes = tuple(proc_root.iterdir())
    except OSError:
        return opened
    for process in processes:
        if not process.name.isdecimal() or int(process.name) == own_pid:
            continue
        try:
            if process.stat().st_uid != own_uid:
                continue
        except OSError:
            continue
        try:
            descriptors = tuple((process / "fd").iterdir())
        except OSError:
            continue
        for descriptor in descriptors:
            try:
                target = os.readlink(descriptor)
            except OSError:
                continue
            camera = device_paths.get(target)
            if camera:
                opened.add(camera)
    return opened


class CameraClientMonitor:
    """Track loopback clients from inotify open/close events."""

    def __init__(self, devices: dict[str, str]):
        libc = ctypes.CDLL(None, use_errno=True)
        descriptor = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if descriptor < 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error))
        self.descriptor = descriptor
        self.source_id: int | None = None
        self.cameras_by_watch: dict[int, str] = {}
        self.open_counts = {camera: 0 for camera in devices}
        try:
            for camera, device in devices.items():
                watch = libc.inotify_add_watch(
                    descriptor,
                    os.fsencode(device),
                    IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE,
                )
                if watch < 0:
                    error = ctypes.get_errno()
                    raise OSError(error, f"cannot watch {device}: {os.strerror(error)}")
                self.cameras_by_watch[watch] = camera
        except Exception:
            os.close(descriptor)
            raise

    @property
    def opened(self) -> set[str]:
        return {
            camera
            for camera, count in self.open_counts.items()
            if count > 0
        }

    def reset(self, opened: set[str]) -> None:
        self.open_counts = {
            camera: int(camera in opened)
            for camera in self.open_counts
        }

    def consume(self, *, discard: bool = False) -> bool:
        """Consume queued events and report whether the queue overflowed."""
        overflowed = False
        while True:
            try:
                payload = os.read(self.descriptor, 4096)
            except BlockingIOError:
                break
            if not payload:
                break
            offset = 0
            while offset + INOTIFY_EVENT.size <= len(payload):
                watch, mask, _cookie, name_length = INOTIFY_EVENT.unpack_from(
                    payload,
                    offset,
                )
                offset += INOTIFY_EVENT.size + name_length
                if mask & IN_Q_OVERFLOW:
                    overflowed = True
                    continue
                if discard:
                    continue
                camera = self.cameras_by_watch.get(watch)
                if camera is None:
                    continue
                if mask & IN_OPEN:
                    self.open_counts[camera] += 1
                if mask & (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE):
                    self.open_counts[camera] = max(
                        0,
                        self.open_counts[camera] - 1,
                    )
        return overflowed

    def attach(self, callback: Any) -> None:
        self.source_id = GLib.io_add_watch(
            self.descriptor,
            GLib.IO_IN | GLib.IO_ERR | GLib.IO_HUP,
            callback,
        )

    def close(self) -> None:
        if self.source_id is not None:
            GLib.source_remove(self.source_id)
            self.source_id = None
        os.close(self.descriptor)


def hottest_temperature_celsius(
    thermal_root: Path = DEFAULT_THERMAL_ROOT,
) -> float | None:
    """Return the hottest plausible thermal-zone reading.

    Some Cherry Trail firmware exposes disconnected zones as zero or absolute
    zero. Ignore those values instead of disabling the thermal safety gate.
    """
    temperatures: list[float] = []
    try:
        zones = tuple(thermal_root.glob("thermal_zone*/temp"))
    except OSError:
        return None
    for temperature_path in zones:
        try:
            millidegrees = int(temperature_path.read_text(encoding="ascii").strip())
        except (OSError, ValueError):
            continue
        if 0 < millidegrees < 150_000:
            temperatures.append(millidegrees / 1000)
    return max(temperatures, default=None)


def ensure_safe_start_temperature(
    temperature: float | None,
    maximum: float,
) -> None:
    if temperature is not None and temperature >= maximum:
        raise RuntimeError(
            f"refusing to start camera processing at {temperature:.1f} C"
        )


class CameraActivityMonitor:
    """Choose streaming transitions from clients, idle time and temperature."""

    def __init__(
        self,
        idle_delay: float,
        max_temperature: float,
        resume_temperature: float,
    ):
        if idle_delay < 0:
            raise ValueError("camera idle delay cannot be negative")
        if resume_temperature >= max_temperature:
            raise ValueError("camera resume temperature must be below its maximum")
        self.idle_delay = idle_delay
        self.max_temperature = max_temperature
        self.resume_temperature = resume_temperature
        self.idle_since: float | None = None
        self.thermal_blocked = False

    def update(
        self,
        *,
        opened: set[str],
        streaming: bool,
        temperature: float | None,
        now: float,
    ) -> tuple[bool | None, str | None]:
        if temperature is not None:
            if temperature >= self.max_temperature:
                self.thermal_blocked = True
            elif self.thermal_blocked and temperature <= self.resume_temperature:
                self.thermal_blocked = False

        if self.thermal_blocked:
            self.idle_since = None
            if streaming:
                return False, "thermal limit"
            return None, None

        if opened:
            self.idle_since = None
            if not streaming:
                return True, "camera client opened"
            return None, None

        if self.idle_since is None:
            self.idle_since = now
        if streaming and now - self.idle_since >= self.idle_delay:
            return False, "no camera clients"
        return None, None


class CameraSelectionMonitor:
    """Debounce short browser probes and accept one sustained endpoint."""

    def __init__(self, dwell: float):
        self.dwell = dwell
        self.candidate: str | None = None
        self.candidate_since = 0.0
        self.previous_opened: set[str] = set()

    def update(
        self,
        opened: set[str],
        active: str,
        now: float,
    ) -> str | None:
        candidate: str | None = None
        if len(opened) == 1:
            candidate = next(iter(opened))
        elif len(opened) > 1:
            added = opened - self.previous_opened
            if len(added) == 1:
                candidate = next(iter(added))
            elif self.candidate in opened:
                candidate = self.candidate
        self.previous_opened = opened.copy()
        if candidate is None:
            self.candidate = None
            return None
        if candidate == active:
            self.candidate = None
            return None
        if candidate != self.candidate:
            self.candidate = candidate
            self.candidate_since = now
            return None
        if now - self.candidate_since < self.dwell:
            return None
        self.candidate = None
        return candidate


def command(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            arguments,
            check=check,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip()
        rendered = " ".join(arguments)
        if detail:
            rendered = f"{rendered}: {detail}"
        raise RuntimeError(rendered) from error


def command_when_available(*arguments: str) -> subprocess.CompletedProcess[str]:
    """Retry only the short V4L2 close/open handoff race."""
    for attempt in range(50):
        result = command(*arguments, check=False)
        if result.returncode == 0:
            return result
        detail = (result.stderr or result.stdout or "").strip()
        if "Device or resource busy" not in detail or attempt == 49:
            rendered = " ".join(arguments)
            if detail:
                rendered = f"{rendered}: {detail}"
            raise RuntimeError(rendered)
        time.sleep(0.1)
    raise AssertionError("unreachable V4L2 retry loop")


def discover_sensor_subdevice(media_device: str, sensor: str) -> str:
    topology = command("media-ctl", "-d", media_device, "-p").stdout
    entity = False
    for line in topology.splitlines():
        if line.startswith("- entity "):
            match = re.match(r"- entity \d+: (.+?) \(\d+ pads?[,)]", line)
            candidate = match.group(1).casefold() if match else ""
            expected = sensor.casefold()
            entity = candidate == expected or (
                " " not in expected and candidate.startswith(f"{expected} ")
            )
        elif entity:
            match = re.search(r"device node name (/dev/v4l-subdev\d+)", line)
            if match:
                return match.group(1)
    raise RuntimeError(f"cannot find {sensor} sensor subdevice in {media_device}")


def configure_hardware(
    capture_device: str,
    media_device: str,
    profile: dict[str, Any],
) -> str:
    command_when_available(
        "v4l2-ctl",
        "-d",
        capture_device,
        f"--set-input={profile['input']}",
    )
    sensor_device = discover_sensor_subdevice(media_device, str(profile["sensor"]))
    controls = profile.get("sensor_controls", {})
    if controls:
        rendered = ",".join(f"{name}={value}" for name, value in controls.items())
        command("v4l2-ctl", "-d", sensor_device, f"--set-ctrl={rendered}")
    # AtomISP's CSS firmware has no raw-output binary for the default Preview
    # run mode. Explicit Still capture mode is required after every driver
    # probe; relying on a value left by an earlier application breaks reboot.
    isp_device = discover_sensor_subdevice(media_device, "Atom ISP")
    command(
        "v4l2-ctl",
        "-d",
        isp_device,
        "--set-ctrl=atomisp_run_mode=2",
    )
    return sensor_device


def resolve_profile_bayer_format(
    capture_device: str,
    profile: dict[str, Any],
) -> dict[str, Any]:
    """Bind the userspace Bayer caps to the format exposed by the kernel."""
    mappings = profile.get("kernel_bayer_formats")
    if not isinstance(mappings, dict) or not mappings:
        raise RuntimeError("camera profile has no kernel Bayer format mapping")
    listing = command(
        "v4l2-ctl",
        "-d",
        capture_device,
        "--list-formats-ext",
    ).stdout
    enumerated = set(re.findall(r"\[\d+\]: '([^']{4})'", listing))
    for fourcc, bayer_format in mappings.items():
        if fourcc in enumerated:
            resolved = dict(profile)
            resolved["bayer_format"] = bayer_format
            print(
                f"CAMERA_FORMAT fourcc={fourcc} bayer={bayer_format}",
                flush=True,
            )
            return resolved
    expected = ",".join(mappings)
    actual = ",".join(sorted(enumerated)) or "none"
    raise RuntimeError(f"camera raw format mismatch: expected={expected} actual={actual}")


def lock_loopback_format(output_device: str) -> None:
    """Lock producer caps and retain the last valid frame while idle."""
    command(
        "v4l2-ctl",
        "-d",
        output_device,
        "--set-ctrl=keep_format=1,sustain_framerate=1,timeout=0",
    )


def prepare_loopback_format(output_device: str, width: int, height: int) -> None:
    """Establish producer caps before a desktop client can choose them."""
    command_when_available(
        "v4l2-ctl",
        "-d",
        output_device,
        "--set-ctrl=keep_format=0",
    )
    command_when_available(
        "v4l2-ctl",
        "-d",
        output_device,
        (
            f"--set-fmt-video-out=width={width},height={height},"
            "pixelformat=YUYV,field=none,colorspace=rec709,xfer=srgb,"
            "ycbcr=601,quantization=lim-range"
        ),
    )


def is_white_balance_candidate(level: float) -> bool:
    """Exclude only clipped pixels from whole-frame white-balance feedback."""
    return 24 <= level <= 235


def normalized_bayer_buffer(
    source: Gst.Buffer,
    *,
    width: int,
    height: int,
    capture_width: int | None = None,
    capture_height: int | None = None,
    source_stride: int,
) -> Gst.Buffer | None:
    """Crop an AtomISP transport frame into GStreamer's tight layout."""
    capture_width = capture_width if capture_width is not None else width
    capture_height = capture_height if capture_height is not None else height
    if capture_width < width or capture_height < height:
        raise ValueError("capture dimensions are smaller than the Bayer image")
    if source_stride < capture_width * 2:
        raise ValueError("capture stride is smaller than the transport row")
    crop_left = (capture_width - width) // 2
    crop_top = (capture_height - height) // 2
    if (capture_width - width) % 2 or (capture_height - height) % 2:
        raise ValueError("Bayer transport padding cannot be cropped symmetrically")
    if crop_left % 2 or crop_top % 2:
        raise ValueError("Bayer crop offsets must preserve the color phase")
    tight_stride = width * 2
    payload_size = tight_stride * height
    row_bytes = source_stride * capture_height
    size = source.get_size()
    if size < row_bytes:
        print(
            f"ERROR: short raw frame: {size} bytes, expected at least {row_bytes}",
            file=sys.stderr,
        )
        return None
    if source_stride == tight_stride and capture_height == height:
        return source.copy_region(
            Gst.BufferCopyFlags.MEMORY
            | Gst.BufferCopyFlags.TIMESTAMPS
            | Gst.BufferCopyFlags.META,
            0,
            payload_size,
        )

    payload = source.extract_dup(0, row_bytes)
    crop_offset = crop_top * source_stride + crop_left * 2
    tight_payload = b"".join(
        payload[
            (crop_offset + row * source_stride) :
            (crop_offset + row * source_stride + tight_stride)
        ]
        for row in range(height)
    )
    target = Gst.Buffer.new_allocate(None, payload_size, None)
    written = target.fill(0, tight_payload)
    if written != payload_size:
        raise RuntimeError(f"short Bayer copy: {written} of {payload_size} bytes")
    target.pts = source.pts
    target.dts = source.dts
    target.duration = source.duration
    target.offset = source.offset
    target.offset_end = source.offset_end
    return target


class CameraPipeline:
    def __init__(
        self,
        arguments: argparse.Namespace,
        profile: dict[str, Any],
        sensor_device: str,
    ):
        self.arguments = arguments
        self.profile = profile
        self.loop = GLib.MainLoop()
        self.frames = 0
        self.statistics_frames = 0
        self.last_report = 0
        self.still_pending = False
        self.ready_reported = False
        self.output_started = False
        self.pipeline_failed = False
        self.streaming = False
        self.client_monitor: CameraClientMonitor | None = None
        self.activity_source_id: int | None = None
        self.published_camera: str | None = None
        self.switching = False
        self.sensor_device = sensor_device
        self.output_devices = {
            "front": arguments.front_output_device,
            "rear": arguments.rear_output_device,
        }
        self.selection_monitor = CameraSelectionMonitor(arguments.switch_dwell)
        self.activity_monitor = CameraActivityMonitor(
            arguments.idle_delay,
            arguments.max_temperature,
            arguments.resume_temperature,
        )
        self.sensor_controls = {
            name: int(value) for name, value in profile.get("sensor_controls", {}).items()
        }
        self.control_ranges = profile.get("control_ranges", {})

        width = int(profile["width"])
        height = int(profile["height"])
        self.source_stride = int(profile["bytes_per_line"])
        processing = profile["processing"]
        output_width = int(profile["output_width"])
        output_height = int(profile["output_height"])
        for output_device in self.output_devices.values():
            prepare_loopback_format(output_device, output_width, output_height)
        caps = (
            f"video/x-bayer,format={profile['bayer_format']},"
            f"width={width},height={height},framerate=30/1"
        )

        self.capture_description = self._capture_pipeline_description(profile)
        self.process_description = (
            f"appsrc name=source is-live=true format=time caps=\"{caps}\" "
            "max-buffers=2 leaky-type=downstream ! "
            "bayer2rgb ! videoconvert n-threads=4 ! "
            "videoscale method=bilinear n-threads=4 ! "
            f"video/x-raw,width={output_width},height={output_height},framerate=30/1 ! "
            f"videobalance name=balance contrast={processing['contrast']} brightness=0.0 "
            f"saturation={processing['saturation']} ! "
            f"gamma name=tone gamma={processing['gamma']} ! "
            "videoconvert n-threads=4 ! "
            f"video/x-raw,format=RGBA,width={output_width},height={output_height},framerate=30/1 ! "
            f"frei0r-filter-coloradj-rgb name=whitebalance action=1.0 "
            f"r={processing['rgb_red']} g={processing['rgb_green']} "
            f"b={processing['rgb_blue']} keep-luma=false ! "
            f"frei0r-filter-hqdn3d name=denoise spatial={processing['denoise_spatial']} "
            f"temporal={processing['denoise_temporal']} ! "
            "glupload ! glshader name=correction ! gldownload ! tee name=processed "
            "processed. ! queue max-size-buffers=2 leaky=downstream ! "
            "videoconvert n-threads=4 ! "
            f"video/x-raw,format=YUY2,width={output_width},height={output_height},framerate=30/1 ! "
            "intervideosink name=browser_bridge channel=yogabook-camera sync=false "
            "processed. ! queue max-size-buffers=1 leaky=downstream ! "
            "videorate drop-only=true max-rate=2 ! "
            "videoscale method=nearest-neighbour ! "
            "video/x-raw,format=RGBA,width=64,height=36,framerate=2/1 ! "
            "appsink name=statistics emit-signals=true sync=false max-buffers=1 drop=true"
        )
        self.output_description = (
            "intervideosrc channel=yogabook-camera do-timestamp=true "
            f"timeout={INTERVIDEO_LAST_FRAME_TIMEOUT_NS} ! "
            "videoconvert n-threads=2 ! videoscale method=bilinear n-threads=2 ! "
            f"video/x-raw,format=YUY2,width={output_width},height={output_height},"
            "framerate=30/1,colorimetry=2:4:7:1 ! "
            "tee name=browser_outputs "
            "browser_outputs. ! queue max-size-buffers=2 leaky=downstream ! "
            f"v4l2sink device={arguments.front_output_device} sync=false "
            "browser_outputs. ! queue max-size-buffers=2 leaky=downstream ! "
            f"v4l2sink device={arguments.rear_output_device} sync=false"
        )
        if arguments.print_pipeline:
            print(self.capture_description)
            print(self.process_description)
            print(self.output_description)

        self.process = Gst.parse_launch(self.process_description)
        self.output = Gst.parse_launch(self.output_description)
        self.capture: Gst.Element | None = None
        self.appsink: Gst.Element | None = None
        self.capture_bus: Gst.Bus | None = None
        self.capture_bus_handler: int | None = None
        self.sample_handler: int | None = None
        self.eos_handler: int | None = None
        self.appsrc = self.process.get_by_name("source")
        self.browser_bridge = self.process.get_by_name("browser_bridge")
        self.statistics = self.process.get_by_name("statistics")
        self.balance = self.process.get_by_name("balance")
        self.tone = self.process.get_by_name("tone")
        self.whitebalance = self.process.get_by_name("whitebalance")
        self.denoise = self.process.get_by_name("denoise")
        self.correction = self.process.get_by_name("correction")
        shader = FRONT_FRAGMENT_SHADER if arguments.camera == "front" else IDENTITY_FRAGMENT_SHADER
        self.correction.set_property("fragment", shader)
        self.gamma = float(processing["gamma"])
        self.rgb_red = float(processing["rgb_red"])
        self.rgb_blue = float(processing["rgb_blue"])

        self.statistics.connect("new-sample", self._new_statistics_sample)
        process_bus = self.process.get_bus()
        process_bus.add_signal_watch()
        process_bus.connect("message", self._message)
        output_bus = self.output.get_bus()
        output_bus.add_signal_watch()
        output_bus.connect("message", self._message)
        self._create_capture()

    def _capture_pipeline_description(self, profile: dict[str, Any]) -> str:
        capture_width = profile.get("capture_width", profile["width"])
        capture_height = profile.get("capture_height", profile["height"])
        caps = (
            f"video/x-bayer,format={profile['bayer_format']},"
            f"width={capture_width},height={capture_height},framerate=30/1"
        )
        return (
            f"v4l2src device={self.arguments.capture_device} io-mode=2 do-timestamp=true ! "
            f"{caps} ! appsink name=capture emit-signals=true sync=false "
            "max-buffers=2 drop=true"
        )

    def _create_capture(self) -> None:
        if self.capture is not None:
            raise RuntimeError("physical capture pipeline already exists")
        self.capture = Gst.parse_launch(self.capture_description)
        self.appsink = self.capture.get_by_name("capture")
        self.sample_handler = self.appsink.connect("new-sample", self._new_raw_sample)
        self.eos_handler = self.appsink.connect(
            "eos", lambda _sink: self.appsrc.emit("end-of-stream")
        )
        self.capture_bus = self.capture.get_bus()
        self.capture_bus.add_signal_watch()
        self.capture_bus_handler = self.capture_bus.connect("message", self._message)

    def _destroy_capture(self) -> None:
        capture = self.capture
        appsink = self.appsink
        if capture is None:
            return
        # Disconnect EOS before stopping. A temporary physical-source pause
        # must not terminate the independent browser-facing output pipeline.
        if appsink is not None and self.sample_handler is not None:
            appsink.disconnect(self.sample_handler)
        if appsink is not None and self.eos_handler is not None:
            appsink.disconnect(self.eos_handler)
        self.sample_handler = None
        self.eos_handler = None
        capture.set_state(Gst.State.NULL)
        state_result, current, _ = capture.get_state(10 * Gst.SECOND)
        if state_result == Gst.StateChangeReturn.FAILURE or current != Gst.State.NULL:
            raise RuntimeError(f"physical capture did not stop cleanly: {current.value_nick}")
        if self.capture_bus is not None:
            if self.capture_bus_handler is not None:
                self.capture_bus.disconnect(self.capture_bus_handler)
            self.capture_bus.remove_signal_watch()
        self.capture_bus_handler = None
        self.capture_bus = None
        self.appsink = None
        self.capture = None
        del appsink
        del capture
        gc.collect()

    def _apply_profile(self, camera: str, profile: dict[str, Any]) -> None:
        processing = profile["processing"]
        caps = Gst.Caps.from_string(
            f"video/x-bayer,format={profile['bayer_format']},"
            f"width={profile['width']},height={profile['height']},framerate=30/1"
        )
        self.appsrc.set_property("caps", caps)
        self.balance.set_property("contrast", float(processing["contrast"]))
        self.balance.set_property("saturation", float(processing["saturation"]))
        self.gamma = float(processing["gamma"])
        self.tone.set_property("gamma", self.gamma)
        self.rgb_red = float(processing["rgb_red"])
        self.rgb_blue = float(processing["rgb_blue"])
        self.whitebalance.set_property("r", self.rgb_red)
        self.whitebalance.set_property("g", float(processing["rgb_green"]))
        self.whitebalance.set_property("b", self.rgb_blue)
        self.denoise.set_property("spatial", float(processing["denoise_spatial"]))
        self.denoise.set_property("temporal", float(processing["denoise_temporal"]))
        shader = FRONT_FRAGMENT_SHADER if camera == "front" else IDENTITY_FRAGMENT_SHADER
        self.correction.set_property("fragment", shader)
        self.arguments.camera = camera
        self.profile = profile
        self.source_stride = int(profile["bytes_per_line"])
        self.capture_description = self._capture_pipeline_description(profile)
        self.sensor_controls = {
            name: int(value) for name, value in profile.get("sensor_controls", {}).items()
        }
        self.control_ranges = profile.get("control_ranges", {})
        self.statistics_frames = 0
        self.last_report = 0

    def _start_capture(self) -> None:
        self._create_capture()
        if self.capture is None:
            raise RuntimeError("physical capture pipeline was not created")
        result = self.capture.set_state(Gst.State.PLAYING)
        if result == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("physical capture failed to enter PLAYING")

    def _stop_processing(self) -> None:
        self.process.set_state(Gst.State.NULL)
        state_result, current, _ = self.process.get_state(10 * Gst.SECOND)
        if state_result == Gst.StateChangeReturn.FAILURE or current != Gst.State.NULL:
            raise RuntimeError(f"image processing did not stop cleanly: {current.value_nick}")

    def _start_processing(self) -> None:
        result = self.process.set_state(Gst.State.PLAYING)
        if result == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("image processing failed to enter PLAYING")

    def _last_processed_timestamp(self) -> int | None:
        sample = self.browser_bridge.get_property("last-sample")
        if sample is None:
            return None
        buffer = sample.get_buffer()
        if buffer is None:
            return None
        return int(buffer.pts)

    def _wait_for_fresh_processed_frame(
        self,
        previous_timestamp: int | None,
        timeout_seconds: float = 10.0,
    ) -> None:
        deadline = time.monotonic() + timeout_seconds
        while True:
            timestamp = self._last_processed_timestamp()
            if timestamp is not None and timestamp != previous_timestamp:
                return
            if time.monotonic() >= deadline:
                raise RuntimeError("timed out waiting for a fresh processed camera frame")
            time.sleep(0.05)

    def _pause_streaming(self, reason: str) -> None:
        if not self.streaming:
            return
        self.output.set_state(Gst.State.PAUSED)
        failure: Exception | None = None
        try:
            self._destroy_capture()
        except Exception as error:
            failure = error
        try:
            self._stop_processing()
        except Exception as error:
            if failure is None:
                failure = error
        finally:
            self.streaming = False
        notify_systemd(f"STATUS=Camera idle: {reason}")
        print(f"CAMERA_IDLE reason={reason}", flush=True)
        if failure is not None:
            raise failure

    def _resume_streaming(self, reason: str) -> None:
        if self.streaming:
            return
        previous_timestamp = self._last_processed_timestamp()
        try:
            self.sensor_device = configure_hardware(
                self.arguments.capture_device,
                self.arguments.media_device,
                self.profile,
            )
            self.sensor_controls = {
                name: int(value)
                for name, value in self.profile.get("sensor_controls", {}).items()
            }
            self._start_processing()
            self._start_capture()
            self._wait_for_fresh_processed_frame(previous_timestamp)
            result = self.output.set_state(Gst.State.PLAYING)
            if result == Gst.StateChangeReturn.FAILURE:
                raise RuntimeError("browser output failed to resume")
        except Exception:
            self.output.set_state(Gst.State.PAUSED)
            self._destroy_capture()
            self._stop_processing()
            raise
        self.streaming = True
        notify_systemd("STATUS=Corrected camera frames are available")
        print(f"CAMERA_ACTIVE reason={reason}", flush=True)

    def _switch_camera(self, camera: str) -> None:
        if camera == self.arguments.camera or self.switching or self.still_pending:
            return
        old_camera = self.arguments.camera
        old_profile = self.profile
        profile = load_config(self.arguments.config, camera)
        was_streaming = self.streaming
        self.switching = True
        print(f"CAMERA_SWITCH requested={camera} previous={old_camera}", flush=True)
        try:
            if was_streaming:
                self._pause_streaming("switching camera")
            self.sensor_device = configure_hardware(
                self.arguments.capture_device,
                self.arguments.media_device,
                profile,
            )
            profile = resolve_profile_bayer_format(
                self.arguments.capture_device,
                profile,
            )
            self._apply_profile(camera, profile)
            if was_streaming:
                self._resume_streaming("camera switched")
            persist_camera(camera)
            print(f"CAMERA_SWITCH active={camera}", flush=True)
        except Exception as error:
            print(f"ERROR: camera switch to {camera} failed: {error}", file=sys.stderr, flush=True)
            try:
                if self.streaming:
                    self._pause_streaming("restoring camera")
                self._apply_profile(old_camera, old_profile)
                if was_streaming:
                    self._resume_streaming("camera restored")
                persist_camera(old_camera)
                print(f"CAMERA_SWITCH restored={old_camera}", flush=True)
            except Exception as restore_error:
                print(
                    f"ERROR: cannot restore {old_camera} camera: {restore_error}",
                    file=sys.stderr,
                    flush=True,
                )
                self.loop.quit()
        finally:
            self.switching = False

    def _monitor_camera_selection(self) -> bool:
        self.activity_source_id = None
        opened: set[str] = set()
        try:
            if self.client_monitor is None:
                opened = externally_open_cameras(self.output_devices)
            else:
                opened = self.client_monitor.opened
            now = time.monotonic()
            transition, reason = self.activity_monitor.update(
                opened=opened,
                streaming=self.streaming,
                temperature=hottest_temperature_celsius(),
                now=now,
            )
            if transition is False and reason:
                self._pause_streaming(reason)
            elif transition is True and reason:
                self._resume_streaming(reason)
            requested = self.selection_monitor.update(
                opened,
                self.arguments.camera,
                now,
            )
            if requested:
                self._switch_camera(requested)
        except Exception as error:
            print(f"WARN: cannot inspect browser camera selection: {error}", file=sys.stderr)
        interval = (
            ACTIVE_POLL_INTERVAL_MS
            if self.streaming or opened
            else IDLE_POLL_INTERVAL_MS
        )
        self._schedule_activity_monitor(interval)
        return GLib.SOURCE_REMOVE

    def _schedule_activity_monitor(self, delay_ms: int) -> None:
        if self.activity_source_id is not None:
            GLib.source_remove(self.activity_source_id)
        self.activity_source_id = GLib.timeout_add(
            max(delay_ms, 1),
            self._monitor_camera_selection,
        )

    def _initialize_client_monitor(self) -> bool:
        if self.client_monitor is not None:
            return GLib.SOURCE_REMOVE
        try:
            monitor = CameraClientMonitor(self.output_devices)
            initial_opened = externally_open_cameras(self.output_devices)
            monitor.consume(discard=True)
            monitor.reset(initial_opened)
            monitor.attach(self._camera_client_event)
            self.client_monitor = monitor
        except Exception as error:
            print(
                f"WARN: cannot monitor camera clients with inotify: {error}",
                file=sys.stderr,
                flush=True,
            )
        return GLib.SOURCE_REMOVE

    def _camera_client_event(
        self,
        _descriptor: int,
        condition: GLib.IOCondition,
    ) -> bool:
        monitor = self.client_monitor
        if monitor is None:
            return GLib.SOURCE_REMOVE
        if condition & GLib.IO_IN:
            if monitor.consume():
                monitor.reset(externally_open_cameras(self.output_devices))
            self._schedule_activity_monitor(1)
        if condition & (GLib.IO_ERR | GLib.IO_HUP):
            monitor.close()
            self.client_monitor = None
            return GLib.SOURCE_REMOVE
        return GLib.SOURCE_CONTINUE

    def request_configured_camera(self, _signal: int, _frame: object) -> None:
        def switch() -> bool:
            self._switch_camera(resolve_camera("auto"))
            return GLib.SOURCE_REMOVE

        GLib.idle_add(switch)

    def _tight_buffer(self, source: Gst.Buffer) -> Gst.Buffer | None:
        return normalized_bayer_buffer(
            source,
            width=int(self.profile["width"]),
            height=int(self.profile["height"]),
            capture_width=int(self.profile.get("capture_width", self.profile["width"])),
            capture_height=int(self.profile.get("capture_height", self.profile["height"])),
            source_stride=self.source_stride,
        )

    def _new_raw_sample(self, sink: Gst.Element) -> Gst.FlowReturn:
        sample = sink.emit("pull-sample")
        if sample is None:
            return Gst.FlowReturn.EOS
        output = self._tight_buffer(sample.get_buffer())
        if output is None:
            return Gst.FlowReturn.ERROR
        self.frames += 1
        return self.appsrc.emit("push-buffer", output)

    def _new_statistics_sample(self, sink: Gst.Element) -> Gst.FlowReturn:
        sample = sink.emit("pull-sample")
        if sample is None or self.arguments.no_auto:
            return Gst.FlowReturn.OK
        buffer = sample.get_buffer()
        mapped, info = buffer.map(Gst.MapFlags.READ)
        if not mapped:
            return Gst.FlowReturn.OK
        pixels = memoryview(info.data)
        if self.statistics_frames == 0:
            print(
                f"CAMERA_STATS_CAPS caps={sample.get_caps().to_string()} "
                f"bytes={len(pixels)} first={list(pixels[:16])}",
                flush=True,
            )
        if self.output_started and self.published_camera != self.arguments.camera:
            publish_runtime_camera(self.arguments.camera)
            self.published_camera = self.arguments.camera
        if self.output_started and not self.ready_reported:
            for output_device in self.output_devices.values():
                lock_loopback_format(output_device)
            notify_systemd("READY=1\nSTATUS=Corrected camera frames are available")
            self.ready_reported = True
            GLib.idle_add(self._initialize_client_monitor)
        luminance: list[float] = []
        valid_r = valid_g = valid_b = 0.0
        valid_count = 0
        for offset in range(0, min(len(pixels), 64 * 36 * 4), 4):
            red, green, blue = pixels[offset], pixels[offset + 1], pixels[offset + 2]
            level = (54 * red + 183 * green + 19 * blue) / 256.0
            luminance.append(level)
            if is_white_balance_candidate(level):
                valid_r += red
                valid_g += green
                valid_b += blue
                valid_count += 1
        buffer.unmap(info)
        if not luminance:
            return Gst.FlowReturn.OK
        self.statistics_frames += 1
        if self.statistics_frames % 2:
            return Gst.FlowReturn.OK

        luminance.sort()
        percentile = luminance[int(len(luminance) * 0.70)] / 255.0
        target_luma = float(self.profile["processing"]["target_luma"])
        sensor_changed = self._adjust_sensor_exposure(percentile, target_luma)
        if not sensor_changed:
            if percentile < target_luma - 0.035:
                self.gamma = min(2.4, self.gamma + 0.04)
            elif percentile > target_luma + 0.035:
                self.gamma = max(1.0, self.gamma - 0.04)
        self.tone.set_property("gamma", self.gamma)

        red_green = blue_green = 0.0
        if percentile < 0.90 and valid_count >= len(luminance) // 4 and valid_g > 0:
            red_green = valid_r / valid_g
            blue_green = valid_b / valid_g
            target_rg = float(self.profile["processing"]["target_red_green"])
            target_bg = float(self.profile["processing"]["target_blue_green"])
            self.rgb_red = min(0.90, max(0.40, self.rgb_red + 0.030 * (target_rg - red_green)))
            self.rgb_blue = min(1.0, max(0.40, self.rgb_blue + 0.030 * (target_bg - blue_green)))
            self.whitebalance.set_property("r", self.rgb_red)
            self.whitebalance.set_property("b", self.rgb_blue)

        if self.statistics_frames - self.last_report >= 25:
            print(
                f"CAMERA_STATS frames={self.frames} p70={percentile:.3f} "
                f"gamma={self.gamma:.3f} rg={red_green:.3f} bg={blue_green:.3f} "
                f"rgb_r={self.rgb_red:.3f} rgb_b={self.rgb_blue:.3f}",
                flush=True,
            )
            self.last_report = self.statistics_frames
        return Gst.FlowReturn.OK

    def _set_sensor_control(self, name: str, value: int) -> None:
        command(
            "v4l2-ctl",
            "-d",
            self.sensor_device,
            f"--set-ctrl={name}={value}",
        )
        self.sensor_controls[name] = value
        print(f"CAMERA_AE {name}={value}", flush=True)

    def _adjust_sensor_exposure(self, measured: float, target: float) -> bool:
        if measured > target + 0.06:
            order = ("digital_gain", "analogue_gain", "exposure")
            scale = 0.82
            select = max
            bound_index = 0
        elif measured < target - 0.06:
            order = ("exposure", "analogue_gain", "digital_gain")
            scale = 1.18
            select = min
            bound_index = 1
        else:
            return False

        for name in order:
            if name not in self.sensor_controls or name not in self.control_ranges:
                continue
            lower, upper = (int(value) for value in self.control_ranges[name])
            current = self.sensor_controls[name]
            bound = (lower, upper)[bound_index]
            if current == bound:
                continue
            candidate = int(round(current * scale))
            if measured > target:
                candidate = select(lower, candidate)
                if candidate >= current:
                    candidate = lower
            else:
                candidate = select(upper, candidate)
                if candidate <= current:
                    candidate = upper
            self._set_sensor_control(name, candidate)
            return True
        return False

    def _message(self, _bus: Gst.Bus, message: Gst.Message) -> None:
        if message.type == Gst.MessageType.ERROR:
            error, debug = message.parse_error()
            print(f"ERROR: {error}\n{debug or ''}", file=sys.stderr, flush=True)
            self.pipeline_failed = True
            self.loop.quit()
        elif message.type == Gst.MessageType.EOS and message.src == self.process:
            self.pipeline_failed = True
            self.loop.quit()

    def run(self) -> int:
        try:
            self.process.set_state(Gst.State.PLAYING)
            if self.capture is None:
                raise RuntimeError("physical capture pipeline is missing")
            self.capture.set_state(Gst.State.PLAYING)
            self.streaming = True
            self._wait_for_fresh_processed_frame(None)
            self.output.set_state(Gst.State.PLAYING)
            self.output_started = True
            self._schedule_activity_monitor(ACTIVE_POLL_INTERVAL_MS)
            self.loop.run()
        finally:
            if self.activity_source_id is not None:
                GLib.source_remove(self.activity_source_id)
                self.activity_source_id = None
            if self.client_monitor is not None:
                self.client_monitor.close()
                self.client_monitor = None
            try:
                self._destroy_capture()
            finally:
                self.appsrc.emit("end-of-stream")
                self.process.set_state(Gst.State.NULL)
                self.streaming = False
                self.output_started = False
                self.output.set_state(Gst.State.NULL)
        print(f"CAMERA_STOP frames={self.frames}", flush=True)
        return int(self.pipeline_failed)

    def stop(self, _signal: int, _frame: object) -> None:
        self.loop.quit()

    def request_still(self, _signal: int, _frame: object) -> None:
        if not self.still_pending:
            self.still_pending = True
            GLib.idle_add(self._handle_still_request)

    @staticmethod
    def _still_paths() -> tuple[Path, Path]:
        runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        directory = runtime / "yogabook-camera"
        return directory / "still-request.json", directory / "still-result.json"

    def _handle_still_request(self) -> bool:
        request_path, result_path = self._still_paths()
        request_id = "unknown"
        result: dict[str, Any]
        resume_preview = self.streaming
        try:
            request = json.loads(request_path.read_text(encoding="utf-8"))
            request_id = str(request["id"])
            if self.streaming:
                self._pause_streaming("capturing rear still")

            from yogabook_camera_capture import capture_to_path

            still_arguments = argparse.Namespace(
                output=Path(request["output"]),
                config=self.arguments.config,
                capture_device=self.arguments.capture_device,
                media_device=self.arguments.media_device,
                focus_position=request.get("focus_position"),
                no_autofocus=bool(request.get("no_autofocus", False)),
            )
            rear_profile = load_config(self.arguments.config, "rear")
            capture_to_path(still_arguments, rear_profile)
            result = {
                "id": request_id,
                "ok": True,
                "path": str(still_arguments.output.expanduser().resolve()),
            }
        except Exception as error:
            print(f"ERROR: rear still request failed: {error}", file=sys.stderr, flush=True)
            result = {"id": request_id, "ok": False, "error": str(error)}
        finally:
            try:
                self._destroy_capture()
                if resume_preview:
                    self._resume_streaming("rear still complete")
            except Exception as error:
                print(f"ERROR: cannot restore camera preview: {error}", file=sys.stderr, flush=True)
                result = {"id": request_id, "ok": False, "error": f"preview restore failed: {error}"}
            result_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            temporary = result_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(result) + "\n", encoding="utf-8")
            temporary.chmod(0o600)
            temporary.replace(result_path)
            self.still_pending = False
        return GLib.SOURCE_REMOVE


def main() -> int:
    arguments = parse_arguments()
    CameraActivityMonitor(
        arguments.idle_delay,
        arguments.max_temperature,
        arguments.resume_temperature,
    )
    ensure_safe_start_temperature(
        hottest_temperature_celsius(),
        arguments.max_temperature,
    )
    arguments.camera = resolve_camera(arguments.camera)
    profile = load_config(arguments.config, arguments.camera)
    os.environ.setdefault("GST_GL_PLATFORM", "egl")
    os.environ.setdefault("GST_GL_WINDOW", "surfaceless")
    os.environ.setdefault("GST_GL_API", "gles2")
    Gst.init(None)
    sensor_device = configure_hardware(arguments.capture_device, arguments.media_device, profile)
    profile = resolve_profile_bayer_format(arguments.capture_device, profile)
    pipeline = CameraPipeline(arguments, profile, sensor_device)
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, pipeline.stop)
    signal.signal(signal.SIGUSR2, pipeline.request_still)
    signal.signal(signal.SIGHUP, pipeline.request_configured_camera)
    return pipeline.run()


if __name__ == "__main__":
    raise SystemExit(main())
