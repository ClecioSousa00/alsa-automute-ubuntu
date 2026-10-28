# Fix: caixas de som sem áudio com o headset conectado (Realtek ALC897 + PipeWire)

Correção para o problema em que o áudio não sai nas **caixas de som** enquanto um
**headset está plugado no painel frontal**, mesmo trocando a saída no painel de som
do GNOME. Desconectar o headset fazia o som voltar.

- **Hardware:** ASUS (AMD Rembrandt) com codec **Realtek ALC897**
- **Sistema:** Ubuntu 24.04.5, kernel 7.0.0-38, PipeWire 1.0.5 + WirePlumber 0.4.17, GNOME 46 (Wayland)
- **Causa raiz:** `Auto-Mute Mode = Enabled` no mixer ALSA do codec
- **Solução:** desativar o Auto-Mute via serviço systemd de usuário (sem `sudo`)

---

## 1. Sintoma

1. Headset conectado no jack frontal → áudio funciona normalmente no headset.
2. No painel de som, seleciona-se a saída das caixas ("Saída de linha").
3. **Nenhum som sai nas caixas.**
4. Desconectando o headset, as caixas voltam a funcionar (mesmo sem trocar nada no painel).

## 2. Diagnóstico

### 2.1 Topologia encontrada

O ALC897 expõe **um único sink analógico** com **duas portas** — caixas e headset
não são dispositivos separados:

```
Sink: alsa_output.pci-0000_0c_00.6.analog-stereo
 ├── porta analog-output-lineout      (pin 0x14, Line Out traseiro)
 └── porta analog-output-headphones   (pin 0x1b, HP Out frontal)
```

Trocar a saída no painel = trocar a **porta ativa** do sink
(`pactl set-sink-port ...`). As duas saídas compartilham o mesmo DAC: nunca tocam
simultaneamente.

### 2.2 Estado com o headset plugado (antes da correção)

```
Front Headphone Jack ......... on        # detecção de jack OK
Porta ativa .................. analog-output-headphones
Auto-Mute Mode ............... Enabled   # <-- causa raiz
'Front' Playback Switch ...... [off]     # Line Out traseiro mutado
'Headphone' Playback Switch .. [on]
Pin 0x14 (Line Out traseiro) . Pin-ctls: 0x00   # pino DESABILITADO
Pin 0x1b (HP frontal) ........ Pin-ctls: 0xc0 OUT HP
```

### 2.3 Mecanismo da falha

Com `Auto-Mute Mode = Enabled`, é o **kernel** (`snd_hda_codec_alc662`), e não o
PipeWire, que desliga o Line Out traseiro ao detectar presença no jack frontal:
ele zera o pino 0x14 e muta o controle `Front` do mixer.

Ao escolher "caixas de som" no painel, o PipeWire/ALSA (ACP) apenas troca o estado
do mixer da porta — o kernel mantém o pino traseiro desabilitado por causa do
auto-mute. Resultado: silêncio. Ao remover o plugue, o auto-mute libera o Line Out
e o som volta. Isso explica exatamente o comportamento observado.

Não era volume (Master 80%, PCM 99%) nem falha de detecção de jack.

O valor `Enabled` estava persistido em `/var/lib/alsa/asound.state`
(`state.Generic_1`) e era reaplicado a cada boot pelo `alsa-restore.service`.

## 3. Solução aplicada

Desativar o Auto-Mute de forma **dinâmica e por usuário**:

- `bin/alsa-disable-automute.sh` localiza a placa pelo nome do codec
  (`/proc/asound/card*/codec#*`) e executa
  `amixer -c <idx> sset 'Auto-Mute Mode' Disabled`.
- `systemd/alsa-disable-automute.service` (unidade de **usuário**) roda o script
  a cada login.

### Por que não `alsactl store` (system-wide)?

O `alsactl` grava o estado por **nome de placa** (`Generic`, `Generic_1`). No
histórico dessa máquina os nomes/endereços PCI já alternaram entre boots
(`08_00.6`, `09_00.6`, `0c_00.6`). Se a ordem de enumeração mudar, a correção
poderia ser aplicada silenciosamente à placa HDMI errada. A solução por usuário
resolve o índice da placa em tempo de execução e não exige root.

## 4. Validação

| Verificação | Antes | Depois |
|---|---|---|
| `Auto-Mute Mode` | `Enabled` | `Disabled` |
| Pin 0x14 (Line Out) | `0x00` (desabilitado) | `0x40 OUT` |
| Porta `analog-output-lineout` com headset plugado | `Front` mutado, silêncio | `Front` 100% `[on]`, som nas caixas |
| `speaker-test` na porta lineout | — | tom reproduzido ✅ |
| Retorno para `analog-output-headphones` | — | headset volta a tocar ✅ |
| Após reboot/login | `Enabled` | `Disabled` ✅ |

## 5. Instalação

```bash
./install.sh
```

O instalador copia o script para `~/.local/bin`, a unidade para
`~/.config/systemd/user`, habilita e inicia o serviço. Não usa `sudo`.

Verificação:

```bash
amixer -c "$(for c in /proc/asound/card*/codec#*; do
  grep -q '^Codec: Realtek ALC897' "$c" && echo "${c#/proc/asound/card}" | cut -d/ -f1
done)" sget 'Auto-Mute Mode' | tail -1
```

## 6. Desinstalação

```bash
./uninstall.sh              # remove serviço e script
./uninstall.sh --restore    # remove e reativa o Auto-Mute (comportamento original)
```

## 7. Limpeza opcional do estado do WirePlumber

Se o `~/.local/state/wireplumber` tiver entradas de placas que não existem mais
(endereços PCI antigos), volumes/mutes por porta podem ser reaplicados
indevidamente:

```bash
cp -a ~/.local/state/wireplumber ~/.local/state/wireplumber.bak
systemctl --user stop wireplumber
rm -f ~/.local/state/wireplumber/{default-nodes,default-routes,restore-stream}
systemctl --user start wireplumber
```

Isso apenas reseta volumes/mutes por porta; o sink padrão volta a ser escolhido
automaticamente.

## 8. Observações

- O ALC897 possui um único DAC para as duas saídas: a porta não selecionada fica
  muda. Para tocar nas duas ao mesmo tempo seria necessário hardware adicional
  (ex.: DAC USB para as caixas).
- Se o Auto-Mute voltar a `Enabled` após suspender/retomar, adicione um hook de
  resume (ver `docs/diagnostico.md`, seção "Próximos passos").
- Alternativas descartadas (quirk `model=`, `hda-verb`, DAC USB) estão descritas
  em `docs/diagnostico.md`.

## Estrutura

```
.
├── bin/alsa-disable-automute.sh
├── systemd/alsa-disable-automute.service
├── docs/diagnostico.md
├── install.sh
├── uninstall.sh
└── README.md
```
