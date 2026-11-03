"""Packs build/icon*.png into build/icon.ico (PNG-compressed ICO entries)."""
import struct, sys, os
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build")
entries = [(256, "icon.png"), (48, "icon_48.png"), (32, "icon_32.png"), (16, "icon_16.png")]
blobs = [open(os.path.join(root, f), "rb").read() for _, f in entries]
header = struct.pack("<HHH", 0, 1, len(entries))
offset = 6 + 16 * len(entries)
dirs = b""
for (size, _), data in zip(entries, blobs):
    dim = 0 if size == 256 else size
    dirs += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
open(os.path.join(root, "icon.ico"), "wb").write(header + dirs + b"".join(blobs))
print("icon.ico written")
