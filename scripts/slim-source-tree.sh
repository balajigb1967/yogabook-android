#!/usr/bin/env bash
# Slim the LineageOS source tree for an x86_64-only device build on a small disk.
# - removes projects from .repo/manifests/default.xml that an x86_64 ISO build
#   never needs (emulator, ABI dumps, non-x86 toolchains, RBE, Trusty, ...)
# - deletes their worktrees and git object stores
# - prunes the projects left behind
set -uo pipefail
SRC="${SRC:-/root/lineage}"
cd "$SRC" || exit 1

# Paths (regex, anchored at project path) that are safe to drop for an
# x86_64 LineageOS device/ISO build:
DROP='^(cts|vts|development|trust|prebuilts/ndk|prebuilts/abi-dumps|prebuilts/android-emulator|prebuilts/remoteexecution-client|prebuilts/gcc/darwin-x86|prebuilts/gcc/linux-x86/(arm|arm64|aarch64|mips)|prebuilts/gradle-plugin|prebuilts/bazel)'

echo "== projects before: $(grep -c '<project ' .repo/manifests/default.xml) =="

# --- 1. trim the manifest (work on a local branch so repo is not upset)
cd .repo/manifests
git checkout -q -b yogabook-slim 2>/dev/null || git checkout -q yogabook-slim
python3 - "$DROP" <<'PYEOF'
import re, sys
pat = re.compile(sys.argv[1])
with open('default.xml') as f:
    lines = f.readlines()
kept, dropped = [], []
for ln in lines:
    m = re.search(r'path="([^"]+)"', ln)
    if ln.lstrip().startswith('<project') and m and pat.match(m.group(1)):
        dropped.append(m.group(1))
        continue
    kept.append(ln)
with open('default.xml', 'w') as f:
    f.writelines(kept)
with open('/tmp/dropped-projects.txt', 'w') as f:
    f.write('\n'.join(dropped))
print(f"dropped {len(dropped)} projects from manifest")
PYEOF
git commit -q -am "yogabook: slim manifest for x86_64-only build" || true

# --- 2. delete worktrees + object stores of dropped projects
cd "$SRC"
while read -r p; do
  [ -n "$p" ] || continue
  rm -rf "$p" ".repo/projects/$p.git" 2>/dev/null
  # project-objects store is keyed by repo name (org/repo)
done < /tmp/dropped-projects.txt

# object stores: map dropped paths back to project names from the original manifest
git -C .repo/manifests show HEAD~1:default.xml 2>/dev/null | \
  grep '<project ' | while read -r line; do
    name=$(echo "$line" | sed -n 's/.*name="\([^"]*\)".*/\1/p')
    path=$(echo "$line" | sed -n 's/.*path="\([^"]*\)".*/\1/p')
    [ -z "$path" ] && path="$name"
    if ! grep -qx "$path" /tmp/dropped-projects.txt 2>/dev/null; then continue; fi
    rm -rf ".repo/project-objects/${name}.git" 2>/dev/null
  done

echo "== work tree + objects trimmed =="
df -h / | tail -1
