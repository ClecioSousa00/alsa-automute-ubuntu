#!/usr/bin/env bash
# Instala a correcao do Auto-Mute da ALC897 para o usuario atual (sem sudo).
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

bin_src="$repo_dir/bin/alsa-disable-automute.sh"
unit_src="$repo_dir/systemd/alsa-disable-automute.service"
bin_dst="$HOME/.local/bin/alsa-disable-automute.sh"
unit_dst="$HOME/.config/systemd/user/alsa-disable-automute.service"

if [[ ! -f $bin_src || ! -f $unit_src ]]; then
    echo "Arquivos do repositorio nao encontrados em $repo_dir" >&2
    exit 1
fi

if ! grep -q '^Codec: Realtek ALC897' /proc/asound/card*/codec#* 2>/dev/null; then
    echo "Aviso: nenhum codec Realtek ALC897 detectado neste sistema." >&2
    echo "O servico sera instalado, mas falhara enquanto o hardware nao estiver presente." >&2
fi

install -Dm755 "$bin_src" "$bin_dst"
install -Dm644 "$unit_src" "$unit_dst"

systemctl --user daemon-reload
systemctl --user enable --now alsa-disable-automute.service

echo
echo "Instalado com sucesso:"
echo "  $bin_dst"
echo "  $unit_dst"
echo
"$bin_dst" --status
