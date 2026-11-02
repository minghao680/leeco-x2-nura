#!/usr/bin/env python3
"""Parse a probe.S "black box" record out of a console-ramoops dump.

The payload writes (at the console prz data area, which becomes the
console-ramoops file content):
    data[0..7]     "LKPROBE1"
    data[8..15]    x0 (DTB pointer from lk2nd)
    data[16..23]   CurrentEL
    data[24..31]   SCTLR_EL1
    data[32..]     first 16384 bytes at [x0]
    ...            smc ret, cmdline dump (see payload/probe.S)

Usage: parse-probe.py <console-ramoops-file-or-console.log>
"""

import struct
import sys

DTB_OFF = 32
DTB_LEN = 16384
CMD_OFF = 16420


def getprop(dtb, name):
    off_st = struct.unpack('>I', dtb[8:12])[0]
    off_str = struct.unpack('>I', dtb[12:16])[0]
    size_st = struct.unpack('>I', dtb[36:40])[0]
    idx = dtb.find(name.encode() + b'\x00', off_str)
    if idx < 0:
        return None
    nameoff = idx - off_str
    pos, end = off_st, off_st + size_st
    stack = []
    while pos < end:
        token, = struct.unpack('>I', dtb[pos:pos + 4]); pos += 4
        if token == 1:
            e = dtb.find(b'\x00', pos)
            name = dtb[pos:e].decode(errors='replace')
            stack.append(name)
            pos = (e + 4) & ~3
        elif token == 2:
            stack.pop()
        elif token == 3:
            plen, noff = struct.unpack('>II', dtb[pos:pos + 8]); pos += 8
            pname = dtb[off_str + noff:dtb.find(b'\x00', off_str + noff)].decode(errors='replace')
            val = dtb[pos:pos + plen]
            pos = (pos + plen + 3) & ~3
            if pname == name:
                return '/'.join(stack), val
        elif token == 9:
            break
    return None


def main(path):
    data = open(path, 'rb').read()
    if data[:8] != b'LKPROBE1':
        # the record may be followed/appended by 3.18 logs; find banner
        i = data.find(b'LKPROBE1')
        if i < 0:
            print('no LKPROBE1 record found (file may be a plain kernel log)')
            return 1
        data = data[i:]
    x0, = struct.unpack('<Q', data[8:16])
    el, = struct.unpack('<Q', data[16:24])
    sctlr, = struct.unpack('<Q', data[24:32])
    print(f'x0 (DTB ptr)   = {x0:#x}')
    print(f'CurrentEL      = {el:#x}  (EL{(el >> 2) & 3})')
    print(f'SCTLR_EL1      = {sctlr:#x}  (M={sctlr & 1}, C={(sctlr >> 2) & 1}, I={(sctlr >> 12) & 1})')

    dtb = data[DTB_OFF:DTB_OFF + DTB_LEN]
    if dtb[:4] != b'\xd0\x0d\xfe\xed':
        print(f'DTB dump invalid: magic={dtb[:4].hex()}')
        return 1
    total, = struct.unpack('>I', dtb[4:8])
    print(f'DTB totalsize  = {total}')

    for prop in ('qcom,msm-id', 'qcom,board-id', 'qcom,pmic-id'):
        r = getprop(dtb, prop)
        if r:
            path_, v = r
            cells = ' '.join(f'{x:#x}' for x in struct.unpack(f'>{len(v)//4}I', v)) if len(v) % 4 == 0 else v.hex()
            print(f'{prop:<14} = {cells}   (at {path_})')

    # memory node (lk2nd rewrites the reg)
    r = getprop(dtb, 'reg')
    mem = None
    # walk for /memory node specifically
    off_st = struct.unpack('>I', dtb[8:12])[0]
    off_str = struct.unpack('>I', dtb[12:16])[0]
    size_st = struct.unpack('>I', dtb[36:40])[0]
    pos, end = off_st, off_st + size_st
    stack = []
    while pos < end:
        token, = struct.unpack('>I', dtb[pos:pos + 4]); pos += 4
        if token == 1:
            e = dtb.find(b'\x00', pos)
            stack.append(dtb[pos:e].decode(errors='replace'))
            pos = (e + 4) & ~3
        elif token == 2:
            stack.pop()
        elif token == 3:
            plen, noff = struct.unpack('>II', dtb[pos:pos + 8]); pos += 8
            pname = dtb[off_str + noff:dtb.find(b'\x00', off_str + noff)].decode(errors='replace')
            cur = '/'.join(stack)
            val = dtb[pos:pos + plen]
            pos = (pos + plen + 3) & ~3
            if stack and stack[-1].startswith('memory@') and pname == 'reg' and plen <= 64:
                cells = struct.unpack(f'>{len(val)//4}I', val)
                print(f'memory node    = {stack[-1]} reg=' +
                      ' '.join(f'{c:#x}' for c in cells))
            if cur == 'chosen' and pname == 'bootargs':
                print(f'bootargs       = {val.decode(errors="replace")[:200]}')
        elif token == 9:
            break

    cmd = data[CMD_OFF:CMD_OFF + 256]
    if cmd[:8] not in (b'NOCONSOL',):
        print(f'cmdline dump   = {cmd.split(b"\x00")[0].decode(errors="replace")[:200]}')
    else:
        print('cmdline dump   = NOT FOUND in dumped range')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
