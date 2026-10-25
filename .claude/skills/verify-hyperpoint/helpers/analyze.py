"""Summarize a probe recording. Usage: analyze.py posted|wheel|senders|hold|keys <file>"""
import collections
import re
import statistics
import sys

mode, path = sys.argv[1].split("-")[0], sys.argv[2]
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
elif mode == "hold":
    events = []
    for line in lines:
        m = re.match(r"([\d.]+) scroll ours=(\d) dy=(-?\d+) dx=(-?\d+) phase=(\d+) momentum=(\d+) cursor=(-?\d+),(-?\d+)", line)
        if m:
            events.append(dict(t=float(m[1]), kind="scroll", ours=int(m[2]), dy=int(m[3]), dx=int(m[4]), phase=int(m[5]),
                               momentum=int(m[6]), x=int(m[7]), y=int(m[8])))
            continue
        m = re.match(r"([\d.]+) button=(\d+) (\w+) ours=(\d) cursor=(-?\d+),(-?\d+)", line)
        if m:
            events.append(dict(t=float(m[1]), kind=m[3], button=int(m[2]), ours=int(m[4]), x=int(m[5]), y=int(m[6])))
    buttons = collections.Counter((e["button"], e["kind"], "replayed" if e["ours"] else "native") for e in events if e["kind"] != "scroll")
    print("button events apps saw:", dict(sorted(buttons.items())))
    gestures = []
    for e in (e for e in events if e["kind"] == "scroll" and e["ours"]):
        if e["phase"] == 1:
            gestures.append(dict(start=e["t"], x=e["x"], y=e["y"], frames=0, dy=0, dx=0, glide=0, glide_dy=0, glide_dx=0,
                                 drift=0, ended=False, glide_ended=False))
        if not gestures:
            continue
        g = gestures[-1]
        if e["momentum"] == 0:
            g["frames"] += 1
            g["dy"] += e["dy"]
            g["dx"] += e["dx"]
            g["drift"] = max(g["drift"], abs(e["x"] - g["x"]) + abs(e["y"] - g["y"]))
            g["ended"] |= e["phase"] == 4
        else:
            g["glide"] += 1
            g["glide_dy"] += e["dy"]
            g["glide_dx"] += e["dx"]
            g["glide_ended"] |= e["momentum"] == 3
    for g in gestures:
        print(f"scroll at {g['start']:.0f}ms: hand frames={g['frames']} dy={g['dy']} dx={g['dx']} ended={g['ended']}"
              f" pointer-drift={g['drift']}pt glide frames={g['glide']} dy={g['glide_dy']} dx={g['glide_dx']}"
              f" glide-ended={g['glide_ended']}")
elif mode == "keys":
    names = {1: "s", 36: "return", 53: "escape", 56: "leftShift", 58: "leftOption", 61: "rightOption", 105: "f13"}
    groups = collections.Counter()
    for line in lines:
        m = re.match(r"[\d.]+ (in|app) (\w+) key=(\w+) repeat=(\d) flags=(\S+) ours=(\d) sender=(\S+)", line)
        if m:
            key = names.get(int(m[3]), m[3]) if m[3].isdigit() else m[3]
            groups[(m[1], m[2], key, m[4], m[5], m[6], m[7])] += 1
    for (stage, kind, key, repeat, flags, ours, sender), n in groups.items():
        print(f"{stage:3} {kind:5} {key:11} repeat={repeat} flags={flags} ours={ours} sender={sender}: {n}")
    for line in lines:
        if "hidSystemState" in line or line.startswith("carbonHotkeyFired"):
            print(line)
else:
    print("\n".join(lines))
