#!/usr/bin/env bash
# Downloads Kenney's CC0 audio packs and renders the clips the game needs.
#
# CC0 is a public domain dedication: no attribution required, no licence
# contamination, safe in a commercial app. We credit kenney.nl on the about
# screen anyway because it costs nothing.
#
# Usage:
#   Tools/fetch_audio.sh            download, convert, install
#   Tools/fetch_audio.sh --list     show what the downloaded packs contain
#
# If a download fails (Kenney's URLs carry a content hash and do rotate), grab
# the packs by hand from https://kenney.nl/assets?q=audio and drop the zips in
# .build/audio-src/ — the script picks up whatever is already there.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/.build/audio-src"
WORK="$ROOT/.build/audio-work"
OUT="$ROOT/App/Resources/Audio"
BUDGET_BYTES=$((1536 * 1024))   # 1.5 MB, per §10

PACKS=(
  "casino-audio|https://kenney.nl/media/pages/assets/casino-audio/casino-audio.zip"
  "interface-sounds|https://kenney.nl/media/pages/assets/interface-sounds/interface-sounds.zip"
  "ui-audio|https://kenney.nl/media/pages/assets/ui-audio/ui-audio.zip"
)

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)"; exit 1; }
command -v unzip  >/dev/null || { echo "unzip is required"; exit 1; }

mkdir -p "$SRC" "$WORK" "$OUT"

download() {
  local name="$1" url="$2" zip="$SRC/$name.zip"
  if [[ -f "$zip" ]]; then echo "  have $name.zip"; return 0; fi
  echo "  fetching $name"
  if ! curl -fsSL --retry 2 -o "$zip.part" "$url"; then
    rm -f "$zip.part"
    echo "  !! could not download $name — put $name.zip in $SRC and re-run"
    return 1
  fi
  mv "$zip.part" "$zip"
}

echo "Downloading packs..."
missing=0
for entry in "${PACKS[@]}"; do
  download "${entry%%|*}" "${entry##*|}" || missing=1
done

echo "Extracting..."
rm -rf "$WORK/raw"; mkdir -p "$WORK/raw"
shopt -s nullglob
for zip in "$SRC"/*.zip; do
  unzip -qo "$zip" -d "$WORK/raw/$(basename "${zip%.zip}")"
done

# Every audio file found, so the pickers below can match on filename.
mapfile -t ALL < <(find "$WORK/raw" -type f \( -iname '*.wav' -o -iname '*.ogg' -o -iname '*.mp3' \) | sort)

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "${ALL[@]}"
  exit 0
fi

if [[ ${#ALL[@]} -eq 0 ]]; then
  echo "No audio found in $WORK/raw. Download the packs manually into $SRC and re-run."
  exit 1
fi

# Picks the Nth file whose path matches a case-insensitive pattern.
pick() {
  local pattern="$1" index="${2:-1}" count=0
  for file in "${ALL[@]}"; do
    if [[ "${file,,}" == *"${pattern,,}"* ]]; then
      count=$((count + 1))
      if [[ $count -eq $index ]]; then printf '%s' "$file"; return 0; fi
    fi
  done
  return 1
}

# Renders one clip: mono, 44.1 kHz, 16-bit, leading silence trimmed hard, peak
# normalised to about -3 dBFS.
#
# The trim matters more than it sounds like it should: forty milliseconds of
# lead-in on a card sound reads to the player as input lag, not as audio.
render() {
  local input="$1" name="$2"
  local trimmed="$WORK/${name}.trim.wav"

  ffmpeg -v error -y -i "$input" \
    -af "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.005,aformat=channel_layouts=mono" \
    -ar 44100 -ac 1 -c:a pcm_s16le "$trimmed"

  # Two-pass peak normalisation: measure, then apply the exact gain.
  local peak gain
  peak=$(ffmpeg -v info -i "$trimmed" -af volumedetect -f null - 2>&1 \
         | awk -F': ' '/max_volume/ {gsub(/ dB/, "", $2); print $2}' | tail -1)
  peak=${peak:-0}
  gain=$(awk -v p="$peak" 'BEGIN { printf "%.2f", -3.0 - p }')

  ffmpeg -v error -y -i "$trimmed" -af "volume=${gain}dB" \
    -ar 44100 -ac 1 -c:a pcm_s16le "$OUT/${name}.wav"
  rm -f "$trimmed"
  echo "  $name.wav  (peak ${peak} dB -> -3 dB)"
}

# Source patterns per effect. Card handling from Casino Audio covers everything
# table-related; the interface packs cover buttons and confirmations.
#
# dealCard and playCard ship four takes each and the app picks one at random —
# a single card sound repeated fifty-two times during a deal sounds cheap.
declare -a MAP=(
  "shuffle|cardShuffle|1"
  "dealCard1|cardSlide|1"  "dealCard2|cardSlide|2"  "dealCard3|cardSlide|3"  "dealCard4|cardSlide|4"
  "playCard1|cardPlace|1"  "playCard2|cardPlace|2"  "playCard3|cardPlace|3"  "playCard4|cardPlace|4"
  "trickWon|cardTakeOutPackage|1"
  "invalidMove|error|1"
  "bidConfirm|confirmation|1"
  "bidNil|question|1"
  "handComplete|chipsHandle|1"
  "gameWon|jingle|1"
  "gameLost|lose|1"
  "buttonTap|click|1"
  "reactionSent|switch|1"
  "chatSent|bong|1"
  "pointsAwarded|coin|1"
  "dailyBonus|chipsStack|1"
)

echo "Rendering..."
rm -f "$OUT"/*.wav
unmatched=()
for entry in "${MAP[@]}"; do
  IFS='|' read -r name pattern index <<<"$entry"
  if source_file=$(pick "$pattern" "$index"); then
    render "$source_file" "$name"
  else
    unmatched+=("$name (looked for '$pattern' #$index)")
  fi
done

if [[ ${#unmatched[@]} -gt 0 ]]; then
  echo
  echo "No source matched for:"
  printf '  %s\n' "${unmatched[@]}"
  echo "Run 'Tools/fetch_audio.sh --list' to see the filenames the packs actually shipped,"
  echo "then adjust MAP in this script. AudioService simply skips a clip it cannot load."
fi

total=$(find "$OUT" -name '*.wav' -exec wc -c {} + | tail -1 | awk '{print $1}')
total=${total:-0}
echo
printf 'Total audio: %d KB (budget %d KB)\n' $((total / 1024)) $((BUDGET_BYTES / 1024))
if (( total > BUDGET_BYTES )); then
  echo "!! Over the 1.5 MB budget. Trim the longest clips or drop a variant."
  exit 1
fi
[[ $missing -eq 0 ]] || echo "Note: some packs were not downloaded; see above."
