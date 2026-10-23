#!/usr/bin/env python3
import pathlib, struct, subprocess, sys

if len(sys.argv) < 2:
    sys.exit('Usage: python3 script.py path/to/NanoTimeKit')
p = pathlib.Path(sys.argv[1]); b = p.read_bytes()
U32 = lambda off: struct.unpack_from('<I', b, off)[0]
U64 = lambda off: struct.unpack_from('<Q', b, off)[0]
if U32(0) != 0xfeedfacf:
    sys.exit('Expected thin little-endian Mach-O 64; check file with: file <path>')
ncmds = U32(16); off = 32; segments = []; executable = []
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', b, off)
    if cmd == 0x19:
        name = b[off+8:off+24].split(b'\0')[0].decode('ascii', 'replace')
        va, vs, fo, fs = struct.unpack_from('<QQQQ', b, off+24)
        segments.append((va, va+vs, fo, fo+fs, name))
        nsects = U32(off+64)
        s = off+72
        for __ in range(nsects):
            sect = b[s:s+16].split(b'\0')[0].decode('ascii','replace')
            addr, length = struct.unpack_from('<QQ', b, s+32)
            fileoff, flags = U32(s+48), U32(s+64)
            if (flags & 0x80000000 or flags & 0x00000400) and fileoff+length <= len(b):
                executable.append((addr, fileoff, length, sect))
            s += 80
    off += size

def f2v(pos):
    for va, end, fo, fend, _ in segments:
        if fo <= pos < fend: return va+pos-fo
    return None

def v2f(addr):
    for va, end, fo, fend, _ in segments:
        if va <= addr < va+(fend-fo): return fo+addr-va
    return None

terms = [b'load_unencrypted_argon_bundles', b'/AppleInternal/Library/NanoTimeKit/FaceSupport/UnencryptedBundles/']
strings = {}
for term in terms:
    start = 0
    while (pos := b.find(term, start)) != -1:
        addr = f2v(pos)
        if addr is not None:
            strings[addr] = term.decode()
            print(f'STRING 0x{addr:x} file+0x{pos:x} {term.decode()}')
        start = pos+1
if not strings: sys.exit('Target strings not found in mapped Mach-O segments')

# Find direct pointers to the strings (CFString or other static metadata).
pointers = {}
for i in range(0, len(b)-7, 8):
    val = U64(i)
    if val in strings:
        va = f2v(i)
        if va is not None:
            pointers[va] = strings[val]
            if len(pointers) < 25: print(f'POINTER 0x{va:x} -> 0x{val:x} {strings[val]}')
targets = {**strings, **{k: f'pointer to {v}' for k, v in pointers.items()}}

# Pure-Python ARM64 decoder: ADR, ADRP + ADD, ADRP + LDR unsigned offset.
def sx(x, bits): return x-(1<<bits) if x & (1<<(bits-1)) else x
hits = {}
for base, fo, length, section in executable:
    pending = {}
    for i in range(0, int(length)//4):
        insn = U32(fo+4*i); pc = base+4*i
        rd = insn & 31
        if (insn & 0x9f000000) in (0x90000000, 0x10000000):
            imm = sx(((insn >> 5) & 0x7ffff) << 2 | ((insn >> 29) & 3), 21)
            adrp = (insn & 0x9f000000) == 0x90000000
            target = (pc & ~0xfff)+(imm << 12) if adrp else pc+imm
            pending[rd] = (target, pc, i, adrp)
            if target in targets:
                hits[pc] = (target, 'ADRP page' if adrp else 'ADR')
        elif (insn & 0xff000000) == 0x91000000:  # ADD Xd, Xn, #imm
            rn = (insn >> 5) & 31
            if rn in pending:
                start, pc0, i0, adrp = pending[rn]
                if i-i0 <= 10 and adrp:
                    imm = ((insn >> 10) & 0xfff) << (12 if ((insn>>22)&1) else 0)
                    target = start + imm
                    pending[rd] = (target, pc0, i, False)
                    if target in targets: hits[pc] = (target, f'ADRP+ADD from 0x{pc0:x}')
        elif (insn & 0xffc00000) in (0xf9400000, 0xb9400000):
            rn = (insn >> 5) & 31
            if rn in pending:
                start, pc0, i0, adrp = pending[rn]
                if i-i0 <= 10:
                    scale = 8 if (insn & 0xffc00000) == 0xf9400000 else 4
                    addr = start + ((insn >> 10) & 0xfff)*scale
                    if addr in targets:
                        hits[pc] = (addr, f'ADRP+LDR from 0x{pc0:x}')
        if i % 256 == 0: pending.clear()

print(f'\nSummary: {len(strings)} strings; {len(pointers)} direct pointers; {len(hits)} potential code references')
for pc, (target, kind) in sorted(hits.items()):
    print(f'\nXREF 0x{pc:x} -> 0x{target:x} [{kind}] {targets[target]}')
    cmd = ['xcrun', 'llvm-objdump', '--macho', '--disassemble',
           f'--start-address=0x{max(0,pc-40):x}', f'--stop-address=0x{pc+64:x}', str(p)]
    r = subprocess.run(cmd, text=True, encoding='utf-8', errors='replace', capture_output=True)
    if r.returncode == 0:
        print('\n'.join(r.stdout.splitlines()[-30:]))
    else:
        print('objdump:', r.stderr.strip()[:300])
if not hits:
    print('No direct ARM64 reference found. String could be accessed via dyld chained fixups,')
    print('CFString indirection, or shared-cache pointers. This is not proof it is unused.')
