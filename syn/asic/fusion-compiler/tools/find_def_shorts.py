#!/usr/bin/env python3
"""
find_def_shorts.py — surface routing Shorts in a DEF by detecting
same-layer different-net rectangle overlaps.

Background: FS-COMPILER_2022.12's fc_shell does NOT expose
check_routes DRC error markers as a queryable error_data block
(4 escalating probes proved this — see INTEGRATION_CHANGES.md).
The routed wires themselves, however, ARE in the exported DEF
with full net + layer + bbox. Two segments on the same layer
belonging to DIFFERENT nets whose inflated rectangles intersect =
a Short (geometric definition; matches the LEF DRC engine's notion).

Usage:
    python3 find_def_shorts.py <def_file> [--max-output N] [--inflate K]

Implementation notes (v2, 2026-05-20):
- Single-pass line-by-line state-machine parser (v1 regex-on-MB-text
  was ~15× too slow on the 7.9 MB partition DEF).
- Handles DEF '*' shorthand for L-bends / same-axis continuation.
- Walks both NETS and SPECIALNETS so signal-vs-PG shorts surface too.
- Per-layer grid bucketing (10 µm cells) for fast overlap detection.
"""

import sys
import argparse
from collections import defaultdict


# Approximate sc12 cln65lp default wire widths in DBU (DEF UNITS DISTANCE
# MICRONS 1000 → DBU = 1 nm). PG straps from pg_mesh.tcl are 2 µm wide
# on M5/M6 — handled separately by inflating SPECIALNETS extra.
LAYER_DEFAULT_WIDTH_DBU = {
    'M1': 100, 'M2': 100, 'M3': 100, 'M4': 200,
    'M5': 200, 'M6': 200, 'M7': 400, 'M8': 800, 'M9': 1600,
    'AP': 5000,
}
PG_STRAP_WIDTH_DBU = 2000  # 2 µm — from pg_mesh.tcl mesh pattern width


def parse_def_segments(path):
    """Line-by-line parse. Return:
       segments: list of (layer, x1, y1, x2, y2, net, is_pg)."""
    segs = []
    in_nets = in_specialnets = False
    cur_net = None
    cur_is_pg = False
    cur_layer = None
    cur_x = cur_y = None

    def flush_line(line, net, is_pg):
        """Walk one routing-thread line; emit segments."""
        nonlocal cur_layer, cur_x, cur_y
        # Strip the leading + ROUTED or NEW token AND get the layer
        s = line.lstrip()
        if s.startswith('+'):
            s = s[1:].lstrip()
        if s.startswith('ROUTED'):
            s = s[len('ROUTED'):].lstrip()
            cur_x = cur_y = None  # new routing thread → coords reset
        elif s.startswith('NEW'):
            s = s[len('NEW'):].lstrip()
            cur_x = cur_y = None
        else:
            return
        # First token = layer
        parts = s.split(None, 1)
        if not parts:
            return
        cur_layer = parts[0]
        rest = parts[1] if len(parts) > 1 else ''
        # Scan rest for "( tok1 tok2 )" coord pairs IN ORDER. Stop at
        # '+' (next property) or ';' (end of net).
        i = 0
        n = len(rest)
        while i < n:
            ch = rest[i]
            if ch == ';' or ch == '+':
                break
            if ch == '(':
                # Find matching ')'
                j = rest.find(')', i + 1)
                if j < 0:
                    break
                inner = rest[i+1:j].strip()
                toks = inner.split()
                if len(toks) >= 2:
                    tx, ty = toks[0], toks[1]
                    # Skip RECT / MASK / NDR-syntax tuples
                    if (tx not in ('RECT', 'MASK', 'VIRTUAL') and
                            ty not in ('RECT', 'MASK', 'VIRTUAL')):
                        try:
                            nx = cur_x if tx == '*' else int(tx)
                            ny = cur_y if ty == '*' else int(ty)
                        except (TypeError, ValueError):
                            nx = ny = None
                        if nx is not None and ny is not None:
                            if (cur_x is not None and cur_y is not None
                                    and (nx, ny) != (cur_x, cur_y)):
                                segs.append((cur_layer, cur_x, cur_y,
                                             nx, ny, net, is_pg))
                            cur_x, cur_y = nx, ny
                i = j + 1
            else:
                i += 1

    with open(path) as f:
        for raw in f:
            line = raw.rstrip('\n')
            stripped = line.lstrip()
            if not stripped:
                continue
            # Section markers
            if stripped.startswith('NETS '):
                in_nets, in_specialnets = True, False
                continue
            if stripped.startswith('SPECIALNETS '):
                in_nets, in_specialnets = False, True
                continue
            if stripped.startswith('END NETS') or stripped.startswith('END SPECIALNETS'):
                in_nets = in_specialnets = False
                continue
            if not (in_nets or in_specialnets):
                continue
            # New net?
            if stripped.startswith('- '):
                # "- <name>" — name may be braced, may have routing on
                # the same line in compact DEFs (rare; we handle next-line)
                tok = stripped[2:].split(None, 1)
                if tok:
                    cur_net = tok[0].strip('{}')
                    cur_is_pg = in_specialnets
                    cur_x = cur_y = None
                continue
            # Routing line: starts with '+ ROUTED' (first routing
            # thread of this net) or 'NEW' (subsequent thread) or
            # '+ USE / + NONDEFAULTRULE / ;' (properties/end).
            if 'ROUTED' in stripped[:20] or stripped.startswith('NEW '):
                flush_line(line, cur_net, cur_is_pg)
            # Other '+' lines (USE, NONDEFAULTRULE, SHIELD…) just ignored
    return segs


