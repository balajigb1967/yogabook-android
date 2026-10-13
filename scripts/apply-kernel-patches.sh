#!/usr/bin/env bash
# Apply Yoga Book hardware patches to the kernel source tree.
#
#   audio    b4/asoc-yogabook-v4          - RT5677 Cherry Trail machine driver (REQUIRED)
#   tablets  b4/x86-tablets-yogabook      - x86-android-tablets sound+haptics entries (REQUIRED)
#   camera   yogabook-torvalds-20220719+atomisp - AtomISP camera sensors (BEST EFFORT)
#
# Patches come from https://github.com/jekhor/yogabook-linux-kernel
set -uo pipefail

SRC="${SRC:-$HOME/lineage}"
KSRC="$SRC/external/debian-linux"
CACHE="$SRC/.yogabook-patches"
UP=https://github.com/jekhor/yogabook-linux-kernel

[ -d "$KSRC" ] || { echo "ERROR: kernel tree missing: $KSRC" >&2; exit 1; }
mkdir -p "$CACHE"

series() {
  local branch="$1" out="$2" max="${3:-25}"
  local dir="$CACHE/$(echo "$branch" | tr / _)"
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    git clone --quiet --filter=blob:none --depth="$max" \
      --single-branch -b "$branch" "$UP" "$dir" || return 1
  fi
  # The b4 branches stack the series on top of linux-next; the series itself
  # is the leading run of commits by the Yoga Book maintainer.
  local n
  n=$(git -C "$dir" log --format='%ae' -"$max" | grep -c 'jekhor@gmail.com' || true)
  [ "$n" -eq 0 ] && { echo "  no series commits found in $branch" >&2; return 1; }
  git -C "$dir" format-patch --stdout --minimal -k "HEAD~$n..HEAD" > "$out" || return 1
  echo "  $branch: $n patches -> $out"
}

apply() {
  local mbox="$1" required="$2"
  if git -C "$KSRC" am --whitespace=nowarn "$mbox"; then
    echo "  applied $(basename "$mbox") via git am"
    return 0
  fi
  git -C "$KSRC" am --abort >/dev/null 2>&1
  if git -C "$KSRC" apply --whitespace=nowarn --reject "$mbox"; then
    echo "  applied $(basename "$mbox") via git apply --reject (check *.rej if any)"
    return 0
  fi
  if [ "$required" = yes ]; then
    echo "ERROR: required patch set $(basename "$mbox") failed to apply." >&2
    echo "       (kernel base may have moved; update the series or pin the kernel)" >&2
    return 1
  fi
  echo "  WARNING: optional $(basename "$mbox") did not apply - continuing without it (camera stays best-effort)"
  return 0
}

echo "== Yoga Book kernel patches =="

series b4/asoc-yogabook-v4     "$CACHE/asoc.patch"     && \
  apply "$CACHE/asoc.patch" yes || exit 1

series b4/x86-tablets-yogabook "$CACHE/tablets.patch"  && \
  apply "$CACHE/tablets.patch" yes || exit 1

series yogabook-torvalds-20220719+atomisp "$CACHE/atomisp.patch" 20 && \
  apply "$CACHE/atomisp.patch" no || true

echo "== done =="
