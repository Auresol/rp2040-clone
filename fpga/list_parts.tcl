puts "--- Zynq UltraScale+ parts (xczu*) ---"
foreach p [get_parts -filter {FAMILY =~ *UltraScale*}] {
    puts $p
}

