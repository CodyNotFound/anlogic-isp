# Called by verify_build.ps1 after TD has finished routing. No netlist edits.
# The wrapper supplies route_db and audit_dir, both absolute paths.
if {![info exists route_db] || ![info exists audit_dir]} {
    error "route_db and audit_dir must be supplied by the wrapper"
}
if {![file exists $route_db]} {error "Routed database missing"}
proc collect_sta_evidence {route_db audit_dir} {
file mkdir $audit_dir
cd $audit_dir
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db $route_db
update_timing -mode final
report_timing_status -file audit_status.ts
check_timing -verbose -file check_timing.rpt
report_timing_ignored -file ignored_paths.timing -ep_num 200
report_abnormal_timing_target -file abnormal_targets.rpt
foreach {wanted pattern} {check_timing.rpt *.check_timing ignored_paths.timing *.timingignored abnormal_targets.rpt *.abnormal_timing_target} {
    if {![file exists $wanted]} {
        set candidates [glob -nocomplain $pattern]
        if {[llength $candidates]!=1} {error "Missing or ambiguous STA report: $wanted"}
        file copy -force [lindex $candidates 0] $wanted
    }
}
set f [open reset_coverage.txt w]
foreach pattern {*u_video_in*asy_w_rst* *u_video_in*asy_r_rst* *u_video_out*asy_w_rst* *u_video_out*asy_r_rst* *u_camera_raw_clock_bridge*asy_w_rst* *u_camera_raw_clock_bridge*asy_r_rst* *u_reset_*/release_ff*} {
    set matches [get_regs -nowarn $pattern]
    puts $f "$pattern : [llength $matches] : $matches"
}
close $f
}
collect_sta_evidence $route_db $audit_dir
