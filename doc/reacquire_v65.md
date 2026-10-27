# v65: resource-fit retry, explicit Chinese control labels and template reacquisition

Based on0553dba (v64 functionality), isolated from v64 r1's frozen source. v64 r1 failed packing at21297 physical Slice (device21216); no timing-clean bit exists for v64. v64 actual-photo/nativeRGB/fullCNN-to-slew regression subsequently passed with zero warnings/errors; see its retained evidence.

## Resource changes preserving face behavior
- One shared error magnitude/gain/clamp datapath serves both slow CNN and fast sources instead of parallel integer datapaths. Signed bounded intermediates replace32-bit integer results.
- Default vision_bcd20-bit/6-digit behavior remains. Panel uses one12-bit/4-digit engine for both axes and publishes one coherent H/V snapshot; telemetry uses14-bit/4-digit engine. No video-stage changes.
- The tracker counter width uses a conservative5000 cycles per bounded candidate plus100000 seed cycles; the public32-bit value is zero extended. Tile search never enlarges the score arena or one search's candidate count.
- control_v65 regressions: same cadence, stale compensation, loss/manual safety; BCD all10000 values against default engine and decimal arithmetic;187 atomic panel packets plus scan/debounce/LED tests.

## Full-frame template reacquisition
REACQUIRE_ENABLE defaults0 for compatibility, enabled in vision_task_suite. On a missed accepted target, retain the frozen multi-angle/scale gradient template and enter tiled recovery. Each new captured frame searches a tile no larger than the original(2R+1)^2 candidates. All legal top-left positions are visited by raster-scanned tiles. One matching tile needs best<=MAX_SAD/2 and the existing uniqueness gap; a second frame must confirm locally within4 sampled pixels before publishing found=1. Otherwise continue the sweep. K4 resets template/recovery; mode exit releases shared RAM through the existing owner reset.

For160x90,R8 there are9x5=45 tiles; one search is approximately15 ms plus source-frame acquisition. With60Hz input and alternate-frame capture, a stationary reentry may take roughly1.5 seconds per sweep, plus confirmation. This is a scheduling estimate; measured production geometry is still required. Low texture, large scale/pose change and repeated-looking targets remain failure cases. Confidence is local to a tile, not global identity. No automatic cloud processing or new framebuffer is used.

tb_reacquire_v65 PASS (actual_r2.log, zero warnings/errors):47 frames using actual CNN feature RAM for frame/template/scores, absent-target full sweep, reentry outside the old window found after16 frames, second-frame confirmation, K4/mode resets. Max312096 cycles per search, maxaddress8433. This run used the original32-bit work counter; a separate160x90/R8 production run tests the narrowed current counter and maximum tile size. Standalone probe r2 matches the narrowed-counter source; r1 was before narrowing. Whole build colorshading_runs_20261025_v65_reacquire_r1 is pending.

## OSD completion
SW1/SW2 now spell out 自动/锁定; control panel672x54, four168px columns. Mode12 recovering displays 搜索中. All other v64 enlarged Chinese labels, FPS/PROC placement, Logo,3-pixel boxes remain. Font fills the existing128 glyph slots/2048 words exactly; retired mode13 no longer needs 均, whose slot is reused for 搜, with 索/定 in the two formerly free slots. No extra font RAM. reports/osd_v65/render.log passes1843200 nonunknown pixels, two actual RTL-composed frames, qualifiers and brief HOLD filtering.

## Independent preview validation
The inherited font simulator returned rows combinationally although the actual ERAM has a clocked read. Independent pixel checks caught four erroneous edge pixels in XY text. Only the simulator was corrected to one-clock synchronous reads; production RTL was already wired for synchronous ROM. render_sync.log passes both720p frames with zero warnings/errors. scripts/validate_osd_v65.py additionally checks28 entire text rectangles against independently placed ROM glyphs, exact Logo palette/position, all2048 MIF/HEX words, and128 glyph slots. Actual synchronous-model screenshots are frame0.png/frame1.png. Earlier render.log screenshots are superseded.

Shared-arena tracker probe r2 (post counter narrowing):1799 physical Slice,0 BRAM,0 DSP; setup +2.919ns,hold +0.058ns,TNS0. This excludes the existing CNN RAM provider and is not an integrated increment. Source hashes and reports retained under reports/reacquire_v65/probe.
