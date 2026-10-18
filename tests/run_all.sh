#!/bin/bash
# Quick regression check: compile every script, run headless sims for each
# house variant, and soak the real GUI scene with random settings.
#   bash tests/run_all.sh
cd "$(dirname "$0")/.." || exit 1
fail=0
echo "== compile"
for f in scripts/*.gd scripts/*/*.gd tests/*.gd; do
  out=$(timeout 30 godot --headless --path . --check-only -s "$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error")
  if [ -n "$out" ]; then echo "FAIL $f"; echo "$out"; fail=1; fi
done
echo "== sims"
for env in "" "LARGE=1" "REARRANGE=1" "LARGE=1 REARRANGE=1"; do
  line=$(env $env timeout 120 godot --headless --path . -s tests/sim.gd -- 100 careful q normal 2>&1 | grep -E "policy|SCRIPT ERROR")
  echo "[$env] $line"
  echo "$line" | grep -q "SCRIPT ERROR" && fail=1
done
echo "== GUI soak"
out=$(timeout 600 godot --headless --path . -- --play --backend=mock --autoplay=smart --speed=10 --soak=5 2>&1)
echo "$out" | grep -E "soak done"
if echo "$out" | grep -q "SCRIPT ERROR"; then echo "$out" | grep -A3 "SCRIPT ERROR" | head -20; fail=1; fi
[ $fail = 0 ] && echo "ALL OK" || echo "FAILURES"
exit $fail
