#!/usr/bin/env bash
# Weekly Deep Cuts content: new fact-checked questions for every crate, published live.
# Runs on the iMac from a systemd user timer (scripts/weekly/install.sh). Claude writes each
# crate's drafts with web tools only; scripts/content-remote.py validates and publishes them.
#   run.sh [crate ...]   all crates when none given; env COUNT (20), MODEL (opus), REPO, PULL=0
set -uo pipefail

REPO="${REPO:-$HOME/deepcuts}"
WORK="$HOME/deepcuts-weekly/$(date +%F)"
COUNT="${COUNT:-20}"
CLAUDE="${CLAUDE:-$HOME/.local/bin/claude}"
MODEL="${MODEL:-opus}"

[ "${PULL:-1}" = 0 ] || git -C "$REPO" pull -q --ff-only || { echo "git pull failed"; exit 1; }
mkdir -p "$WORK"
python3 "$REPO/scripts/content-remote.py" merged --out "$WORK/merged" || { echo "pull failed"; exit 1; }
crates=("$@")
[ ${#crates[@]} -eq 0 ] && crates=($(ls "$REPO/DeepCuts/Content/genres" | sed 's/\.json$//'))

published=0 failed=()
for crate in "${crates[@]}"; do
  out="$WORK/$crate.json"
  sed -e "s|{{CRATE}}|$crate|g" -e "s|{{MERGED}}|$WORK/merged/$crate.json|g" \
      -e "s|{{COUNT}}|$COUNT|g" -e "s|{{OUT}}|$out|g" "$REPO/scripts/weekly/prompt.md" > "$WORK/$crate.prompt"
  echo "== $crate $(date +%T)"
  (cd "$WORK" && timeout 90m "$CLAUDE" -p --model "$MODEL" \
      --allowedTools "Read,Glob,Grep,Write,WebSearch,WebFetch" < "$WORK/$crate.prompt") > "$WORK/$crate.log" 2>&1
  tail -1 "$WORK/$crate.log"
  if [ ! -s "$out" ] || ! python3 "$REPO/scripts/content-remote.py" publish "$out" --drop-bad \
       --source "weekly-$(date +%F)" >> "$WORK/$crate.log" 2>&1; then
    failed+=("$crate")
  else
    n=$(grep -o '^published [0-9]*' "$WORK/$crate.log" | tail -1 | cut -d' ' -f2)
    published=$((published + ${n:-0}))
    # Later crates dedupe against what just went live.
    python3 "$REPO/scripts/content-remote.py" merged --out "$WORK/merged" >/dev/null 2>&1
  fi
  tail -2 "$WORK/$crate.log"
done

echo "published $published; failed: ${failed[*]:-none}"
if [ ${#failed[@]} -gt 0 ] && command -v ops-alert >/dev/null; then
  printf 'Published %s questions. Failed crates: %s\nLogs: %s on the iMac\n' "$published" "${failed[*]}" "$WORK" \
    | ops-alert "Deep Cuts weekly content: ${#failed[@]} crates failed" --source deepcuts-weekly
fi
