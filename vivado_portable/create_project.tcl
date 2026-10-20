set script_dir [file normalize [file dirname [info script]]]
cd $script_dir
set project_dir [file join $script_dir "build"]

create_project tinycnn_uart $project_dir -part xc7a35tcpg236-1 -force

add_files [glob [file join $script_dir "*.v"]]
add_files -fileset constrs_1 [file join $script_dir "tinycnn_uart_basys3.xdc"]

set_property top tinycnn_uart_top [current_fileset]
update_compile_order -fileset sources_1

puts "Portable project created at: $project_dir"
puts "ROM directory: [file join $script_dir rom]"
puts "ROM files: [glob [file join $script_dir rom *.mem]]"
