# Camera status

## Established hardware

The YB1-X91L exposes two sensors through AtomISP2401:

| Input | Sensor | Native mode | Intended use |
| --- | --- | --- | --- |
| 0 | OV2740 | 1932x1092, cropped to 1920x1080 | Front-facing meetings |
| 1 | OV8858 | 3264x2448 | Rear-facing 8 MP capture |

The 8 MP specification refers to the rear OV8858. The front OV2740 is roughly
2 MP, but a correctly processed 1080p image should still be suitable for video
meetings.

## Proven transport

- OV2740 uses a 576 Mbps two-lane link (288 MHz link frequency).
- The current reviewed Yoga Book mode produces a full 1932x1092 SBGGR10
  transport. The package negotiates that BG10 ABI and the earlier BA10/SGRBG10
  integration fallback. Userspace
  removes six pixels from each edge to preserve the Bayer phase at 1920x1080.
- AtomISP normal-dequeue streaming has produced complete 1920x1080 YU12 frames
  at approximately 30 fps without kernel errors.
- AtomISP's poll path is unsupported; a `--stream-poll` timeout is not evidence
  of transport failure.

The Yoga Book-specific kernel work remains in `Yoga-Book-Linux-Kernel` and is
not duplicated here.

## Latest kernel/runtime validation

The latest device-side validation used kernel
`7.2.0-yogabook-20260828-163827`, built from integration commit
`907805589733fd2e9112118314ac811361afdcd2`. On the physical YB1-X91L:

- OV2740 and OV8858 both bound to their sensor drivers;
- the front link reported 288 MHz and the full 1932x1092 Bayer10 frame;
- OV2740 exposed red- and blue-balance controls;
- OV8858 exposed digital gain from 1024 through 4095;
- `Rear Camera` completed a bounded 90-frame open, followed by an automatic
  switch to a bounded 150-frame `Front Camera` open;
- sustained service operation produced no new AtomISP or CSS error.
- both physical images and switching were accepted in Cheese.

That kernel was validated as a one-shot boot; recording its package and source
identity does not make it the persistent boot default. The kernel/userspace
interface and provenance boundary are specified in
[KERNEL-CONTRACT.md](KERNEL-CONTRACT.md).

## Userspace ISP evidence

The repository implementation has run continuously on the physical tablet:

- OV2740: 1932x1092 sensor-matched Bayer10 transport (current SBGGR10 or
  earlier SGRBG10 fallback) center-cropped to 1920x1080, then
  converted to the 1280x720 YUYV loopback output;
- OV8858: 1632x1224 BGGR10 transport cropped to 1616x1208 with 3,328-byte
  row-stride normalization, then converted to 1280x720 YUYV;
- sensor-domain auto exposure converged from a clipped bright-room start to
  70th-percentile luma near 0.55;
- grey-world AWB converged to the warm-neutral reference ratios
  `R/G=1.115`, `B/G=0.875`;
- both continuous raw tests completed without AtomISP/CSS/kernel errors;
- A later no-client profile exposed an unacceptable regression: the complete
  front pipeline stayed active at 183-200% CPU, raised the PNIT thermal zone
  to 79 C and could contend with desktop audio. Version 0.2.13 keeps both
  browser endpoints visible but closes `/dev/video0` and suspends processing
  after three idle seconds. Event-driven client tracking plus a slow idle
  thermal poll reduced a final 20-second physical sample to 0.41% service CPU;
  PNIT cooled to 51-53 C.
- A bounded 300-frame front capture resumed automatically, completed at
  approximately 25-30 fps, respected the live 175% CPU cgroup ceiling and
  returned to idle without a service restart. A concurrent finite 10-second
  PipeWire playback stream and the camera capture both exited successfully,
  with no new SOF, IPC, XRUN, underrun or overrun message.
- From the fully idle state, a final 30-frame front open completed in 0.92
  seconds and returned to idle automatically. This direct transport check does
  not replace a physical Google Meet image and switching acceptance pass.
