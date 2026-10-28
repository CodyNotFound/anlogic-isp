# v59 AWB lock and smooth gimbal commands

SW1 ON: AWB AUTO; OFF: HOLD applied R/B gains, never bypass. SW2 ON: sensor AE AUTO; OFF: HOLD last exposure/gain, no default reset and no manual camera-tuning-key leak. A started I2C transaction may finish; the OSD describes requested AUTO/HOLD, not sensor readback. SW3 gates automatic gimbal motion only; analytics, selection and compact OSD remain active. SW4 manual HJKL has priority. AB fixed on as requested. Anlogic Logo retained.

Retarget: SW3 OFF; if necessary SW4 ON to point manually, then SW4 OFF; put new color/template at sampling center and K4; SW3 ON. Face mode automatically detects and does not use K4 color/template sampling.

Automatic motion: every fresh accepted detection generates one bounded endpoint using the previous proportional correction. Commands approach that endpoint by <=8us per 20ms PWM period. Maximum 32us plan takes <=80ms; no fresh result does not generate another increment. Plans expire after 120ms. Loss, manual mode and auto OFF cancel pending motion. Manual fine/accelerated steps and safe axis limits retained. This limits command jerk; it is not servo plant/PID identification and does not prove physical overshoot eliminated. At high detection rates maximum automatic slew is 400us/s, an explicit smoothness/speed tradeoff. Face inference cadence remains about 267ms per core result.

Passed: AWB freeze/resume with pending estimate; switchable AWB stalls; sensor AE freeze/resume; bounded slew, cancellation, stale hold, center deadband, reversal and manual acceleration; full pipeline switch/button mapping. OSD full-frame numerical regression pending. Full board build colorshading_runs_20261025_v59_awb_slew_r1 running, not flashed.

The reports/effects_v60 files are isolated experiments, not part of v59 active RTL. Quantitative synthetic-noise results are not camera noise-reduction claims. Template tracking remains enabled per user lighting observation.
