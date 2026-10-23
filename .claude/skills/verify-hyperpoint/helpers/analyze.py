"""Summarize a probe recording. Usage: analyze.py posted|wheel|senders <file>"""
import collections
import re
import statistics
import sys

mode, path = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()


def gaps(times):
    return [b - a for a, b in zip(times, times[1:])]


if mode == "posted":
    rows = []
    for line in lines:
        m = re.match(r"([\d.]+) ours=(\d) point=(-?\d+) fixed=(\S+) lines=(-?\d+) cont=(\d) phase=(\d+)", line)
        if m:
            rows.append(dict(t=float(m[1]), ours=int(m[2]), point=int(m[3]), fixed=float(m[4]), cont=int(m[6]), phase=int(m[7])))
    leaked = [r for r in rows if not r["ours"] and not r["cont"]]
    print(f"frames={len(rows)} ours={sum(r['ours'] for r in rows)} leaked-line-events={len(leaked)}")
    gestures, current = [], []
    for r in (r for r in rows if r["ours"]):
        if r["phase"] == 1 and current:
            gestures.append(current)
            current = []
        current.append(r)
    if current:
        gestures.append(current)
    for i, g in enumerate(gestures):
        intervals = gaps([r["t"] for r in g])
        print(f"gesture {i}: frames={len(g)} first={[r['fixed'] for r in g[:4]]} total={sum(r['fixed'] for r in g):.1f}"
              f" frame-gap median={statistics.median(intervals) if intervals else 0:.1f}ms max={max(intervals, default=0):.1f}ms")
elif mode == "wheel":
    rows = []
    for line in lines:
        m = re.match(r"([\d.]+) sender=(\S+) raw=(\S+) lines=(-?\d+)", line)
        if m:
            rows.append((float(m[1]), m[2], float(m[3])))
    print("senders:", collections.Counter(r[1] for r in rows))
    bursts, current = [], []
    for r in rows:
        if current and r[0] - current[-1][0] > 400:
            bursts.append(current)
            current = []
        current.append(r)
    if current:
        bursts.append(current)
    for i, b in enumerate(bursts):
        seconds = max((b[-1][0] - b[0][0]) / 1000, 0.001)
        print(f"burst {i}: events={len(b)} rate={len(b) / seconds:.0f}/s detents={sum(abs(r[2]) for r in b):.0f}"
              f" max-detents-per-event={max(abs(r[2]) for r in b):.0f}")
else:
    print("\n".join(lines))
