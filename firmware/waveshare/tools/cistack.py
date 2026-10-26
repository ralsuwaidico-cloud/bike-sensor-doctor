#!/usr/bin/env python3
"""Worst-case stack per root from GCC -fcallgraph-info=su (.ci) files of a whole ESP-IDF build, falling back to the
Xtensa disassembly ('entry a1, N' + direct calls) for prebuilt libraries (newlib, BT controller).
usage: cistack.py BUILD_DIR DISASSEMBLY root... [--edge caller=callee]... [--cut name]...
  BUILD_DIR: an idf.py build made with  idf_build_set_property(COMPILE_OPTIONS "-fstack-usage;-fcallgraph-info=su" APPEND)
  DISASSEMBLY: xtensa-esp32s3-elf-objcopy -R .xt.prop -R .xt.lit -R .xtensa.info app.elf x.elf; xtensa-esp32s3-elf-objdump -d x.elf
  root "a@b" = worst stack of a path from a to b plus the worst below b (e.g. nimble_port_run@on_svc).
  Indirect calls (NimBLE dispatch, callbacks): tools/cistack_edges.txt, passed as --edge a=b."""
import re, sys, os, argparse
ap = argparse.ArgumentParser(); ap.add_argument('build'); ap.add_argument('dis'); ap.add_argument('roots', nargs='+')
ap.add_argument('--edge', action='append', default=[]); ap.add_argument('--cut', action='append', default=[])
ap.add_argument('--show', type=int, default=40)
a = ap.parse_args()
size = {}; edges = {}; defs = {}; indirect = set()
nre = re.compile(r'node: \{ title: "([^"]+)" label: "([^"]*)"')
ere = re.compile(r'edge: \{ sourcename: "([^"]+)" targetname: "([^"]+)"')
for root, _, files in os.walk(a.build):
    for fn in files:
        if not fn.endswith('.ci'): continue
        for line in open(os.path.join(root, fn), errors='replace'):
            m = nre.match(line)
            if m:
                t, lab = m.groups(); s = re.search(r'\\n(\d+) bytes', lab)
                if s:
                    size[t] = int(s.group(1)); name = t.split(':')[-1]; defs.setdefault(name, []).append(t)
                continue
            m = ere.match(line)
            if m:
                s, t = m.groups()
                if t == '__indirect_call': indirect.add(s)
                else: edges.setdefault(s, set()).add(t)
# objdump fallback
dsize = {}; dcalls = {}; cur = None
fre = re.compile(r'^([0-9a-f]+) <([^>]+)>:'); ent = re.compile(r'\sentry\s+a1, (0x[0-9a-f]+|\d+)')
cre = re.compile(r'\scall(?:4|8|12)\s+[0-9a-f]+ <([^>+]+)>')
starts = set()
for line in open(a.dis):
    m = fre.match(line)
    if m: cur = m.group(2); starts.add(cur); dsize.setdefault(cur, None); dcalls.setdefault(cur, set()); first = True; continue
    if cur is None: continue
    if dsize[cur] is None:
        m = ent.search(line)
        if m: dsize[cur] = int(m.group(1), 0); continue
    m = cre.search(line)
    if m: dcalls[cur].add(m.group(1))
def resolve(t):
    if t in size: return t
    if ':' in t:
        c = [k for k in size if k.endswith('/' + t) or k == t]
        if c: return c[0]
    d = defs.get(t)
    if d: return max(d, key=lambda x: size[x])
    return 'BIN:' + t
for e in a.edge:
    c, d = e.split('=')
    edges.setdefault(resolve(c), set()).add(d)
cut = set(a.cut)
memo = {}
def worst(node, stack):
    nm = node.split(':')[-1]
    if nm in cut: return (0, [nm + '(cut)'])
    if node in stack: return (0, [nm + '(recursion)'])
    if node in memo: return memo[node]
    if node.startswith('BIN:'):
        own = dsize.get(nm) or 0; kids = ['BIN:' + c for c in dcalls.get(nm, ())]
    else:
        own = size.get(node, 0); kids = [resolve(t) for t in edges.get(node, ())]
    best = (0, [])
    for k in kids:
        r = worst(k, stack | {node})
        if r[0] > best[0]: best = r
    tag = '' if not node.startswith('BIN:') else '*'
    res = (own + best[0], [f'{nm}{tag}[{own}]'] + best[1])
    memo[node] = res
    return res
def kids_of(node):
    nm = node.split(':')[-1]
    if node.startswith('BIN:'): return ['BIN:' + c for c in dcalls.get(nm, ())]
    return [resolve(t) for t in edges.get(node, ())]
def own_of(node):
    nm = node.split(':')[-1]
    return (dsize.get(nm) or 0) if node.startswith('BIN:') else size.get(node, 0)
tmemo = {}
def to(node, target, stack):
    # max stack used from node (inclusive) down to the call of target (exclusive); None = unreachable
    if node == target: return (0, [])
    if node in stack or node.split(':')[-1] in cut: return None
    key = (node, target)
    if key in tmemo: return tmemo[key]
    best = None
    for k in kids_of(node):
        r = to(k, target, stack | {node})
        if r is not None and (best is None or r[0] > best[0]): best = r
    res = None if best is None else (own_of(node) + best[0], [f"{node.split(':')[-1]}[{own_of(node)}]"] + best[1])
    tmemo[key] = res
    return res
for r in a.roots:
    if '@' in r:
        root, via = r.split('@'); rv = resolve(via)
        pre = to(resolve(root), rv, frozenset()); w = worst(rv, frozenset())
        if pre is None: print(f'{r}: {via} not reachable from {root}'); continue
        print(f'{r}: worst {pre[0] + w[0]} B (dispatch {pre[0]} + callback {w[0]})')
        print('    ' + ' -> '.join(pre[1] + w[1])[:4000]); continue
    tot, path = worst(resolve(r), frozenset())
    print(f'{r}: worst {tot} B'); print('    ' + ' -> '.join(path[:a.show]))
