#!/usr/bin/env bash
# Desativa o Auto-Mute do codec Realtek ALC897.
#
# Sem auto-mute o kernel nao desabilita o Line Out traseiro quando ha algo
# plugado no jack de fone frontal, permitindo alternar entre caixas de som e
# headset pelo painel de audio.
#
# Uso: alsa-disable-automute.sh [--status]
set -euo pipefail

find_card() {
    local codec
    for codec in /proc/asound/card*/codec#*; do
        if grep -q '^Codec: Realtek ALC897' "$codec" 2>/dev/null; then
            codec=${codec#/proc/asound/card}
            echo "${codec%%/*}"
            return 0
        fi
    done
    return 1
}

card=$(find_card) || {
    echo "Codec Realtek ALC897 nao encontrado" >&2
    exit 1
}

if [[ ${1:-} == "--status" ]]; then
    amixer -c "$card" sget 'Auto-Mute Mode'
    exit 0
fi

exec amixer -c "$card" sset 'Auto-Mute Mode' Disabled
