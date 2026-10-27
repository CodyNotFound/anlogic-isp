# v61 incremental instrumentation and motion design

Registration text is independent of unfinished additions and stays <=13/500 characters. No form submission has been performed.

1. Target center X/Y in native display pixels, FACE from CNN decoded center, TRACK/REGION from existing displayed sample-grid coordinates times8. Lost/invalid results render ----. Frame-latch the complete numeric packet, reuse the existing font/compositor. No new line buffers.
2. Algorithm compute elapsed display: use existing measured CNN/tracker/region cycle counters, convert at75MHz with rounded milliseconds. Label PROC, not camera-to-display latency. No manufactured16.7ms result. A single serial BCD engine converts fields off the pixel path. First result is required before showing numeric compute time.
3. True transport latency needs input accepted-SOF id/time attached to the exact DDR frame commit and carried to the matching display-read frame. Independent clock-domain counters or newest frame-count differences are not sufficient. Optical validation should compare a blinking source with its displayed image. Exposure/readout and HDMI scan boundaries must be stated.
4. Motion candidate: fixed-camera 160x90 block-average luma frame difference, prior frame stored in existing CNN arena only in a mutually exclusive motion mode. First frame initializes reference; abs difference plus minimum region area and temporal consistency provide motion prompts, not semantic classification. Global change rejects lighting jumps; manual/gimbal movement suppresses detection during movement/settling. Does not support simultaneous CNN and shared-memory motion without further scheduling.
5. Optimize measured costs: reuse font and number formatter, use mutually-exclusive frame/template/queue/motion RAM, profile inherited optional branches, do not blindly convert BRAM into LUT RAM. Full physical utilization and setup/hold remain separate gates. Keep each candidate and Git evidence.

Current starting point: v60 placement20055/21216 Slices, RAM108/108, DSP39/40, final route still pending. Preserve frozen v60 build inputs; changes go to v61 only.
