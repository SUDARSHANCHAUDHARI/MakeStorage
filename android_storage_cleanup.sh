#!/bin/bash

BASE="$HOME/SUDARSHAN_CODE/sudarshan_repos"

echo "================================================"
echo "  Android Dev Storage Cleanup — Sudarshan"
echo "================================================"
echo ""

# ── STEP 1 — Clean project .gradle folders ────────
echo "[1/7] Cleaning project .gradle folders..."
find "$BASE" -name ".gradle" -type d -prune -exec rm -rf {} +
echo "Done."

# ── STEP 2 — Clean build/ dirs, keep APK & AAB ───
echo ""
echo "[2/7] Cleaning build/ dirs (keeping APK & AAB)..."
find "$BASE" -path "*/build" -type d | while read builddir; do
  find "$builddir" -mindepth 1 -maxdepth 1 -type d \
    ! -name "outputs" \
    -exec rm -rf {} +
  if [ -d "$builddir/outputs" ]; then
    find "$builddir/outputs" -mindepth 1 -maxdepth 1 -type d \
      ! -name "apk" ! -name "bundle" \
      -exec rm -rf {} +
  fi
done
echo "Done."

# ── STEP 3 — Clean old Gradle global caches ───────
echo ""
echo "[3/7] Cleaning Gradle caches older than 7 days..."
find ~/.gradle/caches -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
echo "Done."

# ── STEP 3b — Clean old Gradle wrapper versions ───
echo ""
echo "[3b] Cleaning old Gradle wrapper versions..."
if [ -d ~/.gradle/wrapper/dists ]; then
  ls -t ~/.gradle/wrapper/dists/ 2>/dev/null | tail -n +2 | while read old; do
    rm -rf ~/.gradle/wrapper/dists/"$old"
    echo "  Removed wrapper: $old"
  done
fi
echo "Done."

# ── STEP 3c — Clean node_modules from inactive repos ──
echo ""
echo "[3c] Cleaning node_modules from repos idle > 7 days..."
BASE_REPOS="$HOME/SUDARSHAN_CODE/sudarshan_repos"
now=$(date +%s)
for repo in "$BASE_REPOS"/*/; do
  [ -d "$repo/node_modules" ] || continue
  last_commit=$(git -C "$repo" log -1 --format="%at" 2>/dev/null || echo 0)
  age=$(( (now - last_commit) / 86400 ))
  if [ "$age" -gt 7 ]; then
    size=$(du -sh "$repo/node_modules" 2>/dev/null | cut -f1)
    rm -rf "$repo/node_modules"
    echo "  Removed: $(basename $repo)/node_modules ($size, last commit ${age}d ago)"
  fi
done
echo "Done."

# ── STEP 4 — Clean Android Studio caches ──────────
echo ""
echo "[4/7] Cleaning Android Studio caches..."
rm -rf ~/Library/Caches/Google/AndroidStudio*/ 2>/dev/null
rm -rf ~/Library/Logs/Google/ 2>/dev/null
echo "Done."

# ── STEP 5 — Global Gradle settings ───────────────
echo ""
echo "[5/7] Setting up global Gradle properties..."
GRADLE_PROPS="$HOME/.gradle/gradle.properties"
mkdir -p "$HOME/.gradle"
if grep -q "org.gradle.daemon" "$GRADLE_PROPS" 2>/dev/null; then
  echo "Already set — skipping."
else
  cat >> "$GRADLE_PROPS" << 'EOF'
org.gradle.daemon=true
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g
EOF
  echo "Done."
fi

# ── STEP 6 — Create weekly auto-clean script ──────
echo ""
echo "[6/7] Creating weekly auto-clean script..."
cat > ~/android_cleanup.sh << 'CLEANEOF'
#!/bin/bash
BASE="$HOME/SUDARSHAN_CODE/sudarshan_repos"
echo "=== Cleanup: $(date) ==="
echo "Before:"; du -sh "$BASE" ~/.gradle

find "$BASE" -name ".gradle" -type d -prune -exec rm -rf {} + 2>/dev/null

find "$BASE" -path "*/build" -type d | while read builddir; do
  find "$builddir" -mindepth 1 -maxdepth 1 -type d \
    ! -name "outputs" -exec rm -rf {} + 2>/dev/null
  if [ -d "$builddir/outputs" ]; then
    find "$builddir/outputs" -mindepth 1 -maxdepth 1 -type d \
      ! -name "apk" ! -name "bundle" -exec rm -rf {} + 2>/dev/null
  fi
done

find ~/.gradle/caches -maxdepth 1 -type d -mtime +30 -exec rm -rf {} + 2>/dev/null
rm -rf ~/Library/Caches/Google/AndroidStudio*/ 2>/dev/null

echo "After:"; du -sh "$BASE" ~/.gradle
echo "Done!"
CLEANEOF
chmod +x ~/android_cleanup.sh
(crontab -l 2>/dev/null; echo "0 9 * * 0 /bin/bash ~/android_cleanup.sh >> ~/android_cleanup.log 2>&1") | crontab -
echo "Done. Scheduled every Sunday at 9am."

# ── STEP 7 — Run cleanup now ───────────────────────
echo ""
echo "[7/7] Running cleanup now..."
echo ""
echo "Before:"; du -sh "$BASE" ~/.gradle
echo ""

bash ~/android_cleanup.sh

echo ""
echo "================================================"
echo "  All done! Check sizes above."
echo "  Weekly cleanup scheduled every Sunday 9am."
echo "  Log: ~/android_cleanup.log"
echo "================================================"
