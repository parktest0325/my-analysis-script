#!/var/jb/bin/bash
set -u

PREFIX=/var/jb
APT=$PREFIX/usr/bin/apt
SOURCES=$PREFIX/etc/apt/sources.list.d/auto-installer.sources
HERE=$(cd "$(dirname "$0")" && pwd)
LOG=/tmp/auto-tweak.log

g=$'\033[32m'; r=$'\033[31m'; y=$'\033[33m'; b=$'\033[1m'; n=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$g" "$n" "$1"; }
skip() { printf '  %s~%s %s (already in another sources file)\n' "$y" "$n" "$1"; }
fail() { printf '  %s✗%s %s\n' "$r" "$n" "$1"; [[ -n "${2:-}" ]] && sed 's/^/    /' <<< "$2"; }
step() { printf '\n%s[%s]%s\n' "$b" "$1" "$n"; }
clean() { sed 's/#.*//;s/[[:space:]]*$//;s/^[[:space:]]*//' "$1" | grep -v '^$' || true; }

[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }

step "register repos"
: > "$SOURCES"
# Collect URIs already declared in any other sources file so we don't conflict (e.g. chariz in sileo.sources).
existing=$(
  { sed -n 's/^URIs:[[:space:]]*//p'                "$PREFIX/etc/apt/sources.list.d/"*.sources 2>/dev/null
    sed -n 's/^deb[[:space:]]\+\([^ ]\+\).*/\1/p'   "$PREFIX/etc/apt/sources.list.d/"*.list    2>/dev/null
  } | sed 's|/$||' | sort -u
)
clean "$HERE/repo.txt" | while IFS= read -r url; do
  if grep -Fxq "${url%/}" <<< "$existing"; then
    skip "$url"
    continue
  fi
  printf 'Types: deb\nURIs: %s\nSuites: ./\nComponents:\nTrusted: yes\n\n' "$url" >> "$SOURCES"
  ok "$url"
done

step "apt update"
"$APT" update &> "$LOG"
errs=$(grep -E '^(E:|W:)' "$LOG" | grep -v 'is configured multiple times' | tail -n 5)
if [[ -z "$errs" ]]; then
  ok "updated"
else
  # Pre-existing broken repos (palera.in pubkey, bigboss unsigned, etc.) are not ours;
  # surface them but don't bail — per-package install will report what actually failed.
  fail "warnings (proceeding to install)" "$errs"
fi

step "install tweaks"
clean "$HERE/tweak.txt" | while IFS= read -r pkg; do
  if "$APT" install -y --allow-unauthenticated "$pkg" &> "$LOG"; then
    ok "$pkg"
  else
    reason=$(grep -E '^E:' "$LOG" | tail -n 2)
    [[ -z "$reason" ]] && reason=$(tail -n 3 "$LOG")
    fail "$pkg" "$reason"
  fi
done

step "install IPAs"
TROLLHELPER="$PREFIX/Applications/TrollStoreLite.app/trollstorehelper"
IPA_DIR="$HERE/_ipas"
shopt -s nullglob
ipas=("$IPA_DIR"/*.ipa "$IPA_DIR"/*.tipa)
if [[ ${#ipas[@]} -eq 0 ]]; then
  ok "nothing queued"
elif [[ ! -x "$TROLLHELPER" ]]; then
  fail "TrollStore Lite helper not found at $TROLLHELPER (install com.opa334.trollstorelite first)"
else
  for ipa in "${ipas[@]}"; do
    name=$(basename "$ipa")
    if "$TROLLHELPER" install "$ipa" &> "$LOG"; then
      ok "$name"
    else
      fail "$name" "$(tail -n 5 "$LOG")"
    fi
  done
fi

step "uicache"
if "$PREFIX/usr/bin/uicache" -a &> /dev/null; then
  ok "refreshed"
else
  fail "uicache failed"
fi

if [[ -s "$HERE/additional.txt" ]]; then
  printf '\n%s[recommended manual installs]%s\n' "$b" "$n"
  cat "$HERE/additional.txt"
fi
echo
