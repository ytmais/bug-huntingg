#!/usr/bin/env bash
set -euo pipefail

PROGRAM="${1:?usage: hunt.sh <program> <domain1> [domain2] ...}"
shift
DOMAINS_RAW="$*"

# Parse: terima koma ATAU spasi, strip scheme & path
IFS=', ' read -ra DARR <<< "$DOMAINS_RAW"
CLEAN=()
for d in "${DARR[@]}"; do
  d="${d#http://}"; d="${d#https://}"; d="${d%%/*}"
  [ -n "$d" ] && CLEAN+=("$d")
done
[ ${#CLEAN[@]} -eq 0 ] && { echo "[!] no valid domain"; exit 1; }

OUT="$(dirname "$0")/bounty/$PROGRAM"
rm -rf "$OUT/subs" "$OUT/live" "$OUT/urls" "$OUT/nuclei" "$OUT/js" "$OUT/secrets"
for sub in subs live urls nuclei js secrets ptai reports; do mkdir -p "$OUT/$sub"; done

export PATH="$HOME/go/bin:$PATH"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36$UA_SUFFIX"
RATE="${RATE:-5}"          # default 5 rps (OneDoc: max 5)
THREADS="${THREADS:-10}"
UA="Mozilla/5.0 (research)$UA_SUFFIX"

echo "[*] Program: $PROGRAM"
echo "[*] Domains: ${CLEAN[*]}"
echo "[*] Rate-limit: $RATE rps | UA suffix: ${UA_SUFFIX:-none}"

# 1. Subdomain enum
: > "$OUT/subs/all.txt"
for d in "${CLEAN[@]}"; do
  echo "[+] subfinder $d"
  subfinder -d "$d" -silent -all -o "$OUT/subs/$d.txt" || true
  [ -f "$OUT/subs/$d.txt" ] && cat "$OUT/subs/$d.txt" >> "$OUT/subs/all.txt"
  echo "$d" >> "$OUT/subs/all.txt"     # masukkan domain root
done
sort -u -o "$OUT/subs/all.txt" "$OUT/subs/all.txt"

# 2. DNS resolve (filter mati sebelum httpx)
echo "[+] dnsx"
if command -v dnsx >/dev/null; then
  dnsx -l "$OUT/subs/all.txt" -silent -a -resp -o "$OUT/subs/resolved.txt" || true
  awk '{print $1}' "$OUT/subs/resolved.txt" 2>/dev/null | sort -u > "$OUT/subs/alive.txt" || true
else
  cp "$OUT/subs/all.txt" "$OUT/subs/alive.txt"
fi
[ -s "$OUT/subs/alive.txt" ] || cp "$OUT/subs/all.txt" "$OUT/subs/alive.txt"

# 3. HTTP probe
echo "[+] httpx"
httpx -l "$OUT/subs/alive.txt" -silent -threads "$THREADS" -rate-limit "$RATE" \
  -H "User-Agent: $UA" -o "$OUT/live/live.txt" -title -tech-detect -status-code || true

# 4. URL discovery (historical)
echo "[+] gau + waybackurls"
for d in "${CLEAN[@]}"; do
  timeout 600 gau "$d" --threads 3 --rate-limit "$RATE" >> "$OUT/urls/gau.txt" 2>"$OUT/urls/gau.err" || true
  timeout 300 waybackurls "$d" >> "$OUT/urls/wayback.txt" 2>"$OUT/urls/wayback.err" || true
done

# 5. Katana — crawl live hosts + JS
echo "[+] katana (depth 2, JS crawl)"
if [ -s "$OUT/live/live.txt" ]; then
  katana -list "$OUT/live/live.txt" -d 2 -silent -rate-limit "$RATE" -jc -kf all \
    -H "User-Agent: $UA" -o "$OUT/urls/katana.txt" || true
fi

# 6. Merge
cat "$OUT/urls/gau.txt" "$OUT/urls/wayback.txt" "$OUT/urls/katana.txt" 2>/dev/null | sort -u > "$OUT/urls/all.txt" || true

# 7. Interesting endpoints
grep -Ei '(api|v1|v2|v3|auth|oauth|upload|redirect|admin|graphql|invite|share|export|download|internal|private|token|debug|swagger|openapi|\.json)' \
  "$OUT/urls/all.txt" | sort -u > "$OUT/urls/interesting.txt" || true

# 8. JS analysis
echo "[+] JS URL extraction"
grep -E '\.js(\?|$)' "$OUT/urls/all.txt" | sort -u > "$OUT/js/js_urls.txt" || true
wc -l < "$OUT/js/js_urls.txt" 2>/dev/null | xargs -I{} echo "    {} JS URLs"

echo "[+] download + scan secrets"
head -200 "$OUT/js/js_urls.txt" 2>/dev/null | while read -r u; do
  f=$(echo "$u" | md5sum | cut -c1-16).js
  timeout 20 curl -sSL -H "User-Agent: $UA" "$u" -o "$OUT/js/$f" 2>/dev/null || true
done
cat "$OUT/js"/*.js 2>/dev/null > "$OUT/js/all.js"

grep -aoEi '(api[_-]?key|secret|token|password|firebase|AIza[0-9A-Za-z_-]{30,}|sk_live_[0-9a-zA-Z]{20,}|ghp_[0-9a-zA-Z]{30,})[^a-zA-Z0-9]{0,3}[=:]["'\'']?[A-Za-z0-9_\-]{8,}' \
  "$OUT/js/all.js" 2>/dev/null | sort -u > "$OUT/secrets/grep_hits.txt" || true

grep -aoE '"/(api|v[0-9])/[a-zA-Z0-9_/\-{}:]+"' "$OUT/js/all.js" 2>/dev/null | sort -u > "$OUT/urls/endpoints_from_js.txt" || true

# 9. Nuclei
echo "[+] nuclei"
if [ -s "$OUT/live/live.txt" ]; then
  nuclei -l "$OUT/live/live.txt" \
    -t http/exposures/ -t http/misconfiguration/ -t http/cves/ -t http/takeovers/ \
    -severity low,medium,high,critical -rate-limit "$RATE" -bulk-size 5 -timeout 10 \
    -H "User-Agent: $UA" -o "$OUT/nuclei/results.txt" -jsonl -irr || true
else
  echo "[!] live.txt empty — skip nuclei"
fi

# 10. Summary
echo
echo "===== RINGKASAN $PROGRAM ====="
echo "Subdomains : $(wc -l < "$OUT/subs/all.txt" 2>/dev/null || echo 0)"
echo "Live hosts : $(wc -l < "$OUT/live/live.txt" 2>/dev/null || echo 0)"
echo "URLs       : $(wc -l < "$OUT/urls/all.txt" 2>/dev/null || echo 0)"
echo "Interesting: $(wc -l < "$OUT/urls/interesting.txt" 2>/dev/null || echo 0)"
echo "JS URLs    : $(wc -l < "$OUT/js/js_urls.txt" 2>/dev/null || echo 0)"
echo "API from JS: $(wc -l < "$OUT/urls/endpoints_from_js.txt" 2>/dev/null || echo 0)"
echo "Secrets    : $(wc -l < "$OUT/secrets/grep_hits.txt" 2>/dev/null || echo 0)"
echo "Nuclei hits: $(wc -l < "$OUT/nuclei/results.txt" 2>/dev/null || echo 0)"
echo "Output     : $OUT"
