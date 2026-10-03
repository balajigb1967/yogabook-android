# Architecture

Good camera output crosses several independently owned layers:

```text
OV2740 sensor
  -> CSI-2 transport and Yoga Book firmware properties       kernel
  -> AtomISP2401 CSS image-processing pipeline               kernel
  -> stride normalization and Bayer demosaic                 this project
  -> exposure, white balance and color/tone policy           this project
  -> V4L2/PipeWire camera exposure                            this project
  -> transport and physical acceptance                       Validator
```

## Design constraints

1. Use the upstream kernel sensor and AtomISP drivers as the base. The older
   `atomisp-6.10-dkms` project is useful for historical comparison, not as a
   replacement for the Yoga Book's newer customized kernel.
2. Treat Lenovo's AIQB tuning as user-supplied until redistribution rights are
   known. Store only its public metadata and checksum in Git.
3. Do not pretend that raw sensor controls replace ISP tuning. Sensor exposure
   and gains may support bring-up, but lens shading, color and denoising belong
   to the image pipeline.
4. Audit any legacy AtomISP userspace ABI command before enabling it. Never
   expose the complete private ioctl surface merely to run an old binary.
5. Keep application integration standard: the final front camera must appear
   through PipeWire/V4L2 without application-specific Meet workarounds.

## Incompatible Intel camera generations

| Component | Hardware role | Yoga Book relevance |
| --- | --- | --- |
| AtomISP2401 | Cherry Trail CSI and ISP/CSS pipeline | The actual YB1-X91L hardware |
| `intel_atomisp2_pm` | Legacy dummy PCI power-gating driver | Obsolete when the real AtomISP driver is bound |
| IPU6 | Modern Intel ISYS/PSYS camera architecture | Different hardware, firmware and userspace ABI |

IPU6 camera engines cannot run on PCI device `8086:22b8`. Their userspace
architecture may inform future design, but their firmware, processing
algorithms and camera HAL are not binaries or drivers for AtomISP2401.

The historical `intel_atomisp2_pm.c` driver supports `8086:22b8`, but only to
disable CSI ports and power-gate the IUNIT for D3 suspend. The active upstream
AtomISP driver already includes the equivalent ISPSSPM0 power sequence. The
dummy driver performs no capture, 3A, tuning or image processing.

## Delivery stages

1. Preserve the proven OV2740 transport changes in the kernel repository.
2. Capture the complete AtomISP raw transport frame and crop its sensor
   margins in userspace. The current OV2740 Yoga Book mode exposes
   1932x1092 SBGGR10 for a centered 1920x1080 image; the package also
   negotiates the earlier SGRBG10 fallback ABI. OV8858 exposes 1632x1224 for
   a 1616x1208 preview and 3264x2448 for a
   3248x2432 still. Normalize the aligned row stride at the same boundary.
3. Demosaic the selected sensor-matched Bayer10 stream with GStreamer's Bayer
   converter and scale meeting output to 1280x720.
4. Drive standard sensor exposure/gain controls from downscaled output
   statistics. Keep sensor RGB gains at unity and own white balance in one
   userspace stage so exposure changes cannot silently alter color.
5. Apply color, tone, denoising and spatial shading correction before writing
   YUYV to two exclusive-capabilities V4L2 endpoints named for the front and
   rear cameras. Both endpoints carry the one active physical stream so their
   writer side remains stable while applications choose between them.
6. Promote the Debian package only after Validator automation and physical
   front/rear meeting tests pass.

## Runtime data flow

```text
/dev/video0 sensor-matched Bayer10
  -> centered crop + stride normalization
  -> bayer2rgb
  -> 1280x720 RGBA
  -> color balance + hqdn3d + GLSL shading matrix
  -> YUYV inter-video sink
  -> stable inter-video source + tee
       -> /dev/video10 Front Camera
       -> /dev/video11 Rear Camera
  -> PipeWire / browser camera selector

                     -> 64x36, 2 fps statistics
                     -> sensor AE + userspace AWB feedback
```

