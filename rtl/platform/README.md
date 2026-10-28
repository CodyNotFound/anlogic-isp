# Platform Layer

The current TD-compatible platform implementation remains in `rtl/hardware/`
and is wrapped by `rtl/vendor/rtl/vendor_lab1_core.v`. This directory is
the ownership boundary for future SC500, MIPI, DDR, PLL, and HDMI wrappers.
