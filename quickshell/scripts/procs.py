#!/usr/bin/env python3
"""Process and performance data for the Task Manager (popups/TaskManager.qml).

Usage: procs.py [--interval SECONDS] [--once]
Prints one JSON object per line every interval (default 2 s) until stdin closes or it is killed;
Quickshell runs it only while the Task Manager is open. --once prints a single sample.

{ "cpu": %, "mem": {used, total}, "swap": {used, total},
  "gpu": {busy, vramUsed, vramTotal} or null, "count": processes,
  "groups": [{ name, count, cpu, mem, mine, pids }] }      (bytes for memory, % of the whole CPU)

Processes are grouped by program: the executable's name when readable (so browser helper
processes fold into their browser), else the kernel's short name. Kernel threads are skipped.
Memory is RSS summed per group, an estimate (shared pages are counted in every process).
The GPU is the card with the most VRAM (amdgpu sysfs). Standard library only.
"""
import glob
import json
import os
import sys
import time

PAGE = os.sysconf("SC_PAGE_SIZE")
ME = os.getuid()
PF_KTHREAD = 0x00200000


def cpu_times():
    with open("/proc/stat") as f:
        parts = [int(x) for x in f.readline().split()[1:]]
    idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
    return sum(parts), idle


def meminfo():
    kb = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            kb[k] = int(v.split()[0])
    total, avail = kb.get("MemTotal", 0), kb.get("MemAvailable", 0)
    st, sf = kb.get("SwapTotal", 0), kb.get("SwapFree", 0)
    return {"used": (total - avail) * 1024, "total": total * 1024}, {"used": (st - sf) * 1024, "total": st * 1024}


def gpu_card():
    best, size = None, -1
    for dev in glob.glob("/sys/class/drm/card*/device"):
        try:
            with open(dev + "/mem_info_vram_total") as f:
                total = int(f.read())
        except (OSError, ValueError):
            continue
        if total > size:
            best, size = dev, total
    return best


def gpu_info(dev):
    if not dev:
        return None
    try:
        def read(name):
            with open(os.path.join(dev, name)) as f:
                return int(f.read())
        return {"busy": read("gpu_busy_percent"), "vramUsed": read("mem_info_vram_used"), "vramTotal": read("mem_info_vram_total")}
    except (OSError, ValueError):
        return None


def processes():
    """pid -> (name, ticks, rss bytes, mine)"""
    out = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        pid = int(d)
        try:
            with open(f"/proc/{d}/stat") as f:
                stat = f.read()
            comm = stat[stat.index("(") + 1:stat.rindex(")")]
            fields = stat[stat.rindex(")") + 2:].split()
            # fields[0] is the state (field 3); flags = field 9, utime/stime = 14/15
            if int(fields[6]) & PF_KTHREAD:
                continue
            ticks = int(fields[11]) + int(fields[12])
            with open(f"/proc/{d}/statm") as f:
                rss = int(f.read().split()[1]) * PAGE
            mine = os.stat(f"/proc/{d}").st_uid == ME
        except (OSError, ValueError, IndexError):
            continue
        name = comm
        try:
            name = os.path.basename(os.readlink(f"/proc/{d}/exe")).replace(" (deleted)", "") or comm
        except OSError:
            pass
        out[pid] = (name, ticks, rss, mine)
    return out


def sample(prev, card):
    total, idle = cpu_times()
    procs = processes()
    dt = max(1, total - prev["total"])
    cpu = 100.0 * (1 - (idle - prev["idle"]) / dt) if prev["total"] else 0.0
    groups = {}
    for pid, (name, ticks, rss, mine) in procs.items():
        g = groups.setdefault(name, {"name": name, "count": 0, "cpu": 0.0, "mem": 0, "mine": False, "pids": []})
        g["count"] += 1
        g["mem"] += rss
        g["mine"] = g["mine"] or mine
        g["pids"].append(pid)
        before = prev["ticks"].get(pid)
        if before is not None and prev["total"]:
            g["cpu"] += 100.0 * max(0, ticks - before) / dt
    mem, swap = meminfo()
    result = {
        "cpu": round(max(0.0, min(100.0, cpu)), 1),
        "mem": mem, "swap": swap, "gpu": gpu_info(card),
        "count": len(procs),
        "groups": sorted(({**g, "cpu": round(g["cpu"], 1)} for g in groups.values()), key=lambda g: (-g["cpu"], -g["mem"])),
    }
    state = {"total": total, "idle": idle, "ticks": {pid: p[1] for pid, p in procs.items()}}
    return result, state


def main():
    args = sys.argv[1:]
    interval = 2.0
    if "--interval" in args:
        interval = max(0.5, float(args[args.index("--interval") + 1]))
    once = "--once" in args
    card = gpu_card()
    state = {"total": 0, "idle": 0, "ticks": {}}
    # First sample only primes the CPU counters
    _, state = sample(state, card)
    time.sleep(0.5 if once else min(interval, 1.0))
    while True:
        result, state = sample(state, card)
        try:
            print(json.dumps(result), flush=True)
        except BrokenPipeError:
            return
        if once:
            return
        time.sleep(interval)


if __name__ == "__main__":
    main()