def rect_for(seg, hw, pg_extra_hw):
    layer, x1, y1, x2, y2, net, is_pg = seg
    h = hw + (pg_extra_hw if is_pg else 0)
    xlo, xhi = (x1, x2) if x1 <= x2 else (x2, x1)
    ylo, yhi = (y1, y2) if y1 <= y2 else (y2, y1)
    return (xlo - h, ylo - h, xhi + h, yhi + h)


def overlap(a, b):
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    ox0 = max(ax0, bx0); oy0 = max(ay0, by0)
    ox1 = min(ax1, bx1); oy1 = min(ay1, by1)
    if ox0 < ox1 and oy0 < oy1:
        return (ox0, oy0, ox1, oy1)
    return None


def find_shorts(segs, extra_inflate=0):
    """Group segments per layer, bucket-grid-index, find overlap
    between different-net pairs."""
    BS = 10000  # 10 µm cells (DBU)
    per_layer = defaultdict(list)  # layer -> list of (net, rect, idx)
    layer_items = defaultdict(list)
    for seg in segs:
        layer = seg[0]
        hw = LAYER_DEFAULT_WIDTH_DBU.get(layer, 100) // 2
        pg_extra = (PG_STRAP_WIDTH_DBU - LAYER_DEFAULT_WIDTH_DBU.get(layer, 100)) // 2
        if pg_extra < 0:
            pg_extra = 0
        r = rect_for(seg, hw + extra_inflate, pg_extra)
        layer_items[layer].append((seg[5], r, seg))  # net, rect, seg
    shorts = []
    for layer, items in layer_items.items():
        buckets = defaultdict(list)
        for idx, (net, r, seg) in enumerate(items):
            xlo, ylo, xhi, yhi = r
            for bx in range(xlo // BS, xhi // BS + 1):
                for by in range(ylo // BS, yhi // BS + 1):
                    buckets[(bx, by)].append(idx)
        seen = set()
        for idx_list in buckets.values():
            L = len(idx_list)
            if L < 2:
                continue
            for i in range(L):
                ii = idx_list[i]
                a = items[ii]
                for j in range(i + 1, L):
                    jj = idx_list[j]
                    b = items[jj]
                    if a[0] == b[0]:
                        continue
                    key = (ii, jj) if ii < jj else (jj, ii)
                    if key in seen:
                        continue
                    seen.add(key)
                    ov = overlap(a[1], b[1])
                    if ov:
                        shorts.append((layer, a[0], b[0], ov, a[2], b[2]))
    return shorts


def cluster(shorts, radius_dbu=2000):
    """O(N) cluster — bucket by (layer, pair, grid_cell). Merge candidates
    that share layer + net-pair + nearby grid cell."""
    BS = radius_dbu * 2  # cell size
    by_key = {}  # (layer, pair, gx, gy) -> cluster dict
    for s in shorts:
        layer, na, nb, ov, segA, segB = s
        cx, cy = (ov[0] + ov[2]) // 2, (ov[1] + ov[3]) // 2
        pair = tuple(sorted([na, nb]))
        gx, gy = cx // BS, cy // BS
        # Check 3x3 neighborhood of grid cells
        found = None
        for dgx in (-1, 0, 1):
            for dgy in (-1, 0, 1):
                key = (layer, pair, gx + dgx, gy + dgy)
                if key in by_key:
                    cl = by_key[key]
                    if (abs(cl['cx'] - cx) <= radius_dbu
                            and abs(cl['cy'] - cy) <= radius_dbu):
                        found = cl
                        break
            if found:
                break
        if found:
            found['count'] += 1
            # Keep biggest-area representative
            ox0, oy0, ox1, oy1 = ov
            if (ox1 - ox0) * (oy1 - oy0) > (found['ov'][2] - found['ov'][0]) * (found['ov'][3] - found['ov'][1]):
                found['ov'] = ov
                found['segA'] = segA
                found['segB'] = segB
                found['cx'] = cx
                found['cy'] = cy
        else:
            by_key[(layer, pair, gx, gy)] = {
                'layer': layer, 'pair': pair,
                'cx': cx, 'cy': cy, 'count': 1,
                'segA': segA, 'segB': segB, 'ov': ov,
            }
    return list(by_key.values())


# Patterns for non-functional / synthesized nets to skip
SKIP_NET_PATTERNS = [
    'copt_net_',     # clock-opt buffer outputs
    'ctmn_',          # CTS mesh nets
    'ctmnl_',         # CTS leaf nets
    'HFSNET_',        # high-fanout sub-tree nets
    'ropt_net_',      # route-opt buffer outputs
    'tmp_net',        # synthesized temporaries
    'phfnn_',         # CTS PHF nets
    'ctmi_',          # CTS internal nets
    'ctmTds',         # CTS TDS nets
]

def is_skippable_net(name):
    return any(p in name for p in SKIP_NET_PATTERNS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('def_file')
    ap.add_argument('--max-output', type=int, default=30)
    ap.add_argument('--inflate', type=int, default=0,
                    help='extra rectangle inflation in DBU (default 0)')
    ap.add_argument('--include-pg', action='store_true',
                    help='include SPECIALNETS (PG) — defaults to off because '
                         'PG strap widths are not parsed from the DEF and '
                         'over-inflation produces many false positives')
    ap.add_argument('--include-cts', action='store_true',
                    help='include synthesized/CTS nets — defaults to off; '
                         'these are NDR-routed with widths the parser does '
                         'not know about, producing false-positive overlaps')
    ap.add_argument('--min-area-dbu2', type=int, default=10000,
                    help='minimum overlap area (DBU²) to surface a Short — '
                         'default 10000 = 0.01 µm² filters pin-touch noise')
    ap.add_argument('--show-segments', action='store_true')
    args = ap.parse_args()

    print(f'Parsing {args.def_file} ...', flush=True)
    segs = parse_def_segments(args.def_file)
    if not args.include_pg:
        before = len(segs)
        segs = [s for s in segs if not s[6]]  # is_pg flag
        print(f'  (filtered {before - len(segs)} PG segments;'
              f' use --include-pg to keep them)')
    if not args.include_cts:
        before = len(segs)
        segs = [s for s in segs if not is_skippable_net(s[5])]
        print(f'  (filtered {before - len(segs)} CTS/opt-tmp segments;'
              f' use --include-cts to keep them)')
    nets = {s[5] for s in segs}
    print(f'  {len(nets)} nets, {len(segs)} routed segments\n', flush=True)

    print('Detecting same-layer different-net rectangle overlaps ...',
          flush=True)
    shorts = find_shorts(segs, extra_inflate=args.inflate)
    print(f'  {len(shorts)} raw overlap pairs\n', flush=True)

    cls = cluster(shorts)
    # Annotate each cluster with overlap area + filter by min area
    for cl in cls:
        ox0, oy0, ox1, oy1 = cl['ov']
        cl['area'] = (ox1 - ox0) * (oy1 - oy0)
    cls = [c for c in cls if c['area'] >= args.min_area_dbu2]
    # Sort by overlap area descending: real Shorts have the largest
    # metal-on-metal overlap; pin-touch / via-cross noise has tiny area
    cls.sort(key=lambda c: -c['area'])
    print(f'  {len(cls)} clusters after area filter (>= {args.min_area_dbu2}'
          f' DBU² = {args.min_area_dbu2/1e6:.4f} µm²), sorted by area\n',
          flush=True)

    print(f'{"#":>3}  {"layer":>5}  {"x (µm)":>9}  {"y (µm)":>9}  '
          f'{"area µm²":>10}  {"hits":>4}   net A   /   net B')
    print('-' * 130)
    for i, cl in enumerate(cls[:args.max_output], 1):
        x_um = cl['cx'] / 1000
        y_um = cl['cy'] / 1000
        area_um2 = cl['area'] / 1e6
        a, b = cl['pair']
        print(f'{i:>3}  {cl["layer"]:>5}  {x_um:>9.2f}  {y_um:>9.2f}'
              f'  {area_um2:>10.4f}  {cl["count"]:>4}   {a}  /  {b}')
        if args.show_segments:
            print(f'         segA = {cl["segA"]}')
            print(f'         segB = {cl["segB"]}')


if __name__ == '__main__':
    main()
