#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

[ -f .env ] || { echo "X .env not found (copy .env.example)" >&2; exit 1; }
set -a; . ./.env; set +a
PORT="${PORT:-2222}"
[ -n "${ROOT_PASSWORD:-}" ] || { echo "X ROOT_PASSWORD missing in .env" >&2; exit 1; }

target="root@127.0.0.1"
remote="/var/mobile/auto-tweak"
opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# Resolve URLs in ipa.txt to actual .ipa files in _ipas/ (cached by filename).
ipa_dir="_ipas"
mkdir -p "$ipa_dir"
if [ -f ipa.txt ]; then
  while IFS= read -r raw || [ -n "$raw" ]; do
    url=$(echo "${raw%%#*}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$url" ] && continue

    if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/?#]+) ]]; then
      owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]%.git}"
      asset_url=$(curl -fsSL -A auto-tweak "https://api.github.com/repos/$owner/$repo/releases/latest" \
        | grep -oE '"browser_download_url":[[:space:]]*"[^"]+\.t?ipa"' | head -1 \
        | sed 's/.*"\(https[^"]*\)"/\1/')
      [ -z "$asset_url" ] && { echo "[host] X $owner/$repo : no .ipa/.tipa in latest release"; continue; }
      name=$(basename "$asset_url")
      if [ -f "$ipa_dir/$name" ]; then echo "[host] cached $name"; continue; fi
      echo "[host] downloading $name"
      curl -fsSL -A auto-tweak "$asset_url" -o "$ipa_dir/$name"
    elif [[ "$url" =~ \.(ipa|tipa)(\?|$) ]]; then
      name=$(basename "${url%%\?*}")
      if [ -f "$ipa_dir/$name" ]; then echo "[host] cached $name"; continue; fi
      echo "[host] downloading $name"
      curl -fsSL -A auto-tweak "$url" -o "$ipa_dir/$name"
    else
      echo "[host] X unsupported ipa.txt entry: $url"
    fi
  done < ipa.txt
fi

iproxy "$PORT" 22 >/dev/null 2>&1 &
IPROXY_PID=$!
trap 'kill "$IPROXY_PID" 2>/dev/null || true' EXIT
sleep 2

run()  { sshpass -p "$ROOT_PASSWORD" ssh "${opts[@]}" -p "$PORT" "$target" "$@"; }
push() { sshpass -p "$ROOT_PASSWORD" scp "${opts[@]}" -P "$PORT" "$@"; }

run "mkdir -p $remote && rm -rf $remote/_ipas" || { echo "X ssh connect failed" >&2; exit 1; }
push -r repo.txt tweak.txt additional.txt device.sh "$ipa_dir" "$target:$remote/" || { echo "X upload failed" >&2; exit 1; }
run "chmod +x $remote/device.sh && $remote/device.sh"
