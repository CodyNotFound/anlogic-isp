# Frame-buffer latency instrumentation audit

Read before modifying the stable display transport. No video_in/video_out/vendor transport RTL was changed in v62.

- vendor_reference/rtl/vendor_lab1_core.v instantiates video_in with ISP output SOF/data and sys clock, transfers to DDR; I_mipi_rx_error currently tied0. An original sensor exposure timestamp is not present at this interface.
- video_in.v rotates a4-bank write pointer on synchronized SOF and derives read pointer at a fixed offset. It does not export a completed-frame descriptor containing source frame id/time/accepted-word count. Address selection uses the old write pointer at the SOF edge, important for any parallel metadata scoreboard.
- A valid720p RGB frame contains172800 accepted128-bit words. Metadata validity must reflect complete accepted writes and invalidate abort/partial frames, not just SOF.
- video_out.v latches next_frame_base at video frame start, drains old responses, resets its async FIFO, and selects the new base at RELEASE_FIFO. A tag must follow the actual chosen base, not the latest live read pointer. First displayed data is delayed by the pixel FIFO/serializer and can be blanked by underflow.
- A common DDR-domain timebase plus per-bank metadata and explicit display-start snapshot can measure buffer ingress-to-display transport. An original capture-to-display measurement additionally needs the pre-ISP capture tag bound to the same frame. Describe boundary and resolution; do not label PROC or reciprocalFPS as end-to-end latency.
- Proposed v63+ gate order: standalone metadata scoreboard tests (wrap, repeated reads, rejected/partial frame, overwritten bank, drain delay, reset), integrate sideband hooks without changing RAM arbitration or pointer algorithm, CDC review/constraints, native transport regression, routedSTA, optical slow-motion cross-check. Optical evidence should include blinking source and display in one shot.

Current on-screen PROC remains existing algorithm-work counter rounded to milliseconds. Motion work excludes time waiting for camera samples. No unmeasured transport figure is displayed.
