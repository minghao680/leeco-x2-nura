#!/usr/bin/env python3
"""Register msm8996-leeco-x2.dtb in lk2nd's msm8996 rules.mk.

lk2nd declares ADTBS as a single backslash-continued assignment:

    ADTBS += \
        $(LOCAL_DIR)/foo.dtb \
        $(LOCAL_DIR)/bar.dtb

so the new entry has to go at the END of that assignment, and the previous
last line must keep its trailing backslash. Appending a separate line would
silently create a second statement and make the build fail with
"No rule to make target build-*/ADTBS".
"""

import sys

DTB_ENTRY = "\t$(LOCAL_DIR)/msm8996-leeco-x2.dtb"


def main(path: str) -> int:
    with open(path) as f:
        lines = f.read().split("\n")

    if any("leeco-x2" in line for line in lines):
        print("already registered, nothing to do")
        return 0

    try:
        start = next(i for i, l in enumerate(lines) if l.startswith("ADTBS"))
    except StopIteration:
        print("ERROR: no ADTBS assignment found", file=sys.stderr)
        return 1

    end = start
    while end < len(lines) - 1 and lines[end].rstrip().endswith("\\"):
        end += 1

    last = lines[end].rstrip()
    if last.endswith("\\"):
        # The assignment continues past what we found; keep the backslash
        # on the previous line and add ours with one as well.
        lines[end] = last[:-1].rstrip() + " \\"
        lines.insert(end + 1, DTB_ENTRY + " \\")
    else:
        # 'end' is the final entry; move the continuation onto it.
        lines[end] = last + " \\"
        lines.insert(end + 1, DTB_ENTRY)

    with open(path, "w") as f:
        f.write("\n".join(lines))

    print("added msm8996-leeco-x2.dtb to", path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
