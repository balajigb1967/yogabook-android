# Camera acceptance

Camera support is complete only when all automated and physical gates below
pass on a Lenovo Yoga Book YB1-X91L. Transport success is necessary but is not
image-quality acceptance.

## Automated gates

- `make test` and `make package` pass from a clean checkout.
- The package installs, upgrades and removes without maintainer-script errors.
- DMI gating prevents Yoga Book camera preparation on any other product.
- The front and rear sensors are discovered by media entity name rather than a
  fixed subdevice number.
- Front and rear direct streams run without short frames, GStreamer errors,
  AtomISP/CSS errors or unbounded memory growth.
- `Front Camera` and `Rear Camera` are both visible as
  1280x720 YUYV devices through PipeWire and Chromium.
- Selecting either device in a live Google Meet call automatically activates
  the matching sensor without a command, service restart or lost endpoint.
- Short Chromium enumeration probes do not change the active sensor. Selecting
  either sensor survives closing/reopening the application, and the front
  camera remains the safe default for a fresh user.
- Camera operation recovers after five suspend/resume cycles and three cold
  boots.
- A 30-minute meeting stream maintains frame delivery, bounded memory and
  usable audio on the same device.
- With no application holding either endpoint, physical capture becomes idle
  within five seconds and sustained service CPU remains below 5%.
- Active camera processing stays inside its 175% CPU, 384 MiB memory and
  64-task cgroup limits without starving audio or desktop input.
- A simulated thermal-zone reading at 85 C suspends capture, no automatic
  restart occurs above 75 C, and capture resumes after the reading cools to
  75 C or below while a client remains open.

## Front OV2740 physical gates

Evaluate a live face, neutral target, saturated objects and fine detail in
daylight, normal indoor light and dim indoor light. Require:

- recognizable natural skin, orange/red, green and blue colors;
- no persistent green, magenta or cyan cast;
- no visible left/right or corner color discontinuity on a neutral target;
- stable exposure and white balance without pulsing;
- readable central detail and no gross Bayer, line or wave artifacts;
- noise appropriate for a 2 MP 2016 sensor, without destructive smearing;
- acceptable motion and lip synchronization in a real Google Meet session.

The OV2740 is approximately 2 MP. It is not expected to match a modern phone,
but its processed 1080p transport must produce a credible meeting image.

## Rear OV8858 physical gates

Lift the tablet so the rear lens is fully uncovered. Require:

- the same color/exposure/stability checks as the front camera;
- a continuous 1616x1208 preview;
- a full-resolution 3248x2432 still path with correct focus operation;
- a saved still with plausible 8 MP detail and no purple stripes, bad rows or
  frame truncation.

The rear sensor is selectable for a meeting when the tablet is positioned so
its lens has a useful view, but the front remains the normal meeting camera.

## Release decision

Record automated transport and physical image quality separately. A release
must remain experimental if any mode, sensor, browser, lifecycle or physical
gate is missing or only inferred.
