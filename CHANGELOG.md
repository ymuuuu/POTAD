# Changelog

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
