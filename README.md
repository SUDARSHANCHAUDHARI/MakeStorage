# MakeStorage

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Shell](https://img.shields.io/badge/bash-3.2%2B-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

A safe CLI that reclaims Android-developer disk space on macOS. It clears the things that silently eat tens of gigabytes — `.gradle` caches, stale `build/` directories, old Gradle wrapper versions, Android Studio caches, and idle `node_modules` — while **preserving your APK and AAB artifacts**.

Destructive by nature, safe by default: nothing is deleted without a `--dry-run` preview or an explicit confirmation prompt.

## Install

```bash
git clone https://github.com/SUDARSHANCHAUDHARI/MakeStorage.git
cd MakeStorage
./install.sh            # symlinks `makestorage` into ~/.local/bin
```

Or run it directly without installing:

```bash
chmod +x makestorage
./makestorage status
```

## Usage

```bash
makestorage status      # show how much space is reclaimable — deletes nothing
makestorage clean       # preview, then ask before deleting
makestorage clean --dry-run   # preview only, never deletes
makestorage clean --yes       # skip the prompt (for automation)
makestorage setup       # install a weekly launchd job (Sundays 9am)
makestorage uninstall   # remove the weekly job
makestorage config      # print / create the config file
```

### Example

```console
$ makestorage status --root ~/code/android
MakeStorage — reclaimable space
roots: /Users/you/code/android

Project .gradle folders
  reclaimable: 1.2G across 8 item(s)
Build dirs (APK/AAB preserved)
  reclaimable: 3.4G across 22 item(s)
Gradle caches (>30d)
  reclaimable: 3.7G across 5 item(s)
Old Gradle wrapper versions
  reclaimable: 968.5M across 5 item(s)
Idle node_modules (>7d)
  reclaimable: 540.0M across 3 item(s)
Android Studio caches & logs
  reclaimable: 287.0M across 1 item(s)

Total reclaimable: 9.9G
```

Then `makestorage clean` shows the same breakdown and asks once before deleting.

### Point it at your projects

By default it scans the **current directory**. Point it elsewhere per-run:

```bash
makestorage clean --root ~/code/android --root ~/work/apps
```

Or set roots permanently in the config file (`makestorage config` creates it):

```bash
# ~/.config/makestorage/config
ROOTS=(
  "$HOME/code/android"
)
CACHE_DAYS=30        # delete ~/.gradle/caches older than N days
NODE_IDLE_DAYS=7     # delete node_modules from repos idle longer than N days
```

## What gets cleaned

| Target | Action |
|---|---|
| `<repo>/**/.gradle/` | Deleted |
| `<repo>/**/build/` | Cleaned — `outputs/apk` and `outputs/bundle` preserved |
| `~/.gradle/caches/` (older than `CACHE_DAYS`) | Deleted |
| `~/.gradle/wrapper/dists/` (all but newest) | Deleted |
| `<repo>/node_modules` (idle > `NODE_IDLE_DAYS`) | Deleted |
| `~/Library/Caches/Google/AndroidStudio*/` | Deleted |
| `~/Library/Logs/Google/` | Deleted |

`clean` also writes daemon/parallel/caching flags to `~/.gradle/gradle.properties` once (skipped if already present).

## Safety

- `status` and `--dry-run` never delete anything.
- `clean` previews everything and asks for confirmation unless `--yes` is passed.
- Protected paths (`/`, `$HOME`, `~/.gradle`, `~/Library`) are hard-refused even if mis-configured.

## Requirements

- macOS, Bash 3.2+
- `git` (used to detect idle repos)

## Roadmap

- `--stats` per-category MB report
- Kotlin/JVM compiler cache (`~/.kotlin/`) and AVD image cleanup
- Homebrew tap
- Optional single-binary rewrite (Go/Rust)

## Contributing

Issues and pull requests welcome at [github.com/SUDARSHANCHAUDHARI/MakeStorage](https://github.com/SUDARSHANCHAUDHARI/MakeStorage). It's a single Bash script — keep changes safe-by-default (dry-run + confirmation) and macOS-friendly.

## Author

[Sudarshan Chaudhari](https://github.com/SUDARSHANCHAUDHARI) — SudarshanTechLabs

## License

MIT
