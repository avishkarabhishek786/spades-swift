#!/usr/bin/env bash
# Regenerates App/Resources/Audio from Kenney's CC0 packs.
#
# NOT on the critical path of a build. The processed WAVs are committed (see
# CLAUDE.md §10) — CC0 explicitly permits redistribution, the whole set is well
# under 1.5 MB, and a hermetic build beats a network dependency. This script is
# provenance and a regeneration path, nothing more.
#
# Usage:
#   Tools/fetch_audio.sh            download, convert, install
#   Tools/fetch_audio.sh --list     list what the downloaded packs contain
#   Tools/fetch_audio.sh --verify   check the vendored set against the sound map
#
# Kenney's download URLs carry a rotating content hash, so the URL is scraped
# from the asset page rather than hard-coded. If that ever breaks, drop the
# zips into .build/audio-src/ by hand and re-run — the script uses whatever is
# already there.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/.build/audio-src"
WORK="$ROOT/.build/audio-work"
OUT="$ROOT/App/Resources/Audio"
BUDGET_BYTES=$((1536 * 1024))   # 1.5 MB, per §10

PACK_SLUGS=(casino-audio interface-sounds ui-audio)

# effect-name | preferred source basename | fallback substring
#
# Card handling from Casino Audio covers everything table-related; the
# interface packs cover buttons and confirmations. dealCard and playCard ship
# four takes each and the app picks one at random — a single card sound
# repeated fifty-two times during a deal is the fastest way to make a game
# feel cheap.
MAP=(
  "shuffle|card-shuffle|shuffle"
  "dealCard1|card-slide-1|card-slide"
  "dealCard2|card-slide-2|card-slide"
  "dealCard3|card-slide-3|card-slide"
  "dealCard4|card-slide-4|card-slide"
  "playCard1|card-place-1|card-place"
  "playCard2|card-place-2|card-place"
  "playCard3|card-place-3|card-place"
  "playCard4|card-place-4|card-place"
  "trickWon|card-shove-1|card-shove"
  "invalidMove|error_003|error"
  "bidConfirm|confirmation_001|confirmation"
  "bidNil|question_001|question"
  "handComplete|chips-handle-1|chips-handle"
  "gameWon|maximize_008|maximize"
  "gameLost|minimize_008|minimize"
  "buttonTap|click_001|click"
  "reactionSent|pluck_001|pluck"
  "chatSent|bong_001|bong"
  "pointsAwarded|chip-lay-1|chip-lay"
  "dailyBonus|chips-stack-1|chips-stack"
)

if [[ "${1:-}" == "--verify" ]]; then
  missing=()
  for entry in "${MAP[@]}"; do
    name="${entry%%|*}"
    [[ -f "$OUT/$name.wav" ]] || missing+=("$name.wav")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing vendored audio:"; printf '  %s\n' "${missing[@]}"; exit 1
  fi
  total=$(find "$OUT" -name '*.wav' -exec wc -c {} + | tail -1 | awk '{print $1}')
  printf 'All %d clips present, %d KB of a %d KB budget.\n' \
    "${#MAP[@]}" $((${total:-0} / 1024)) $((BUDGET_BYTES / 1024))
  exit 0
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)"; exit 1; }
command -v unzip  >/dev/null || { echo "unzip is required"; exit 1; }

mkdir -p "$SRC" "$WORK" "$OUT"

echo "Downloading packs..."
missing_pack=0
for slug in "${PACK_SLUGS[@]}"; do
  zip="$SRC/$slug.zip"
  if [[ -f "$zip" ]]; then echo "  have $slug.zip"; continue; fi
  url=$(curl -fsSL "https://kenney.nl/assets/$slug" | grep -oE 'https://[^"]*\.zip' | head -1)
  if [[ -z "$url" ]]; then
    echo "  !! could not find a download link on https://kenney.nl/assets/$slug"
    echo "     Download it manually and save as $zip"
    missing_pack=1
    continue
  fi
  echo "  fetching $slug"
  curl -fsSL -o "$zip.part" "$url" && mv "$zip.part" "$zip" || { rm -f "$zip.part"; missing_pack=1; }
