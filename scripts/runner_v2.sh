#!/usr/bin/env bash
set -euo pipefail

MANIFEST="$1"               # path to manifest json
OUT_DIR="$2"                # output base dir, e.g., /srv/stylegen/output
LOG="${3:-/srv/stylegen/logs/run_$(date +%F_%H%M).log}"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image-preview:generateContent"
GEMINI_API_KEY=""

mkdir -p "$OUT_DIR" "$(dirname "$LOG")"

jq_type=$(jq -r 'if .images then "flatlay" elif .jobs then "mannequin" else "generic" end' "$MANIFEST")

echo "Start batch type=$jq_type manifest=$MANIFEST" | tee -a "$LOG"

retry() {
  local n=0 max=3 delay=5
  until "$@"; do
    n=$((n+1))
    if [[ $n -ge $max ]]; then return 1; fi
    sleep $delay
  done
}

if [[ "$jq_type" == "flatlay" ]]; then
  jq -c '.images[]' "$MANIFEST" | while read -r item; do
    file=$(echo "$item" | jq -r '.file_name')
    prompt=$(echo "$item" | jq -r '.prompt')
    width=$(echo "$item" | jq -r '.width')
    height=$(echo "$item" | jq -r '.height')
    out="$OUT_DIR/$file"
    mkdir -p "$(dirname "$out")"
    echo "Render $file" | tee -a "$LOG"



retry curl -sS -k -X POST "$API_URL" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "contents": [ { "parts": [ { "text": "'"$prompt"'" } ] } ] }' \
  --output "$out"

  done
elif [[ "$jq_type" == "mannequin" ]]; then
  # Need cards.json and templates
  CARDS_JSON="${CARDS_JSON:-/srv/stylegen/repo/content/json/cards.json}"
  TPL_JSON="${TPL_JSON:-/srv/stylegen/repo/content/json/mannequins.templates.json}"
  jq -c '.jobs[]' "$MANIFEST" | while read -r job; do
    tpl_id=$(echo "$job" | jq -r '.template_id')
    profile=$(echo "$job" | jq -r '.profile_code')
    card=$(echo "$job" | jq -r '.card_id')
    file=$(echo "$job" | jq -r '.file_name')
    out="$OUT_DIR/$file"
    mkdir -p "$(dirname "$out")"

    prompt_tpl=$(jq -r --arg id "$tpl_id" '.templates[] | select(.id==$id) | .prompt' "$TPL_JSON")
    width=$(jq -r --arg id "$tpl_id" '.templates[] | select(.id==$id) | .width' "$TPL_JSON")
    height=$(jq -r --arg id "$tpl_id" '.templates[] | select(.id==$id) | .height' "$TPL_JSON")

    items=$(jq -r --arg id "$card" '.cards[] | select(.id==$id) | .items | map(.slot + " " + .color_hex) | join("; ")' "$CARDS_JSON")
    prompt="${prompt_tpl//'{{items}}'/$items}"

    echo "Render $file (tpl=$tpl_id, card=$card)" | tee -a "$LOG"
    retry curl -sS -X POST "$API_URL" \
      -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" \
      -d "{\"prompt\":\"$prompt\",\"width\":$width,\"height\":$height,\"format\":\"webp\"}" \
      --output "$out"
  done
else
  echo "Unknown manifest structure" | tee -a "$LOG"; exit 1
fi

echo "Done: $MANIFEST" | tee -a "$LOG"