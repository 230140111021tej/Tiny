set script_dir [file normalize [file dirname [info script]]]
set project_file [file join $script_dir "build" "tinycnn_uart.xpr"]

open_project $project_file

launch_runs impl_1 -jobs 4
wait_on_run impl_1

puts "IMPLEMENTATION_STATUS: [get_property STATUS [get_runs impl_1]]"
