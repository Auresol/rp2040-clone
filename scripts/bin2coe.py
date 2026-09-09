#!/usr/bin/env python3
"""Convert a raw RISC-V .bin firmware file to a Xilinx .coe for BRAM init.

Usage: bin2coe.py <input.bin> <output.coe> [depth_words]

depth_words: number of 32-bit words in the BRAM (default 16384 = 64KB).
Unused words are filled with zero.
"""

import sys
import struct

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.coe> [depth_words]")
        sys.exit(1)

    bin_path  = sys.argv[1]
    coe_path  = sys.argv[2]
    depth     = int(sys.argv[3]) if len(sys.argv) > 3 else 16384  # 64KB default

    with open(bin_path, "rb") as f:
        data = f.read()

    # Pad to word boundary
    if len(data) % 4:
        data += b'\x00' * (4 - len(data) % 4)

    words = struct.unpack(f"<{len(data)//4}I", data)

    if len(words) > depth:
        print(f"ERROR: firmware ({len(words)} words) exceeds BRAM depth ({depth} words)")
        sys.exit(1)

    with open(coe_path, "w") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        all_words = list(words) + [0] * (depth - len(words))
        for i, w in enumerate(all_words):
            sep = "," if i < depth - 1 else ";"
            f.write(f"{w:08x}{sep}\n")

    print(f"Written {len(words)} words ({len(data)} bytes) into {coe_path} (depth={depth})")

if __name__ == "__main__":
    main()