- full-resolution 3248x2432 rear BGGR10 capture, one-shot focus movement and
  JPEG encoding have completed on the physical tablet;
- the OV8858 synthetic pattern produces clean full-scale white, yellow, cyan,
  green, magenta, red and blue bars through the raw AtomISP path;
- a real rear frame spans the full 10-bit range after applying Lenovo's
  production per-channel digital-gain registers; the previous near-black
  output came from the generic driver writing a different gain block;
- a same-frame rear color comparison selected RGB controls `0.65/0.50/0.60`
  at gamma `2.0`, producing whole-frame means `135/133/129` instead of the
  unity profile's green `103/139/107`; physical scene acceptance remains open;
- repeated fixed-focus stills stabilized near 173 MB service memory rather
  than growing once per capture.
- cold driver initialization requires `atomisp_run_mode=2` before BGGR10
  format negotiation; this is now set through the exact `Atom ISP` media
  entity rather than relying on state left by earlier diagnostic programs.
- Chrome fallback to the private green AtomISP YUV node is prevented by a
  device ACL boundary and an early system service that becomes ready only
  after the corrected loopback receives frames.
- A post-idle 300-frame front-camera sample reproduced eight synthetic timeout
  frames with exact downscaled means `R=0/G=131/B=0`. Disabling the loopback
  timeout image eliminated all green frames in the follow-up sample. The
  inter-video source now retains the last corrected frame across idle wakeups
  instead of switching to its independent black timeout frame.
- The first 0.2.16 concurrency pass then found 22 black warmup frames because
  resuming the browser writer raced the newly restarted processing pipeline.
  Version 0.2.17 keeps the writer paused until the processing sink exposes a
  fresh timestamp, while the loopback repeats its previous valid frame.
- The loopback format is locked after its first processed frame; a physical
  Chrome trace then sustained 66 successful dequeues over two seconds without
  the earlier stream-off/reopen loop or producer stall.
- Version 0.2 exposes separate front and rear browser endpoints while keeping
  one physical AtomISP stream. A debounced endpoint-open monitor performs the
  sensor handoff without restarting the stable browser-facing writers;
  physical Google Meet switching remains an acceptance gate.
- Chromium requires capture-only loopback advertisement to enumerate the
  endpoint. The two-buffer limit also supports GStreamer consumers; the format
  lock prevents Chromium's open from stalling the producer. Package upgrades
  leave the active producer running so a browser cannot strand the output side.
- A direct 1280x720 frame exposed two-dimensional color shading hidden by the
  meeting crop. A clamped quadratic red/blue gain surface was physically
  rejected because it produced orange skin and inconsistent wall color. The
  subsequent neutral-only feedback experiment was also rejected because
  sparse samples drove the scene orange. The front profile now uses the
  previously stable whole-frame non-clipped white-balance feedback and retains
  conservative post-denoise edge enhancement; final physical acceptance
  remains required.

This evidence proves runtime architecture and transport, not final image
acceptance. The front image still has visible noise and residual spatial color
variation. The rear lens has now been confirmed unobstructed and the black
output has been localized to gain programming, but a real corrected 8 MP still
requires physical color, focus and detail acceptance.

Lenovo's inspected `OV2740_CJAE533_CHT.cpf` is a 33,720-byte Intel AIQB file
described internally as OV2740 V11 tuning dated 2015-02-02. Compatibility with
the current upstream AtomISP CSS ABI and a legally redistributable AIQ runtime
has not yet been established.

The inspected Lenovo package contains the CPF, an OV2740 Windows kernel driver
and an ISP2401 Windows resource-manager driver. It does not contain an AIQ
userspace DLL, so those files alone cannot be transplanted into Linux as the
missing 3A service.

## Safety boundary

AtomISP private ioctls remain disabled. A previous narrow white-balance ioctl
experiment reached an invalid ISP parameter path and divided by zero while
starting the CSS stream. Reopening private controls requires per-command ABI
analysis, bounded validation and a recoverable one-shot boot.

Raw formats are limited to the active sensor media-bus format and require no
module parameter. AtomISP private ISP ioctls remain closed.
