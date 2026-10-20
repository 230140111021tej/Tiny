set script_dir [file normalize [file dirname [info script]]]
cd $script_dir
set project_file [file join $script_dir "build" "tinycnn_uart.xpr"]

open_project $project_file

set_property top tinycnn_uart_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1

puts "SYNTHESIS_STATUS: [get_property STATUS [get_runs synth_1]]"
