#!/usr/bin/env python3
"""Expand environment variables in VCS filelists recursively."""
import os, sys, re

def expand_vars(line):
    """Replace $(VAR) and ${VAR} patterns with environment variable values."""
    def repl(m):
        name = m.group(1) or m.group(2)
        val = os.environ.get(name, m.group(0))
        return val
    return re.sub(r'\$\((\w+)\)|\$\{(\w+)\}', repl, line)

def process_flist(fpath, out):
    """Recursively process a filelist, expanding -f references."""
    with open(fpath) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//') or line.startswith('#'):
                continue
            line = expand_vars(line)
            if line.startswith('-f '):
                nested = line[3:].strip()
                process_flist(nested, out)
            else:
                out.append(line)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.flist> <output.flist>")
        sys.exit(1)
    lines = []
    process_flist(sys.argv[1], lines)
    with open(sys.argv[2], 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print(f"  Expanded {len(lines)} entries -> {sys.argv[2]}")