The physical AtomISP video, media and subdevice nodes deliberately do not
receive logind `uaccess` ACLs. The early system processor runs as desktop UID
1000 with supplementary `video` and `render` groups, while ordinary browser
processes of that UID cannot open `/dev/video0`. Only `/dev/video10` and
`/dev/video11` retain normal desktop access. The service notifies systemd after
its first processed frame, locks both established loopback formats and is
ordered before the display manager. The format lock prevents Chromium from
reconfiguring either capture side and stalling an already-running producer
during its first open. The loopbacks use capture-only advertisement while the
processor owns their output sides; Chromium filters loopback devices that also
advertise video output.
Before a planned processor stop, systemd clears `keep_format`; otherwise the
loopback can retain capture-only state after the writer exits and reject the
next writer even when no browser has the node open.
At startup the processor first establishes the complete 1280x720 YUYV output
format before constructing the expensive camera pipeline. It sets
`keep_format` only after both producer writers are active, because locking an
unowned `exclusive_caps` loopback would make it capture-only and reject the
writer. This prevents PipeWire or Chromium discovery from selecting
v4l2loopback's default BGR4 format during the boot window. Any later pipeline
error exits nonzero so the unit's bounded `Restart=on-failure` policy can
reconstruct the producer.

The loopback writers remain open but paused when no external process holds
either capture endpoint. After a three-second debounce, the service stops the
physical AtomISP capture and the expensive Bayer, denoise and color pipelines.
Opening either loopback resumes them before frame delivery, preserving normal
browser discovery without continuously spending approximately two Atom cores.

Resource safety is layered. The service stops processing if any plausible
system thermal-zone reading reaches 85 C and uses a 10 C hysteresis before
resuming. Its systemd cgroup caps CPU at 175%, memory at 384 MiB and tasks at
64, assigns a low CPU weight and limits restart storms. Kernel thermal
protection remains authoritative; the userspace gate prevents this optional
camera workload from reaching that last-resort boundary during normal use.

The front and rear cameras share one AtomISP capture node. Sensor selection is
therefore serialized; it is not safe to run two physical capture producers at
once. A debounced monitor ignores short enumeration probes and switches only
after exactly one external camera endpoint remains open. The physical capture
and processing pipelines are then rebuilt in place. A separate inter-video
pipeline keeps the two browser-facing writers open and supplies a bounded
last-valid-frame interval during idle wakeups and handoffs, so changing the
camera in a Meet call does not remove either device. The loopbacks disable
their synthetic timeout image: a measured default timeout frame was solid
green, and publishing it during processor wakeups made remote meeting video
flash green. The inter-video bridge retains the last corrected frame for a
practical one-year interval instead of substituting a black frame. On every
idle resume or sensor switch, the browser writer remains paused until the
processor publishes a sample whose timestamp differs from the previous
sample. The loopback therefore repeats its last valid frame during warmup and
never receives the inter-video bridge's initial black frame.

Full-resolution rear stills are requested through the running system service.
The service pauses only its AtomISP source pipeline while keeping the
V4L2-loopback output pipeline open, captures and encodes the rear frame, then
restores the selected preview. This prevents browsers from interpreting a
temporary loopback disappearance as permission to open the private raw
AtomISP node.

GStreamer can report the physical pipeline at NULL just before the last V4L2
file reference is released. Sensor switching therefore retries only
`Device or resource busy` for a bounded five seconds; unsupported formats,
missing devices and all other errors remain immediate failures.

AtomISP rejects system suspend while a raw stream is active. A DMI-scoped
system sleep unit therefore records each active per-user camera service,
stops it before `sleep.target`, and restarts only the recorded instances after
resume. The loopback and physical pipeline are reconstructed by the normal
service startup path.

AtomISP also defaults its ISP subdevice to `Preview` after every probe. The
bundled CSS firmware cannot construct a BGGR10 output pipeline in that mode.
Before every front or rear configuration, the runtime resolves the exact
`Atom ISP` media entity and selects `Still capture`; this is explicit boot
state, not a value inherited from earlier camera applications.
