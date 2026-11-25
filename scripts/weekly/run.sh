#!/usr/bin/env bash
# Weekly Deep Cuts content: new fact-checked questions for every crate, published live.
# Runs on the iMac from a systemd user timer (scripts/weekly/install.sh). Per crate, Gemini Flash (agy)
# drafts questions with web tools, verify.py keeps only those that pass a blind answer check (Gemini
# Hydrogen) and a fact check (Claude Haiku), and scripts/content-remote.py validates and publishes them.
#   run.sh [crate ...]   all crates when none given
#   env: COUNT (20 wanted), DRAFT_COUNT (COUNT+6), DRAFT_MODEL (gemini-3.8-flash-high),
#        DRAFT=claude to draft with `claude -p --model $MODEL` (opus) instead; when agy writes nothing the
#        crate is drafted on $FALLBACK_MODEL (sonnet). DRY=1 to skip publishing,
#        REPO, PULL=0
set -uo pipefail

REPO="${REPO:-$HOME/deepcuts}"
WORK="$HOME/deepcuts-weekly/$(date +%F)"
COUNT="${COUNT:-20}"
DRAFT_COUNT="${DRAFT_COUNT:-$((COUNT + 6))}"
DRAFT="${DRAFT:-agy}"
DRAFT_MODEL="${DRAFT_MODEL:-gemini-3.8-flash-high}"
AGY="${AGY:-$HOME/.local/bin/agy}"
CLAUDE="${CLAUDE:-$HOME/.local/bin/claude}"
MODEL="${MODEL:-opus}"
FALLBACK_MODEL="${FALLBACK_MODEL:-sonnet}"
export AGY CLAUDE FALLBACK_MODEL

[ "${PULL:-1}" = 0 ] || git -C "$REPO" pull -q --ff-only || { echo "git pull failed"; exit 1; }
mkdir -p "$WORK"
python3 "$REPO/scripts/content-remote.py" merged --out "$WORK/merged" || { echo "pull failed"; exit 1; }
crates=("$@")
[ ${#crates[@]} -eq 0 ] && crates=($(ls "$REPO/DeepCuts/Content/genres" | sed 's/\.json$//'))

draft() {  # prompt-file
  if [ "${DRAFT}" = claude ]; then
    timeout 90m "$CLAUDE" -p --model "$MODEL" --allowedTools "Read,Glob,Grep,Write,WebSearch,WebFetch" < "$1"
  else
    timeout 90m "$AGY" --model "$DRAFT_MODEL" --dangerously-skip-permissions -p "$(cat "$1")" < /dev/null
  fi
}

published=0 failed=()
for crate in "${crates[@]}"; do
  drafts="$WORK/$crate.drafts.json" out="$WORK/$crate.json"
  sed -e "s|{{CRATE}}|$crate|g" -e "s|{{MERGED}}|$WORK/merged/$crate.json|g" \
      -e "s|{{COUNT}}|$DRAFT_COUNT|g" -e "s|{{OUT}}|$drafts|g" "$REPO/scripts/weekly/prompt.md" > "$WORK/$crate.prompt"
  echo "== $crate $(date +%T)"
  (cd "$WORK" && draft "$WORK/$crate.prompt") > "$WORK/$crate.log" 2>&1
  if [ ! -s "$drafts" ] && [ "$DRAFT" != claude ]; then  # agy quota or outage: draft on Sonnet instead
    echo "agy wrote no drafts; drafting with claude $FALLBACK_MODEL" >> "$WORK/$crate.log"
    (cd "$WORK" && DRAFT=claude MODEL="$FALLBACK_MODEL" draft "$WORK/$crate.prompt") >> "$WORK/$crate.log" 2>&1
  fi
  tail -1 "$WORK/$crate.log"
  if [ -s "$drafts" ]; then
    python3 "$REPO/scripts/weekly/verify.py" "$drafts" "$out" "$COUNT" >> "$WORK/$crate.log" 2>&1
    grep -E '^verified' "$WORK/$crate.log" | tail -1
  fi
  pub=(publish "$out" --drop-bad --source "weekly-$(date +%F)")
  [ "${DRY:-0}" = 1 ] && pub+=(--dry-run)
  has_items() { python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1])) else 1)' "$1" 2>/dev/null; }
  if ! has_items "$out" || ! python3 "$REPO/scripts/content-remote.py" "${pub[@]}" >> "$WORK/$crate.log" 2>&1; then
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
if [ ${#failed[@]} -gt 0 ] && [ "${DRY:-0}" != 1 ] && command -v ops-alert >/dev/null; then
  printf 'Published %s questions. Failed crates: %s\nLogs: %s on the iMac\n' "$published" "${failed[*]}" "$WORK" \
    | ops-alert "Deep Cuts weekly content: ${#failed[@]} crates failed" --source deepcuts-weekly
fi
