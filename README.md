# MakeStorage

Android developer storage cleanup scripts for macOS. Reclaims disk space by clearing `.gradle` caches, stale `build/` directories, and Android Studio logs — while preserving APK and AAB outputs.

## Scripts

### `android_setup.sh`
Full setup + immediate cleanup. Run once to:
- Clean `.gradle` and `build/` directories across all projects
- Remove old Gradle global caches (>30 days)
- Clear Android Studio caches and logs
- Configure global `gradle.properties` for daemon + parallel builds
- Install a weekly cron job (`~/android_cleanup.sh`) that runs every Sunday at 9am

```bash
chmod +x android_setup.sh
./android_setup.sh
```

### `android_storage_cleanup.sh`
Standalone cleanup script. Same cleaning steps as above without the setup/cron installation.

```bash
chmod +x android_storage_cleanup.sh
./android_storage_cleanup.sh
```

## What gets cleaned

| Target | Action |
|---|---|
| `<repo>/**/.gradle/` | Deleted |
| `<repo>/**/build/` | Cleaned (APK + AAB outputs preserved) |
| `~/.gradle/caches/` (>30 days) | Deleted |
| `~/Library/Caches/Google/AndroidStudio*/` | Deleted |
| `~/Library/Logs/Google/` | Deleted |

## Requirements

- macOS
- Bash
- Projects under `~/SUDARSHAN_CODE/sudarshan_repos/`

## Author

[Sudarshan Chaudhari](https://github.com/SUDARSHANCHAUDHARI) — SudarshanTechLabs

## License

MIT
