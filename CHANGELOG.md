# Changelog

## 0.2.1

Fixes Layer B hosts bind visibility under root-hiding Zygisk implementations such as ReZygisk.

- Moved the merged hosts bind source from `/data/adb/potad/hosts` to `/data/adb/modules/potad/hosts`, changing the `/proc/self/mountinfo` mount root to `/adb/modules/potad/hosts` so ReZygisk (`umount_root`) unmounts it inside app namespaces while keeping POTAD's self-managed bind mount independent of mount metamodules.
- Rebuilds `/data/adb/modules/potad/hosts` automatically on boot or action re-apply after module updates replace the module directory.
- Added upgrade migration: unmounts any active legacy `/adb/potad/hosts` bind before binding the new source (never stacking binds or touching third-party hosts mounts) and deletes unused `/data/adb/potad/hosts`.
- Updated `uninstall.sh` and standalone `restore.sh` to lift POTAD's hosts bind and clean up both `/data/adb/modules/potad/hosts` and `/data/adb/potad/hosts`, including when `restore.list` is empty.

## 0.2.0

Fixes for three gaps found while verifying 0.1.1 against a live Pixel 6a.

- Honest layer-A reporting: after the disable loop, every component's state is re-read
  from a fresh `pm dump` instead of trusting the `pm disable` exit status. Components
  that come back enabled (seen on-device: `SystemUpdateActivity`,
  `OtaSuggestionSummaryProvider`) are logged at ERROR and re-asserted exactly once.
- The action button's status section now reports the real per-component state
  (`disabled:` / `ENABLED:`) instead of `present:`, plus per-host verification that the
  hosts entries are live *and* the bind mount is up, and the time of GMS's last
  successful update check. `android.googleapis.com` stays reachable by design — blocking
  it would break sign-in, FCM push, Play Store and device checkin.
- The Block path now clears leftover OTA payload files from `/data/ota_package`
  (whitelisted names only, everything else logged and left alone), which update_engine
  kept feeding itself from even after `--cancel` reported nothing staged.

## 0.1.1

No functional changes. Released to check that in-app updating works from the
root manager.

## 0.1.0

First release.

- Disables the GMS/GSF OTA components, on every boot, with a runtime scan so a renamed
  component still gets caught.
- Blackholes `ota.googlezip.net` and `update.googleapis.com` via a merged hosts file, so
  an existing ad-blocker's entries survive.
- Clears an already-staged update from the action button.
- Restore path: action button → Vol Down, or `sh /data/adb/potad/restore.sh`. Only undoes
  what this module changed, and still works after the module is removed.