done

echo "Extracting..."
rm -rf "$WORK/raw"; mkdir -p "$WORK/raw"
shopt -s nullglob
for zip in "$SRC"/*.zip; do
  unzip -qo "$zip" -d "$WORK/raw/$(basename "${zip%.zip}")"
done

mapfile -t ALL < <(find "$WORK/raw" -type f \( -iname '*.wav' -o -iname '*.ogg' -o -iname '*.mp3' \) | sort)

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "${ALL[@]}"
  exit 0
fi

if [[ ${#ALL[@]} -eq 0 ]]; then
  echo "No audio found in $WORK/raw. Put the pack zips in $SRC and re-run."
  exit 1
fi

# Exact basename first, then a substring match so a rename degrades to a
# near-miss rather than a hole.
pick() {
  local exact="$1" fallback="$2" file base
  for file in "${ALL[@]}"; do
    base="$(basename "$file")"
    [[ "${base%.*}" == "$exact" ]] && { printf '%s' "$file"; return 0; }
  done
  for file in "${ALL[@]}"; do
    base="$(basename "$file")"
    [[ "${base,,}" == *"${fallback,,}"* ]] && { printf '%s' "$file"; return 0; }
  done
  return 1
}

# 16-bit 44.1 kHz mono WAV, leading silence trimmed hard, peak normalised to
# about -3 dBFS.
#
# The trim matters more than it sounds like it should: forty milliseconds of
# lead-in on a card sound reads to the player as input lag, not as audio.
render() {
  local input="$1" name="$2"
  local trimmed="$WORK/${name}.trim.wav"

  ffmpeg -v error -y -i "$input" \
    -af "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.005,aformat=channel_layouts=mono" \
    -ar 44100 -ac 1 -c:a pcm_s16le "$trimmed" || return 1

  # Two-pass peak normalisation: measure, then apply the exact gain.
  local peak gain
  peak=$(ffmpeg -v info -i "$trimmed" -af volumedetect -f null - 2>&1 \
         | awk -F': ' '/max_volume/ {gsub(/ dB/, "", $2); print $2}' | tail -1)
  peak=${peak:-0}
  gain=$(awk -v p="$peak" 'BEGIN { printf "%.2f", -3.0 - p }')

  ffmpeg -v error -y -i "$trimmed" -af "volume=${gain}dB" \
    -ar 44100 -ac 1 -c:a pcm_s16le "$OUT/${name}.wav" || return 1
  rm -f "$trimmed"
  printf '  %-14s <- %-24s (peak %s dB -> -3 dB)\n' "$name.wav" "$(basename "$input")" "$peak"
}

echo "Rendering..."
rm -f "$OUT"/*.wav
unmatched=()
for entry in "${MAP[@]}"; do
  IFS='|' read -r name exact fallback <<<"$entry"
  if source_file=$(pick "$exact" "$fallback"); then
    render "$source_file" "$name" || unmatched+=("$name (ffmpeg failed)")
  else
    unmatched+=("$name (no match for '$exact' or '$fallback')")
  fi
done

if [[ ${#unmatched[@]} -gt 0 ]]; then
  echo
  echo "No source matched for:"
  printf '  %s\n' "${unmatched[@]}"
  echo "Run 'Tools/fetch_audio.sh --list' to see what the packs shipped, then adjust MAP."
fi

total=$(find "$OUT" -name '*.wav' -exec wc -c {} + | tail -1 | awk '{print $1}')
total=${total:-0}
echo
printf 'Total audio: %d KB (budget %d KB)\n' $((total / 1024)) $((BUDGET_BYTES / 1024))
if (( total > BUDGET_BYTES )); then
  echo "!! Over the 1.5 MB budget. Trim the longest clips or drop a variant."
  exit 1
fi
[[ $missing_pack -eq 0 ]] || { echo "Note: some packs were not downloaded; see above."; exit 1; }
