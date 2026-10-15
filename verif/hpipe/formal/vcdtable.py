#!/usr/bin/env python3
"""Print a per-step table of selected signals from an sby trace VCD.
usage: vcdtable.py trace.vcd sig1 sig2 ...   (signal = leaf name or a.b.leaf suffix)
Values are sampled at the clock's rising edges (the first signal named 'HCLK')."""
import sys

def parse(path):
    ids, scope, vals, times = {}, [], {}, []
    cur = 0
    changes = []
    with open(path) as f:
        it = iter(f)
        for line in it:
            t = line.split()
            if not t:
                continue
            if t[0] == '$scope':
                scope.append(t[2])
            elif t[0] == '$upscope':
                scope.pop()
            elif t[0] == '$var':
                name = '.'.join(scope + [t[4]])
                ids.setdefault(t[3], []).append(name)
            elif t[0].startswith('#'):
                cur = int(t[0][1:])
            elif t[0][0] in 'b':
                changes.append((cur, t[1], t[0][1:]))
            elif t[0][0] in '01xz' and len(t[0]) > 1:
                changes.append((cur, t[0][1:], t[0][0]))
    return ids, changes

def main():
    path, sigs = sys.argv[1], sys.argv[2:]
    ids, changes = parse(path)
    name2id = {}
    for i, names in ids.items():
        for n in names:
            name2id[n] = i
    def find(s):
        cands = [n for n in name2id if n == s or n.endswith('.' + s)]
        cands.sort(key=len)
        return name2id[cands[0]] if cands else None
    sid = {s: find(s) for s in sigs}
    clk = find('HCLK')
    state, rows = {}, []
    last_t = None
    by_t = {}
    for t, i, v in changes:
        by_t.setdefault(t, []).append((i, v))
    prev_clk = '0'
    for t in sorted(by_t):
        for i, v in by_t[t]:
            state[i] = v
        c = state.get(clk, '0')
        if c == '1' and prev_clk != '1':
            rows.append({s: state.get(sid[s], '?') if sid[s] else 'NA' for s in sigs})
        prev_clk = c
    def fmt(v):
        if v in ('NA', '?'):
            return v
        try:
            return hex(int(v, 2))[2:] if len(v) > 1 else v
        except ValueError:
            return v
    w = {s: max(len(s), 6) for s in sigs}
    print('step ' + ' '.join(s[-w[s]:].rjust(w[s]) for s in sigs))
    for k, r in enumerate(rows):
        print(f'{k:4d} ' + ' '.join(fmt(r[s]).rjust(w[s]) for s in sigs))

if __name__ == '__main__':
    main()
