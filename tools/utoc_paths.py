"""Rebuilds full file paths from the IoStore directory index of the game's .utoc.

Build 25632050's container is not encrypted, so FIoDirectoryIndexResource can
be read straight out of the table of contents. Read-only.

Usage: python utoc_paths.py <out.txt>
"""
import struct
import sys

UTOC = r"C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds\RSDragonwilds\Content\Paks\RSDragonwilds-Windows.utoc"


class R:
    def __init__(self, b, o=0):
        self.b, self.o = b, o

    def u8(self):
        v = self.b[self.o]
        self.o += 1
        return v

    def u16(self):
        v = struct.unpack_from("<H", self.b, self.o)[0]
        self.o += 2
        return v

    def u32(self):
        v = struct.unpack_from("<I", self.b, self.o)[0]
        self.o += 4
        return v

    def i32(self):
        v = struct.unpack_from("<i", self.b, self.o)[0]
        self.o += 4
        return v

    def u64(self):
        v = struct.unpack_from("<Q", self.b, self.o)[0]
        self.o += 8
        return v

    def skip(self, n):
        self.o += n

    def fstring(self):
        n = self.i32()
        if n == 0:
            return ""
        if n > 0:
            s = self.b[self.o:self.o + n - 1].decode("latin-1")
            self.o += n
        else:
            n = -n
            s = self.b[self.o:self.o + 2 * n - 2].decode("utf-16-le")
            self.o += 2 * n
        return s


def main():
    out = sys.argv[1]
    b = open(UTOC, "rb").read()
    r = R(b)
    r.skip(16)
    version = r.u8()
    r.skip(3)
    header_size = r.u32()
    entry_count = r.u32()
    block_count = r.u32()
    block_entry_size = r.u32()
    method_count = r.u32()
    method_len = r.u32()
    r.u32()  # compression block size
    dir_index_size = r.u32()
    r.u32()  # partition count
    r.u64()  # container id
    r.skip(16)  # encryption guid
    flags = r.u8()
    r.skip(3)
    seeds_count = r.u32()
    r.u64()  # partition size
    no_hash_count = r.u32()
    print(f"version {version} header {header_size} entries {entry_count} blocks {block_count} flags 0x{flags:X} dirindex {dir_index_size}")
    o = header_size
    o += entry_count * 12  # chunk ids
    o += entry_count * 10  # offset/lengths
    if version >= 4:
        o += seeds_count * 4
    if version >= 5:
        o += no_hash_count * 4
    o += block_count * block_entry_size
    o += method_count * method_len
    if flags & 4:
        hs = struct.unpack_from("<i", b, o)[0]
        o += 4 + hs * 2 + block_count * 20
    if flags & 2:
        print("encrypted directory index; stopping")
        return
    r = R(b, o)
    mount = r.fstring()
    nd = r.u32()
    dirs = [(r.u32(), r.u32(), r.u32(), r.u32()) for _ in range(nd)]
    nf = r.u32()
    files = [(r.u32(), r.u32(), r.u32()) for _ in range(nf)]
    ns = r.u32()
    strings = [r.fstring() for _ in range(ns)]
    NONE = 0xFFFFFFFF
    paths = []

    def walk(di, prefix):
        name, child, sib, ff = dirs[di]
        here = prefix
        if name != NONE:
            here = prefix + strings[name] + "/"
        f = ff
        while f != NONE:
            fname, nxt, _ = files[f]
            paths.append(here + strings[fname])
            f = nxt
        c = child
        while c != NONE:
            walk(c, here)
            c = dirs[c][2]

    sys.setrecursionlimit(10000)
    walk(0, mount)
    with open(out, "w", encoding="utf-8") as fh:
        for p in sorted(paths):
            fh.write(p + "\n")
    print(f"mount {mount} dirs {nd} files {nf} strings {ns} -> {len(paths)} paths")


if __name__ == "__main__":
    main()
