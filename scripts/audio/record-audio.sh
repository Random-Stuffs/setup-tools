#!/usr/bin/env bash
# record-audio.sh — gravador interativo
#
# P          : iniciar gravação / pausar / retomar
# R          : salvar checkpoint agora e continuar gravando
# .          : salvar arquivo final e resetar
# ,          : descartar gravação atual e resetar
# Ctrl+C     : salvar (se houver gravação ativa) e sair

# Sem set -e: read -t retorna != 0 no timeout e isso não deve encerrar o script.

STATE="idle"        # idle | recording | paused
FFMPEG_PID=""
TMPWAV=""
CHECKPOINT_NUM=0
STTY_BACKUP=""
OUTPUT_DIR="${OUTPUT_DIR:-.}"

# --- detecção de áudio (WSL2 + WSLg / Linux nativo) ---
detect_audio() {
  local wslg="/mnt/wslg/runtime-dir/pulse/native"
  if [[ -S "$wslg" ]]; then
    export PULSE_SERVER="unix:$wslg"
    AUDIO_FLAGS=(-f pulse -i default)
  elif pactl info &>/dev/null 2>&1; then
    AUDIO_FLAGS=(-f pulse -i default)
  elif arecord -l &>/dev/null 2>&1; then
    AUDIO_FLAGS=(-f alsa -i default)
  else
    echo "ERRO: microfone não encontrado."
    echo "  No WSL2, instale WSLg (Windows 11) ou configure PulseAudio."
    echo "  Execute no PowerShell: wsl --update"
    exit 1
  fi
}

# --- helpers ---
ts()  { date +%Y%m%d_%H%M%S; }
log() { printf "  %s\n" "$*"; }

convert_to_mp4() {
  ffmpeg -loglevel warning \
    -i "$1" \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    "$2"
}

start_ffmpeg() {
  TMPWAV="/tmp/rec_$$_$(ts).wav"
  ffmpeg -loglevel warning \
    "${AUDIO_FLAGS[@]}" \
    -c:a pcm_s16le -ar 44100 -ac 1 \
    "$TMPWAV" &
  FFMPEG_PID=$!
}

stop_ffmpeg() {
  [[ -z "$FFMPEG_PID" ]] && return
  # retoma antes de terminar: SIGINT em processo STOP'd fica pendente e não para o ffmpeg
  [[ "$STATE" == "paused" ]] && kill -CONT "$FFMPEG_PID" 2>/dev/null || true
  kill -INT "$FFMPEG_PID" 2>/dev/null || true
  # aguarda até 5s; força kill se travar
  local i
  for i in $(seq 1 50); do
    kill -0 "$FFMPEG_PID" 2>/dev/null || break
    sleep 0.1
  done
  kill -9 "$FFMPEG_PID" 2>/dev/null || true
  wait "$FFMPEG_PID" 2>/dev/null || true
  FFMPEG_PID=""
}

flush_to_mp4() {
  local out="$OUTPUT_DIR/gravacao_$(ts).mp4"
  log "Convertendo → $out ..."
  convert_to_mp4 "$TMPWAV" "$out" && log "✓ Salvo: $out" || log "✗ Falha na conversão"
  rm -f "$TMPWAV"
  TMPWAV=""
}

# --- cleanup ao sair ---
EXITING=false

on_exit() {
  # guarda contra dupla execução (INT dispara on_exit → exit → EXIT dispara on_exit de novo)
  $EXITING && return
  EXITING=true

  # ignora Ctrl+C durante o cleanup para não interromper a conversão WAV→MP4
  trap '' INT TERM

  if [[ "$STATE" == "recording" || "$STATE" == "paused" ]]; then
    log "Finalizando..."
    stop_ffmpeg
    [[ -f "$TMPWAV" ]] && flush_to_mp4
  fi

  [[ -n "$STTY_BACKUP" ]] && stty "$STTY_BACKUP" </dev/tty 2>/dev/null || true
  printf "\n"
}

