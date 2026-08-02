# POTAD — Pixel OTA Disabler

Stops Google from pushing system updates to your Pixel. Works with Magisk, KernelSU,
KernelSU Next, SukiSU and APatch.

## What it does

Three layers, independent of each other. If one fails the other two still work.

| Layer | What | When |
|---|---|---|
| A | `pm disable` on every GMS/GSF OTA component that exists on your build | every boot |
| B | bind-mounts a hosts file that blackholes `ota.googlezip.net` and `update.googleapis.com` | boot |
| C | `update_engine_client --cancel --reset_status` to clear an already-staged update | action button |

Layer A doesn't rely on a hardcoded list alone. It also scans the live build, so if Google
renames a component or a new Android version adds one, it gets picked up without me
shipping an update. Anything it isn't sure about gets logged as `NEW:` and left running —
those are usually Play Store app-update components, and killing those breaks app updates.

Layer B merges into your existing hosts file instead of replacing it, so AdAway and
similar keep working.

Nothing here depends on your root manager's mount backend, which is the usual reason these modules quietly stop working.

## Install

Grab the zip from [Releases](https://github.com/ymuuuu/POTAD/releases), flash it, reboot.

Once installed it'll show up as an update in your root manager when I push a new version.

Or build it yourself:

```sh
./build.sh
```

## Using it

Press the module's **Action** button. It shows what state things are in, then asks:

- **Vol Up** — Block. Clears a stuck OTA and re-applies everything. No reboot needed.
- **Vol Down** — Restore. Undoes everything the module did.
- **Nothing** — after 15 seconds it does Block, which is the safe one.

Log lives at `/data/adb/potad/potad.log`.

## Undoing it

**Removing the module does not undo anything.** The disabled state belongs to Android, not
to the module — it's stored in `package-restrictions.xml` and it survives uninstall. So if
you want your phone back to stock, run the restore first.

Two ways:

- Action button → Vol Down
- `su -c 'sh /data/adb/potad/restore.sh'`

Restore only re-enables the components *this module* disabled. If you'd already disabled
something yourself before installing, it stays disabled — it isn't POTAD's to undo. It also
lifts the hosts blackhole and cleans up its own files.

`restore.sh` is installed to `/data/adb/potad/` rather than inside the module folder,
specifically so it still works after you've removed the module.

## Checking it worked

```sh
su -c 'cat /data/adb/potad/potad.log'          # expect a "layer A:" line
su -c 'grep googlezip /system/etc/hosts'       # expect 127.0.0.1 ota.googlezip.net
```

Then Settings → System → System update. Should be nothing pending.

If you use an ad-blocker, check your own hosts entries are still there.

## What it deliberately doesn't do

It doesn't shadow `/system/bin/update_engine`. That trick works, but it's the one approach that depends on the mount backend, and it's the known failure mode on setups running a mount metamodule like Magic Mount-rs — the module shows as enabled while doing absolutely nothing. It also breaks manual sideloading and Play system updates.

If an OTA gets through anyway, the log will tell you which layer missed it. Open an issue
with the log and I'll look.

## Credits

This is a consolidation of three modules that came before it. The hard parts were already
solved by other people:

- **[TMW1996](https://github.com/TMW1996)** — `PixelSystemupdateBlock_v3`. The hosts-file approach for blackholing the OTA endpoints.
- **[Badabing2005](https://github.com/badabing2005)** — `block_ota_updates` and `clear_ota_updates`. The `update_engine_client` binaries shipped in `module/bin/` are from `clear_ota_updates`; they're AOSP builds (r28 and r72), and the module tries the newer one first and falls back if it won't link on your device. Also the idea of cancelling a staged update rather than only preventing new ones.

If you want the originals rather than this, they're worth a look — both authors have been at this a lot longer than I have.

## Development

```sh
sh tests/run.sh                                    # test suite, no device needed
shellcheck -s sh module/*.sh module/common/*.sh    # static analysis
./build.sh                                         # builds dist/POTAD-<version>.zip
```