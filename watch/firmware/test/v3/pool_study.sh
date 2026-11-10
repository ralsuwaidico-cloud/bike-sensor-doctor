#!/bin/bash
# LVGL pool-size study (computer only): rebuild the renderer and the frame benchmark with a smaller LVGL pool and check that
# every state renders byte-identically to the 64 KB build and that partial updates still equal full redraws.
# usage: ./pool_study.sh 32 24 16 ...      (run after `make render perf-link` for the 64 KB reference in out/)
set -u
for kb in "$@"; do
  b=.build-pool$kb; o=out-pool$kb; rm -rf $o; mkdir -p $o
  make -s BUILD=$b EXTRA="-DCYW_LV_MEM_KB=${kb}U" link perf-link >/dev/null 2>&1 || { echo "pool $kb KB: build failed"; continue; }
  timeout 300 $b/v3_render $o > $o/render.log 2>&1; rr=$?
  same=0; diff=0; for f in out/*.png; do n=$(basename $f); if [ -f $o/$n ] && cmp -s $f $o/$n; then same=$((same+1)); else diff=$((diff+1)); fi; done
  timeout 300 $b/v3_perf $o/v.csv --verify > $o/perf.log 2>&1; pr=$?
  echo "pool $kb KB: render exit $rr ($(grep -o '[0-9]* states, [0-9]* checks, [0-9]* open findings' $o/render.log)) · PNG identical to 64 KB: $same, different/missing: $diff · frame benchmark exit $pr: $(grep 'partial-update' $o/perf.log)"
done