# INT/TERM: faz cleanup E chama exit explicitamente (sem o exit, o while true continua e trava)
trap 'on_exit; exit' INT TERM
# EXIT: cobre saídas normais (ex: . ou , já chamaram exit implícito)
trap 'on_exit' EXIT

# --- inicialização ---
detect_audio

STTY_BACKUP=$(stty -g </dev/tty)
# modo raw: retorna tecla imediatamente, sem eco, Ctrl+C ainda gera SIGINT (-isig não está setado)
stty -icanon -echo </dev/tty

printf "\n"
printf "  ╔══════════════════════════════════════════╗\n"
printf "  ║  Gravador de Áudio                       ║\n"
printf "  ║  P: gravar/pausar   R: checkpoint        ║\n"
printf "  ║  .: salvar+resetar  ,: descartar+resetar ║\n"
printf "  ║  Ctrl+C: sair (salva automaticamente)    ║\n"
printf "  ╚══════════════════════════════════════════╝\n\n"
log "Estado: PARADO — pressione P para começar"

# --- loop principal: lê teclas direto de /dev/tty ---
while true; do
  key=""
  # timeout de 0.5s para poder checar se ffmpeg morreu
  IFS= read -rsn1 -t 0.5 key </dev/tty 2>/dev/null || true

  # checa se ffmpeg morreu inesperadamente
  if [[ -n "$FFMPEG_PID" ]] && ! kill -0 "$FFMPEG_PID" 2>/dev/null; then
    log "⚠  ffmpeg encerrou de forma inesperada"
    FFMPEG_PID=""
    STATE="idle"
    log "Estado: PARADO — pressione P para recomeçar"
  fi

  [[ -z "$key" ]] && continue

  case "$key" in

    p|P)
      case "$STATE" in
        idle)
          start_ffmpeg
          STATE="recording"
          log "▶  Gravando..."
          ;;
        recording)
          kill -STOP "$FFMPEG_PID" 2>/dev/null
          STATE="paused"
          log "⏸  Pausado"
          ;;
        paused)
          kill -CONT "$FFMPEG_PID" 2>/dev/null
          STATE="recording"
          log "▶  Retomado"
          ;;
      esac
      ;;

    r|R)
      if [[ "$STATE" == "idle" ]]; then
        log "⚠  Inicie a gravação primeiro (P)"
      else
        CHECKPOINT_NUM=$((CHECKPOINT_NUM + 1))
        ckpt_out="$OUTPUT_DIR/checkpoint_$(ts)_${CHECKPOINT_NUM}.mp4"
        ckpt_tmp="/tmp/ckpt_$$_${CHECKPOINT_NUM}.wav"

        # pausa brevemente apenas se estiver gravando (não pausado)
        resume_after=false
        if [[ "$STATE" == "recording" ]]; then
          kill -STOP "$FFMPEG_PID" 2>/dev/null
          resume_after=true
        fi

        cp "$TMPWAV" "$ckpt_tmp"

        [[ "$resume_after" == true ]] && kill -CONT "$FFMPEG_PID" 2>/dev/null

        log "📌 Gerando checkpoint $CHECKPOINT_NUM em background..."
        (
          convert_to_mp4 "$ckpt_tmp" "$ckpt_out" \
            && rm -f "$ckpt_tmp" \
            && printf "  ✓  Checkpoint %d: %s\n" "$CHECKPOINT_NUM" "$ckpt_out"
        ) &
      fi
      ;;

    '.')
      if [[ "$STATE" == "idle" ]]; then
        log "⚠  Nenhuma gravação ativa"
      else
        stop_ffmpeg
        STATE="idle"
        [[ -f "$TMPWAV" ]] && flush_to_mp4
        CHECKPOINT_NUM=0
        log "Estado: PARADO — P para nova gravação"
      fi
      ;;

    ',')
      if [[ "$STATE" == "idle" ]]; then
        log "⚠  Nenhuma gravação ativa"
      else
        stop_ffmpeg
        rm -f "$TMPWAV"
        TMPWAV=""
        STATE="idle"
        CHECKPOINT_NUM=0
        log "✗  Descartado"
        log "Estado: PARADO — P para nova gravação"
      fi
      ;;

  esac
done
