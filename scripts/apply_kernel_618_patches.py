#!/usr/bin/env python3
"""
apply_kernel_618_patches.py
===========================
Applies the 11 Yoga Book hardware backport patches to any Linux 6.18 kernel tree
(e.g. android-generic/kernel-zenith).

Usage:
    python scripts/apply_kernel_618_patches.py [path_to_kernel_source]
"""

import os
import sys
import subprocess

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATCH_DIR = os.path.join(BASE_DIR, "patches-kernel-6.18")

def main():
    if len(sys.argv) > 1:
        ksrc = sys.argv[1]
    else:
        ksrc = os.environ.get("KSRC", os.path.join(BASE_DIR, "kernel-zenith"))

    if not os.path.isdir(ksrc):
        print(f"ERROR: Kernel source directory not found: {ksrc}")
        print("Please provide the path to the kernel-zenith 6.18 source tree.")
        sys.exit(1)

    if not os.path.isdir(PATCH_DIR):
        print(f"ERROR: Patches directory not found: {PATCH_DIR}")
        sys.exit(1)

    patch_files = sorted([f for f in os.listdir(PATCH_DIR) if f.endswith(".patch")])
    if not patch_files:
        print("ERROR: No .patch files found in patches-kernel-6.18")
        sys.exit(1)

    print("=" * 70)
    print(f"  APPLYING YOGA BOOK HARDWARE PATCHES TO KERNEL 6.18 ({ksrc})")
    print("=" * 70)

    applied = 0
    failed = 0

    for pf in patch_files:
        p_path = os.path.join(PATCH_DIR, pf)
        print(f"[*] Applying {pf}...", end=" ", flush=True)

        # Try git am --3way
        cmd_am = ["git", "-C", ksrc, "am", "--3way", "--whitespace=nowarn", p_path]
        res = subprocess.run(cmd_am, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode == 0:
            print("OK (git am)")
            applied += 1
            continue

        # Abort failed am
        subprocess.run(["git", "-C", ksrc, "am", "--abort"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Fallback to git apply
        cmd_apply = ["git", "-C", ksrc, "apply", "--whitespace=nowarn", "--reject", p_path]
        res = subprocess.run(cmd_apply, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode == 0:
            print("OK (git apply)")
            applied += 1
        else:
            print("FAILED")
            failed += 1

    print("-" * 70)
    print(f"Result: {applied} applied, {failed} failed.")
    print("=" * 70)
    sys.exit(1 if failed > 0 else 0)

if __name__ == "__main__":
    main()
