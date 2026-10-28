#!/usr/bin/env bash
# Remove a correcao do Auto-Mute da ALC897.
#
#   ./uninstall.sh             remove servico e script
#   ./uninstall.sh --restore   remove e reativa o Auto-Mute (comportamento original)
set -euo pipefail

bin_dst="$HOME/.local/bin/alsa-disable-automute.sh"
unit_dst="$HOME/.config/systemd/user/alsa-disable-automute.service"

systemctl --user disable --now alsa-disable-automute.service 2>/dev/null || true
rm -f "$unit_dst" "$bin_dst"
systemctl --user daemon-reload

if [[ ${1:-} == "--restore" ]]; then
    card=""
    for codec in /proc/asound/card*/codec#*; do
        if grep -q '^Codec: Realtek ALC897' "$codec" 2>/dev/null; then
            codec=${codec#/proc/asound/card}
            card=${codec%%/*}
            break
        fi
    done
    if [[ -n $card ]]; then
        amixer -c "$card" sset 'Auto-Mute Mode' Enabled
    else
        echo "Codec ALC897 nao encontrado; Auto-Mute nao foi reativado." >&2
    fi
fi

echo "Removido."
