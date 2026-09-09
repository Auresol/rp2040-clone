#!/usr/bin/env python3
"""Convert a raw RISC-V .bin firmware file to a .mem file for $readmemh.

Usage: bin2mem.py <input.bin> <output.mem> [depth_words]

Output: one hex word per line, little-endian 32-bit words.
depth_words: number of 32-bit words (default 16384 = 64KB). Unused words filled with 0.
"""

import sys
import struct

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.mem> [depth_words]")
        sys.exit(1)

    bin_path  = sys.argv[1]
    mem_path  = sys.argv[2]
    depth     = int(sys.argv[3]) if len(sys.argv) > 3 else 16384

    with open(bin_path, "rb") as f:
        data = f.read()

    if len(data) % 4:
        data += b'\x00' * (4 - len(data) % 4)

    words = list(struct.unpack(f"<{len(data)//4}I", data))

    if len(words) > depth:
        print(f"ERROR: firmware ({len(words)} words) exceeds BRAM depth ({depth} words)")
        sys.exit(1)

    words += [0] * (depth - len(words))

    with open(mem_path, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")

    print(f"Written {len(words)} words to {mem_path}")

if __name__ == "__main__":
    main()
