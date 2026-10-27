# ISP and Algorithms

Pixel-domain transforms live here. `pixel_algorithm.v` currently provides
passthrough, binary, grayscale, and Sobel modes.

Binary mode uses a frame-global BT.601 Y average as its adaptive threshold.
The threshold is bounded to 24..224 and moves by at most eight levels per
frame, avoiding the all-white/all-black jump caused by a fixed threshold when
scene illumination changes.
