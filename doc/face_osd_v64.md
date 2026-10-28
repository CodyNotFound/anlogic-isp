# v64: face feedback cadence, Chinese HUD and visible effects

## Scope and frozen source
Based on v62 (12751d7), rather than the larger v63 packing result. Whole build: colorshading_runs_20261025_v64_face_osd_r1. Routed capacity/timing and live-board acceptance are pending.

## Face control diagnosis and correction
The CNN takes about 267 ms per inference. Old control expires a move after 120 ms and labels age>=200 ms HOLD, even during successful inference. The old 32-us endpoint is reached in four PWM periods, producing a repeated burst-and-stop pattern.

CNN mode now records commanded H/V at accepted capture SOF. A new result computes a bounded absolute goal relative to that capture command, compensating for intervening commanded camera motion. The residual is distributed with fractional accumulation over 16 PWM periods (320 ms); maximum 128 us per plan, at most 8 us per 20-ms PWM period. This is commanded-motion compensation, not a measured encoder model. Detection validity timeout is 650 ms in CNN mode. No infinite extrapolation: one result permits at most 16 steps. Missing target cancels motion immediately. Manual/auto-off cancels capture authorization; a new post-manual capture is required. Fast-source template/color controls keep the previous behavior.

Evidence:
- reports/face_v64/cadence.log: 280-ms update stimulus, 70/70 moving PWM periods versus old 20/70; spurious HOLD 0 versus25. Synthetic control test, not detection accuracy.
- delay_comp.log: delayed observation of a stationary target does not reintegrate movement already commanded since capture; finite stale-ramp expiry.
- legacy.log: original fast-source endpoint/slew, loss hold, OFF cancellation, deadband, reversal and manual acceleration.
- pipeline.log: native coordinates/PROC propagation, injected interface probe only.
- Full actual-photo/native-camera-protocol/CNN-to-PWM regression is running separately (native_r2.log); do not claim it passed until final PASS with no warnings/errors.
- CNN arithmetic, weights and detector FPS have not changed. This addresses servo cadence and stale-measurement overcorrection; it cannot eliminate the network inference delay or guarantee moving-face accuracy.

## Chinese OSD
Rebuilt 126 glyphs (42 ASCII,84 CJK) within the existing 2048x16 font ROM; production MIF equals simulator HEX. Bold ASCII and existing 16x16 Chinese glyph size, rendered at1.5x. Native alphabet includes lowercase m/s for `0267ms PROC` directly below FPS. PROC is algorithm work time, not end-to-end latency.

Mode names: 人脸/模板/色区/运动/卡通. Main states: 等待/跟踪中/目标丢失/手动控制/自动关闭; motion-mode status is Chinese too. Brief nontracking status changes wait16 video frames before replacing TRACK, while restored TRACK and manual/auto changes apply immediately. Physical keys use Chinese directions, no Vim letters. Bottom legend is576x54 rather than a full-width bar. SW1/2 use 自/锁 for automatic/locked; SW3/4 use 开/关. Separate font resources remain within previous ROM allocation.

reports/osd_v64/render.log: 2 complete720p frames,1843200 known RGB pixels with aligned qualifiers and HOLD rejection. frame0.png/frame1.png are actual RTL-composed output. visual_validation.json checks both Logo crops exactly against existing index/palette, unchanged central picture area, all2048 MIF/HEX words and nonblank Chinese glyphs. Font map and text_spec.json record glyph/label definitions.

## Effects and outlines
Sharpening detail gain increases2x->4x, retains6-level detail threshold to avoid boosting very small noise. Blur becomes separable recursive low-pass (3*previous+current)/4 along each axis. It reuses the existing line1 RAM for vertical feedback in mode6, initializes first row/column at SOF, and adds no RAM. It is a causal smoother with spatial displacement, not symmetric Gaussian or neural blur. Other modes retain their pipeline latency.

reports/face_v64/effects_r3.log:147456 exact RGB pixels against an independent integer Python reference,8 scenes, mode0 untouched, sharpen/blur/emboss, frame restart and SOF/EOL. Initial failed harness logs remain but are not accepted proof. Reproducible v64 fixtures and guarded bench are under reports/effects_v64 and sim/tb_effects_spatial_v64.sv.

Face, template/color/motion boxes become3 pixels thick and center crosses3 pixels wide. outline_r2.log checks6144 exact RGB pixels and frame qualifiers.

## Remaining prior request
Template full-frame automatic reacquisition is still disabled in this source; only three bounded local recovery frames are configured. A separate next candidate must implement bounded tile search using the same score arena and test target absence, reentry outside the old window, distractors, reseed and worst-case completion time. Do not claim full reacquisition from old obsolete testbench names.
