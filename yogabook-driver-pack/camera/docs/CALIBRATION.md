# Camera calibration

Calibration is sensor-specific. A setting accepted for the front OV2740 must
not be copied to the rear OV8858, and a single recognizable frame is not
enough to establish image quality.

## Reference scene

Use a stable, flicker-free room light and place these items in one frame:

- a neutral grey or white card;
- a saturated orange/red object;
- green and blue objects;
- a face or hand with both lit and shadowed skin;
- a fine-text target near the center and all four corners.

Capture the same scene from a known-good camera without changing the lighting.
The reference camera is a perceptual color target, not a resolution target:
its HDR, sharpening and denoising will differ from the OV2740 or OV8858.

The initial front reference taken on 24 August 2026 established representative
medians of approximately `155,139,122` for the warm wall, `168,79,38` for the
orange object, `127,109,94` for lit skin and `74,37,28` for shadowed skin. The
reference image itself is private test data and is not committed.

## Adjustment order

Tune in this order so one feedback loop does not conceal another problem:

1. Confirm sensor-matched Bayer10 transport, dimensions, row stride and Bayer order with the
   sensor test pattern.
2. Keep sensor red and blue balance at unity. Establish black level and remove
   clipped or defective pixels from statistics.
3. Converge exposure, then analogue gain, then digital gain. Reduce these in
   the reverse order when the scene is too bright.
4. Converge userspace white balance from non-clipped image statistics.
5. Correct spatial color/lens shading using neutral patches across the frame.
6. Fit the color transformation against neutral, saturated and skin patches.
7. Apply tone mapping and only then tune spatial/temporal denoising.
8. Recheck motion, detail, frame rate and CPU/memory use after every quality
   change.

Do not tune against one wall alone. A transform that makes the wall neutral
can still destroy skin and saturated colors.

The 0.1.15 front residual-shading pass used the wall only to measure spatial
variation after global color convergence. Six broad regions and sixteen local
samples ranged from `R/G=0.821..1.263` and `B/G=0.760..0.971`, while the
reference wall remained near `R/G=1.119`, `B/G=0.882`. A quadratic gain surface
was fitted for red and blue and clamped to the measured range. Physical tests
rejected that surface: it caused orange skin and inconsistent wall color even
after saturated foreground objects were excluded from white-balance feedback.
Version 0.1.19 therefore removes the quadratic surface while retaining the
earlier bounded edge correction and mild sharpening. The orange and skin
references remain physical acceptance gates; they are not neutral patches.

Version 0.1.18 tried low-chroma-only white-balance statistics. Physical testing
rejected that policy too: qualifying samples were absent from most statistics
windows, and rare wall samples drove the red gain upward until skin and the
room became orange. Version 0.1.20 restores the previously stable whole-frame
statistics while continuing to exclude clipped dark and bright pixels. This
matches the known-good 14:50 baseline behavior without restoring the rejected
quadratic surface.

## Evidence to retain

For each accepted profile record the kernel and package versions, sensor and
mode, sensor controls after convergence, output statistics, lighting type,
reference/candidate captures and the physical observer's result. Captures may
contain private material and therefore stay outside Git.
