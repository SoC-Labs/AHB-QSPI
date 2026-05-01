#!/usr/bin/env python3
"""Recursively flatten nested -f includes in VCS-style flists and convert
$(VAR) references to ${VAR} so SpyGlass can resolve environment variables."""

import re
import os
import sys


def resolve(path):
    lines = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            # Convert $(VAR) to ${VAR}
            line = re.sub(r"\$\((\w+)\)", r"${\1}", line)
            # Recurse into -f includes
            m = re.match(r"-f\s+(.*)", line)
            if m:
                inc = m.group(1).strip()
                # Resolve ${VAR} for the file path so we can open it
                inc_resolved = re.sub(
                    r"\$\{(\w+)\}",
                    lambda m: os.environ.get(m.group(1), m.group(0)),
                    inc,
                )
                lines.extend(resolve(inc_resolved))
            else:
                lines.append(line)
    return lines


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.flist> <output.flist>", file=sys.stderr)
        sys.exit(1)

    result = resolve(sys.argv[1])
    with open(sys.argv[2], "w") as f:
        f.write("\n".join(result) + "\n")
    print(f"  Wrote {len(result)} lines to {sys.argv[2]}")
