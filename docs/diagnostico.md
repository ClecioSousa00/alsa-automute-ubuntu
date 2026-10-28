# Detalhamento técnico do diagnóstico

Registro completo da investigação, comandos usados e evidências coletadas.

## 1. Ambiente

| Item | Valor |
|---|---|
| Distro | Ubuntu 24.04.5 LTS (Noble) |
| Kernel | 7.0.0-38-generic |
| Sessão | Wayland, GNOME Shell 46.0 |
| Servidor de som | PipeWire 1.0.5 + WirePlumber 0.4.17 (libwireplumber 0.4.17) |
| Placa-mãe | ASUSTeK (subsystem `1043:8850`) |
| Codec | Realtek ALC897 (`10ec:0897`), driver `snd_hda_codec_alc662` |
| Controladora | AMD Family 17h/19h HD Audio (`1022:15e3`), `snd_hda_intel` |
| Endereço PCI atual | `0000:0c:00.6` |
| Outras placas de áudio | HDMI AMD Rembrandt (`0c:00.1`), HDMI NVIDIA (`01:00.1`) |

## 2. Comandos de diagnóstico usados

```bash
cat /proc/asound/cards
cat /proc/asound/card2/codec#0
amixer -c 2 scontrols
amixer -c 2
amixer -c 2 contents | grep -i jack
wpctl status
wpctl inspect 49
pactl list cards
pactl list sinks
pw-dump 48
journalctl -k | grep -iE 'jack|hda'
```

## 3. Evidências

### 3.1 Um sink, duas portas

```
Sink: alsa_output.pci-0000_0c_00.6.analog-stereo
  device.routes = 2
  porta analog-output-lineout      prioridade 9000  -> pin 0x14 (Line Out, traseiro)
  porta analog-output-headphones   prioridade 9900  -> pin 0x1b (HP Out, frontal)
```

`pactl list cards` mostra que a placa só oferece os perfis
`output:analog-stereo`, `output:analog-stereo+input:analog-stereo`, `input:analog-stereo`
e `pro-audio` — não existe um sink separado para as caixas. Portanto "trocar de
dispositivo" no painel do GNOME é trocar de **porta**.

### 3.2 Detecção de jack funcionando

```
numid=35,iface=CARD,name='Front Headphone Jack'  : values=on
numid=34,iface=CARD,name='Line Out Jack'         : values=on
```

Com o headset plugado, `Front Headphone Jack = on`. A detecção está correta; o
problema não é jack sense quebrado.

### 3.3 Auto-Mute ativo e persistido

```
Simple mixer control 'Auto-Mute Mode',0
  Items: 'Disabled' 'Enabled'
  Item0: 'Enabled'
```

Em `/var/lib/alsa/asound.state`, dentro de `state.Generic_1`:

```
name 'Auto-Mute Mode'
value Enabled
```

E `alsa-restore.service` está ativo (`static`, executado no boot), reaplicando
esse valor a cada inicialização.

### 3.4 Estado dos pinos e do mixer com o headset plugado (antes)

```
Pin 0x14: Pin Default 0x01014010: [Jack] Line Out at Ext Rear
          Pin-ctls: 0x00              <- desabilitado pelo auto-mute
Pin 0x1b: Pin Default 0x02214020: [Jack] HP Out at Ext Front
          Pin-ctls: 0xc0: OUT HP      <- ativo

'Front' Playback Switch      : [off]   (Line Out mutado)
'Headphone' Playback Switch  : [on]
```

### 3.5 Estado após desativar o Auto-Mute

```
Auto-Mute Mode: Disabled
Pin 0x14: Pin-ctls: 0x40: OUT     <- pino reabilitado imediatamente
```

Trocando a porta para `analog-output-lineout` **com o headset ainda plugado**:

```
'Front'      : Playback 87 [100%] [0.00dB] [on]
'Headphone'  : Playback 0  [0%]   [-65.25dB] [off]
```

`speaker-test -c 2 -t sine -f 440 -l 1` reproduziu o tom nas caixas (exit 0).
Retornando para `analog-output-headphones`, o headset voltou a tocar.

## 4. Causa raiz

`Auto-Mute Mode = Enabled` no codec ALC897. O auto-mute é implementado no driver
HDA do kernel: ao detectar presença no jack de fone, ele:

1. coloca o pino do Line Out traseiro (0x14) em estado desabilitado/entrada;
2. muta o controle de mixer `Front` (amplificador do Line Out).

O PipeWire/ACP, ao trocar a porta, mexe apenas no mixer da porta escolhida — não
reativa o pino, que é controlado pelo kernel. Por isso a troca no painel não
produz som até o plugue ser removido (quando o auto-mute libera o pino).

## 5. Solução

Serviço systemd **de usuário** executando `amixer sset 'Auto-Mute Mode' Disabled`
a cada login, com o índice da placa resolvido dinamicamente pelo nome do codec.

## 6. Alternativas consideradas

| Alternativa | Por que não foi usada |
|---|---|
| `sudo alsactl store` | Estado é gravado por nome de placa (`Generic`/`Generic_1`); os nomes/endereços PCI já variaram entre boots nesta máquina, podendo aplicar a configuração à placa errada. |
| Quirk `options snd-hda-intel model=...` | Sem modelo específico documentado para essa combinação ASUSTeK/ALC897; risco de regressão em outros controles sem ganho garantido. |
| `hda-verb` forçando pino 0x14 | Solução de baixo nível, não persistente e frágil entre versões de kernel. |
| DAC USB para as caixas | Resolveria com independência real entre as saídas, mas exige hardware extra. |
| Deixar o headset desconectado | Workaround manual, que era justamente o sintoma. |

## 7. Próximos passos / troubleshooting

- **Auto-Mute volta a `Enabled` após suspender/retomar:** o codec é
  reinicializado no resume. Adicionar um hook que reexecute o script, por exemplo
  um `systemd` user timer:
  ```ini
  # ~/.config/systemd/user/alsa-disable-automute.timer
  [Unit]
  Description=Reaplicar Auto-Mute Disabled periodicamente

  [Timer]
  OnBootSec=30s
  OnUnitActiveSec=5min

  [Install]
  WantedBy=timers.target
  ```
- **Quero as duas saídas tocando juntas:** manter `Auto-Mute Mode = Disabled` e
  não alternar portas — mas o ALC897 compartilha um DAC, então a porta não
  selecionada fica muda de qualquer forma. Para simultaneidade real é preciso
  hardware adicional.
- **Conferir o estado atual:**
  ```bash
  ~/.local/bin/alsa-disable-automute.sh --status
  ```
