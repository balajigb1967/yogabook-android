# Google Apps & Play certification

## The situation

This ROM is built from pure LineageOS 23.2 sources. Two facts:

1. **MindTheGapps does not publish an Android 16 x86_64 package** (only
   ARM/ARM64). GApps for x86_64 Android 16 are only available from
   third-party builders — the build script will add one automatically when a
   known-good download is reachable, and skip GApps with a clear message
   otherwise. The ROM is fully usable without them (F-Droid / Aurora Store).
2. Any self-built Android shows **"Device is not certified"** in Google Play
   until you register it. That is normal — it is *not* the old "unlicensed
   version" watermark (which is gone: this build has no third-party ROM
   licensing code at all).

## Registering the device for Google Play

1. Install Play Store (if GApps are included).
2. Open Play Store → ⋮ → Settings → About → tap **Play Protect certification**.
   It shows a long device/registration code.
3. On a browser, sign in with your Google account at
   `https://www.google.com/android/uncertified` and enter that code.
4. Force-stop Play Store, clear its cache, reboot — the warning clears within
   a day.

Apps that use Play Integrity (banking) may still refuse unlocked/rooted
environments — that is a Google-side policy, not something the ROM can fix.
