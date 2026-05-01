#!/usr/bin/env python3
"""Parse benchmark CSV and produce plots for throughput and fc batch scaling."""
import os
import re
from collections import defaultdict
import matplotlib.pyplot as plt

INPUT = os.path.join(os.path.dirname(__file__), '..', 'bench', 'results', 'benchmark_matrix_5000.csv')
OUTDIR = os.path.join(os.path.dirname(__file__), '..', 'bench', 'results', 'plots')

def parse_line(line):
    parts = line.strip().split(',')
    if not parts or len(parts) < 2:
        return None
    impl = parts[0]
    kv = {}
    for tok in parts[1:]:
        if '=' in tok:
            k, v = tok.split('=', 1)
            kv[k.strip()] = v.strip()
    # throughput is like '40716.93 ops/s' or just numeric
    thr = None
    if 'throughput' in kv:
        m = re.search(r"([0-9]+\.?[0-9]*)", kv['throughput'])
        if m:
            thr = float(m.group(1))
    batch = None
    if 'avg_batch_size' in kv:
        try:
            batch = float(kv['avg_batch_size'])
        except Exception:
            batch = None
    threads = int(kv.get('threads', '0'))
    mix = kv.get('mix', '')
    return {'impl': impl, 'threads': threads, 'mix': mix, 'throughput': thr, 'avg_batch_size': batch}

def load_data(path):
    rows = []
    with open(path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            r = parse_line(line)
            if r:
                rows.append(r)
    return rows

def plot_throughput(rows):
    mixes = sorted({r['mix'] for r in rows})
    impls = sorted({r['impl'] for r in rows})
    os.makedirs(OUTDIR, exist_ok=True)
    for mix in mixes:
        plt.figure(figsize=(7,4))
        for impl in impls:
            xs = [r['threads'] for r in rows if r['mix']==mix and r['impl']==impl and r['throughput'] is not None]
            ys = [r['throughput'] for r in rows if r['mix']==mix and r['impl']==impl and r['throughput'] is not None]
            if not xs:
                continue
            # sort by threads
            xy = sorted(zip(xs, ys))
            xs, ys = zip(*xy)
            plt.plot(xs, ys, marker='o', label=impl)
        plt.xlabel('Threads')
        plt.ylabel('Throughput (ops/s)')
        plt.title(f'Throughput vs Threads — {mix}')
        plt.grid(True, linestyle='--', alpha=0.4)
        plt.legend()
        fname = os.path.join(OUTDIR, f'throughput_{mix}.png')
        plt.tight_layout()
        plt.savefig(fname)
        plt.close()

def plot_batch_scaling(rows):
    fc_rows = [r for r in rows if r['impl']=='fc_queue' and r['avg_batch_size'] is not None]
    if not fc_rows:
        print('No fc_queue batch data found')
        return
    # group by threads and take the avg (if multiple runs)
    by_threads = defaultdict(list)
    for r in fc_rows:
        by_threads[r['threads']].append(r['avg_batch_size'])
    xs = sorted(by_threads.keys())
    ys = [sum(by_threads[t])/len(by_threads[t]) for t in xs]
    plt.figure(figsize=(6,4))
    plt.plot(xs, ys, marker='o')
    plt.xlabel('Threads')
    plt.ylabel('Average FC Batch Size')
    plt.title('FC Queue: Avg Batch Size vs Threads')
    plt.grid(True, linestyle='--', alpha=0.4)
    fname = os.path.join(OUTDIR, 'fc_batch_scaling.png')
    plt.tight_layout()
    plt.savefig(fname)
    plt.close()

def main():
    if not os.path.exists(INPUT):
        print('Input CSV not found:', INPUT)
        return
    rows = load_data(INPUT)
    plot_throughput(rows)
    plot_batch_scaling(rows)
    print('Plots written to', OUTDIR)

if __name__ == '__main__':
    main()
