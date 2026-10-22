#!/usr/bin/env bash
# Install the weekly content timer on the iMac (Sundays 03:00). Run on the iMac; needs
# ~/deepcuts (a clone of this repo) and ~/.tester_feedback (the admin key).
set -euo pipefail
dir="$HOME/.config/systemd/user"
mkdir -p "$dir"
cat > "$dir/deepcuts-weekly.service" <<UNIT
[Unit]
Description=Deep Cuts weekly live questions

[Service]
Type=oneshot
Environment=PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$HOME/deepcuts/scripts/weekly/run.sh
TimeoutStartSec=30h
UNIT
cat > "$dir/deepcuts-weekly.timer" <<UNIT
[Unit]
Description=Deep Cuts weekly live questions, Sundays 03:00

[Timer]
OnCalendar=Sun 03:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now deepcuts-weekly.timer
systemctl --user list-timers deepcuts-weekly.timer --no-pager
