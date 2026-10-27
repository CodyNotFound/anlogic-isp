# v57 tracker constant coefficients and storage follow-up

The active source replaces the four generic signed rotation products with exact shift/add coefficient functions. All 2048 signed-input/bank combinations and all 2304 template gradients match the prior implementation. Motion, blank rejection and mode reset also match.

Standalone synthesis with identical settings: 2983 -> 2748 estimated Slices; 3515 -> 3250 LUT; 768 M-Slice unchanged. These are synthesis figures, not final physical resource savings. Full integrated build remains isolated and pending.

The v55 whole-board baseline has passed routed timing: 20820/21216 physical Slices, 108/108 RAM, 39/40 DSP, setup +0.022 ns, hold +0.020 ns. The bit is generated; no board acceptance is claimed. Archive validation is running separately.

The v58 storage experiment under reports/yunet_v58 is NOT active RTL. It reuses idle CNN feature RAM for packed 9-bit template gradients and 18-bit scores. Independent before/after synthesis and actual-CNN-RAM equivalence tests are running. It will not be adopted without numerical and frame-time checks. Existing active build inputs remain frozen.
