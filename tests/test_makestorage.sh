#!/usr/bin/env bash
#
# Unit tests for makestorage + install.sh. No dependencies: plain bash.
#
#   bash tests/test_makestorage.sh                 # run everything
#   MAKESTORAGE=/path/to/copy bash tests/test_makestorage.sh   # run against another copy
#
# Safety: every test runs with HOME / XDG_CONFIG_HOME pointing into a throwaway
# temp dir, a fake `launchctl` first on PATH, and (for safe_rm) a recording `rm`.
# Nothing here touches the real home dir, launchd, or the network.
#
# known_fail tests document real defects: they must FAIL today. If one starts
# passing the run reports it, so the marker gets removed when the bug is fixed.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${MAKESTORAGE:-$REPO/makestorage}"
INSTALLER="$REPO/install.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/makestorage-tests.XXXXXX")" || exit 2
case "$WORK" in /tmp/*|/var/*|/private/*) ;; *) echo "refusing odd temp dir: $WORK"; exit 2;; esac
trap 'rm -rf -- "$WORK"' EXIT

# Hermetic git: ignore the user's global/system config (hooks, signing, identity).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

OLD=200001010000   # touch -t stamp: ~9800 days old, older than any sane threshold
ESC=$'\033'

# ── assertion helpers (each exits the per-test subshell on failure) ──
fail()            { printf '    ASSERT FAILED: %s\n' "$*"; exit 1; }
assert_eq()       { [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$2] got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "output missing [$2]"; printf '%s\n' "$1";; esac; }
assert_lacks()    { case "$1" in *"$2"*) fail "output unexpectedly has [$2]";; esac; }
assert_exists()   { [ -e "$1" ] || fail "should exist: ${1#"$T"/}"; }
assert_gone()     { [ ! -e "$1" ] || fail "should be deleted: ${1#"$T"/}"; }

# ── per-test environment ──
# run_ms ARGS...  -> sets OUT (stdout+stderr, ANSI stripped) and RC. stdin = $STDIN or empty.
STDIN=""
run_ms() {
  OUT="$(printf '%s' "$STDIN" | HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" \
        PATH="$T/bin:$PATH" bash "$SCRIPT" "$@" 2>&1 | sed "s/${ESC}\\[[0-9;]*m//g"; \
        exit "${PIPESTATUS[1]}")"
  RC=$?
}

# git fixture helper: mkrepo DIR [YYYY-MM-DD]  (commits one file, optionally back-dated)
mkrepo() {
  local d="$1" when="${2:-}"
  mkdir -p "$d"
  ( cd "$d" && git init -q . && echo x > seed.txt && git add seed.txt
    if [ -n "$when" ]; then export GIT_AUTHOR_DATE="$when 12:00:00 +0000" GIT_COMMITTER_DATE="$when 12:00:00 +0000"; fi
    git -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -q -m seed )
}

setup_env() {
  T="$WORK/$1"
  mkdir -p "$T/home" "$T/bin"
  # fake launchctl: records args, exit code controlled by $T/launchctl.fail_on
  cat > "$T/bin/launchctl" <<EOF
#!/bin/sh
echo "\$@" >> "$T/launchctl.log"
[ "\$1" = "\$(cat "$T/launchctl.fail_on" 2>/dev/null)" ] && exit 1
exit 0
EOF
  chmod +x "$T/bin/launchctl"
  export T
}

# ═══════════════ arg parsing / help ═══════════════
t_no_args_prints_help() {
  run_ms
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "makestorage v1.0.0"
  assert_contains "$OUT" "Commands"
}
t_help_command_exits_zero() {
  run_ms help
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "--dry-run"
}
t_help_flag_after_command_prints_usage_and_does_not_clean() {
  mkdir -p "$T/proj/.gradle"
  run_ms clean --help --root "$T/proj"
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "Commands"
  assert_exists "$T/proj/.gradle"
}
t_unknown_command_prints_usage_and_exits_1() {
  run_ms bogus
  assert_eq "$RC" 1 "exit code"
  assert_contains "$OUT" "Commands"
}
t_unknown_option_exits_1_and_deletes_nothing() {
  mkdir -p "$T/proj/.gradle"
  run_ms clean --yes --root "$T/proj" --nope
  assert_eq "$RC" 1 "exit code"
  assert_contains "$OUT" "unknown option: --nope"
  assert_exists "$T/proj/.gradle"
}
t_root_flag_without_value_exits_1() {
  run_ms status --root
  assert_eq "$RC" 1 "exit code"
  assert_contains "$OUT" "--root needs a PATH"
}

# ═══════════════ human() and safe_rm() (sourced, main stripped) ═══════════════
load_functions() {
  export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config"
  # main() runs on source, so drop the trailing `main "$@"` call. File, not <(...): bash 3.2 can't source a pipe.
  sed '/^main "\$@"$/d' "$SCRIPT" > "$T/functions.sh"
  # shellcheck disable=SC1090,SC1091
  source "$T/functions.sh"
  type human >/dev/null 2>&1 && type safe_rm >/dev/null 2>&1 || fail "could not load makestorage functions"
}
t_human_formats_kb_boundaries() {
  load_functions
  assert_eq "$(human 0)" "0K"
  assert_eq "$(human)" "0K" "empty arg"
  assert_eq "$(human 1023)" "1023K"
  assert_eq "$(human 1024)" "1.0M"
  assert_eq "$(human 1536)" "1.5M"
  assert_eq "$(human 1048575)" "1024.0M"
  assert_eq "$(human 1048576)" "1.0G"
  assert_eq "$(human 5242880)" "5.0G"
}
t_safe_rm_refuses_protected_paths() {
  load_functions
  rm() { echo "rm $*" >> "$T/rm.log"; }     # recorder: a regression must not delete anything
  local p
  for p in "" "/" "$HOME" "$HOME/" "$HOME/.gradle" "$HOME/Library"; do
    safe_rm "$p" 2>/dev/null && fail "safe_rm accepted protected path [$p]"
  done
  [ ! -s "$T/rm.log" ] || fail "rm was invoked: $(cat "$T/rm.log")"
}
t_safe_rm_deletes_normal_path() {
  load_functions
  mkdir -p "$T/victim/sub"; touch "$T/victim/sub/f"
  safe_rm "$T/victim" || fail "returned non-zero"
  assert_gone "$T/victim"
}
t_safe_rm_handles_dash_leading_names() {
  load_functions
  mkdir -p "$T/work"; ( cd "$T/work" && mkdir -- "-rf" && touch -- "-rf/f" && safe_rm "-rf" )
  assert_gone "$T/work/-rf"
}

# ═══════════════ config ═══════════════
t_config_creates_file_with_defaults_then_reuses_it() {
  run_ms config
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "Created config:"
  local cfg="$T/home/.config/makestorage/config"
  assert_exists "$cfg"
  assert_contains "$(cat "$cfg")" "CACHE_DAYS=30"
  assert_contains "$(cat "$cfg")" "NODE_IDLE_DAYS=7"
  echo "CACHE_DAYS=99" > "$cfg"
  run_ms config
  assert_contains "$OUT" "Config: $cfg"
  assert_eq "$(cat "$cfg")" "CACHE_DAYS=99" "existing config must not be overwritten"
}
t_config_roots_are_used_and_cli_root_overrides_them() {
  mkdir -p "$T/home/.config/makestorage" "$T/fromcfg" "$T/fromcli"
  echo "ROOTS=(\"$T/fromcfg\")" > "$T/home/.config/makestorage/config"
  run_ms status
  assert_contains "$OUT" "roots: $T/fromcfg"
  run_ms status --root "$T/fromcli"
  assert_contains "$OUT" "roots: $T/fromcli"
  assert_lacks "$OUT" "$T/fromcfg"
}
t_no_roots_defaults_to_current_directory() {
  mkdir -p "$T/cwd/.gradle"
  OUT="$(cd "$T/cwd" && HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" PATH="$T/bin:$PATH" \
        bash "$SCRIPT" status </dev/null 2>&1)"
  assert_contains "$OUT" "$(cd "$T/cwd" && pwd)"
  assert_contains "$OUT" "/cwd/.gradle"
}
t_missing_root_warns_but_continues() {
  run_ms status --root "$T/does-not-exist"
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "warning: root does not exist: $T/does-not-exist"
  assert_contains "$OUT" "Total reclaimable: 0K"
}

# ═══════════════ status / dry-run never delete ═══════════════
t_status_lists_but_keeps_everything() {
  mkdir -p "$T/proj/app/.gradle" "$T/proj/app/build/intermediates"
  echo data > "$T/proj/app/.gradle/f"
  run_ms status --root "$T/proj"
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "would remove"
  assert_contains "$OUT" "$T/proj/app/.gradle"
  assert_contains "$OUT" "$T/proj/app/build/intermediates"
  assert_exists "$T/proj/app/.gradle/f"
  assert_exists "$T/proj/app/build/intermediates"
}
t_stats_is_alias_of_status() {
  run_ms stats --root "$T/empty"
  assert_contains "$OUT" "reclaimable space"
}
t_clean_dry_run_keeps_files_and_skips_gradle_props() {
  mkdir -p "$T/proj/.gradle"
  run_ms clean --dry-run --root "$T/proj"
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "Dry run — nothing deleted"
  assert_exists "$T/proj/.gradle"
  assert_gone "$T/home/.gradle/gradle.properties"
}
t_empty_root_reports_nothing_to_clean() {
  mkdir -p "$T/proj"
  run_ms status --root "$T/proj"
  assert_contains "$OUT" "nothing to clean"
  assert_contains "$OUT" "Total reclaimable: 0K"
}

# ═══════════════ clean --yes: each category ═══════════════
t_clean_removes_project_gradle_dirs() {
  mkdir -p "$T/proj/a/.gradle/x" "$T/proj/b/.gradle"
  run_ms clean --yes --root "$T/proj"
  assert_gone "$T/proj/a/.gradle"
  assert_gone "$T/proj/b/.gradle"
  assert_exists "$T/proj/a"
}
t_clean_build_dirs_preserve_apk_and_bundle() {
  local b="$T/proj/app/build"
  mkdir -p "$b/intermediates" "$b/outputs/apk/debug" "$b/outputs/bundle/release" "$b/outputs/logs" "$b/tmp"
  echo a > "$b/outputs/apk/debug/app.apk"; echo b > "$b/outputs/bundle/release/app.aab"
  echo keep > "$b/top-level-file.txt"
  run_ms clean --yes --root "$T/proj"
  assert_gone "$b/intermediates"
  assert_gone "$b/tmp"
  assert_gone "$b/outputs/logs"
  assert_exists "$b/outputs/apk/debug/app.apk"
  assert_exists "$b/outputs/bundle/release/app.aab"
  assert_exists "$b/top-level-file.txt"
}
t_clean_never_touches_build_dir_with_git_tracked_files() {
  mkrepo "$T/repo"
  mkdir -p "$T/repo/src/build/generated" "$T/repo/app/build/junk"
  echo src > "$T/repo/src/build/generated/a.txt"
  ( cd "$T/repo" && git add src/build/generated/a.txt \
    && git -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -q -m track )
  run_ms clean --yes --root "$T/repo"
  assert_exists "$T/repo/src/build/generated/a.txt"
  assert_gone "$T/repo/app/build/junk"
}
t_clean_removes_only_old_gradle_cache_dirs() {
  local c="$T/home/.gradle/caches"
  mkdir -p "$c/old" "$c/fresh"; touch -t $OLD "$c/old"
  run_ms clean --yes --root "$T/empty"
  assert_gone "$c/old"
  assert_exists "$c/fresh"
}
t_config_cache_days_changes_gradle_cache_threshold() {
  local c="$T/home/.gradle/caches"
  mkdir -p "$c/old" "$T/home/.config/makestorage"; touch -t $OLD "$c/old"
  echo "CACHE_DAYS=999999" > "$T/home/.config/makestorage/config"
  run_ms clean --yes --root "$T/empty"
  assert_exists "$c/old"
  assert_contains "$OUT" "Gradle caches (>999999d)"
}
t_clean_keeps_newest_gradle_wrapper_only() {
  local d="$T/home/.gradle/wrapper/dists"
  mkdir -p "$d/gradle-7.0" "$d/gradle-8.0" "$d/gradle-9.0"
  touch -t 200001010000 "$d/gradle-7.0"; touch -t 200101010000 "$d/gradle-8.0"; touch -t 200201010000 "$d/gradle-9.0"
  run_ms clean --yes --root "$T/empty"
  assert_gone "$d/gradle-7.0"
  assert_gone "$d/gradle-8.0"
  assert_exists "$d/gradle-9.0"
}
t_clean_removes_idle_node_modules_but_keeps_recent_repo() {
  mkrepo "$T/proj/idle" 2000-01-01
  mkrepo "$T/proj/active"
  mkdir -p "$T/proj/idle/node_modules/p" "$T/proj/active/node_modules/p"
  run_ms clean --yes --root "$T/proj"
  assert_gone "$T/proj/idle/node_modules"
  assert_exists "$T/proj/active/node_modules/p"
  assert_exists "$T/proj/idle/seed.txt"
}
t_config_node_idle_days_changes_threshold() {
  mkrepo "$T/proj/idle" 2000-01-01
  mkdir -p "$T/proj/idle/node_modules" "$T/home/.config/makestorage"
  echo "NODE_IDLE_DAYS=999999" > "$T/home/.config/makestorage/config"
  run_ms clean --yes --root "$T/proj"
  assert_exists "$T/proj/idle/node_modules"
}
t_clean_removes_android_studio_caches_and_logs() {
  mkdir -p "$T/home/Library/Caches/Google/AndroidStudio2024.1/x" "$T/home/Library/Logs/Google" "$T/home/Library/Caches/Other"
  run_ms clean --yes --root "$T/empty"
  assert_gone "$T/home/Library/Caches/Google/AndroidStudio2024.1"
  assert_gone "$T/home/Library/Logs/Google"
  assert_exists "$T/home/Library/Caches/Other"
}
t_clean_reports_freed_total_in_human_units() {
  mkdir -p "$T/proj/.gradle"; dd if=/dev/zero of="$T/proj/.gradle/big" bs=1024 count=2048 2>/dev/null
  run_ms clean --yes --root "$T/proj"
  assert_contains "$OUT" "Freed approximately 2."   # 2048K+dir overhead -> "2.0M"/"2.x M"
  assert_contains "$OUT" "M."
}
t_clean_with_stats_prints_log_path() {
  run_ms clean --yes --stats --root "$T/empty"
  assert_contains "$OUT" "log: $T/home/Library/Logs/makestorage.log"
}

# ═══════════════ gradle.properties ═══════════════
t_clean_writes_gradle_props_once() {
  run_ms clean --yes --root "$T/empty"
  local f="$T/home/.gradle/gradle.properties"
  assert_contains "$(cat "$f")" "org.gradle.daemon=true"
  assert_contains "$(cat "$f")" "org.gradle.caching=true"
  run_ms clean --yes --root "$T/empty"
  assert_eq "$(grep -c 'org.gradle.daemon' "$f")" 1 "duplicate append"
}
t_clean_leaves_existing_gradle_props_alone() {
  mkdir -p "$T/home/.gradle"; echo "org.gradle.daemon=false" > "$T/home/.gradle/gradle.properties"
  run_ms clean --yes --root "$T/empty"
  assert_eq "$(cat "$T/home/.gradle/gradle.properties")" "org.gradle.daemon=false"
}

# ═══════════════ confirmation prompt ═══════════════
t_clean_prompt_n_aborts_and_deletes_nothing() {
  mkdir -p "$T/proj/.gradle"
  STDIN=$'n\n'; run_ms clean --root "$T/proj"
  assert_eq "$RC" 1 "exit code"
  assert_contains "$OUT" "Aborted."
  assert_exists "$T/proj/.gradle"
  assert_gone "$T/home/.gradle/gradle.properties"
}
t_clean_prompt_eof_aborts() {
  mkdir -p "$T/proj/.gradle"
  STDIN=""; run_ms clean --root "$T/proj"
  assert_eq "$RC" 1 "exit code"
  assert_exists "$T/proj/.gradle"
}
t_clean_prompt_y_deletes() {
  mkdir -p "$T/proj/.gradle"
  STDIN=$'y\n'; run_ms clean --root "$T/proj"
  assert_contains "$OUT" "Delete the above"
  assert_gone "$T/proj/.gradle"
}
t_clean_prompt_other_answer_aborts() {
  mkdir -p "$T/proj/.gradle"
  STDIN="maybe"; run_ms clean --root "$T/proj"
  assert_eq "$RC" 1 "exit code"
  assert_exists "$T/proj/.gradle"
}

# ═══════════════ setup / uninstall (fake launchctl, temp HOME) ═══════════════
PLIST_REL="Library/LaunchAgents/com.sudarshantechlabs.makestorage.plist"
t_setup_writes_plist_and_loads_it() {
  mkdir -p "$T/proj"
  run_ms setup --root "$T/proj"
  assert_eq "$RC" 0 "exit code"
  local p="$T/home/$PLIST_REL"
  assert_exists "$p"
  assert_contains "$(cat "$p")" "<string>com.sudarshantechlabs.makestorage</string>"
  assert_contains "$(cat "$p")" "clean --yes --root \"$T/proj\""
  assert_contains "$(cat "$p")" "<key>Weekday</key><integer>0</integer>"
  assert_eq "$(cat "$T/launchctl.log")" "unload $p
load $p" "launchctl call sequence"
}
t_setup_warns_when_launchctl_load_fails() {
  echo load > "$T/launchctl.fail_on"
  run_ms setup --root "$T/proj"
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "launchctl load failed"
  assert_exists "$T/home/$PLIST_REL"
}
t_uninstall_removes_plist_and_unloads() {
  run_ms setup --root "$T/proj"
  : > "$T/launchctl.log"
  run_ms uninstall
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "Removed weekly cleanup job."
  assert_gone "$T/home/$PLIST_REL"
  assert_eq "$(cat "$T/launchctl.log")" "unload $T/home/$PLIST_REL"
}
t_uninstall_without_job_is_a_noop() {
  run_ms uninstall
  assert_eq "$RC" 0 "exit code"
  assert_contains "$OUT" "No launchd job installed."
  assert_gone "$T/launchctl.log"
}

# ═══════════════ safety: protected paths through the real CLI ═══════════════
t_clean_refuses_to_delete_home_gradle_even_when_home_is_a_root() {
  mkdir -p "$T/home/.gradle"; echo keep > "$T/home/.gradle/f"
  run_ms clean --yes --root "$T/home"
  assert_contains "$OUT" "REFUSING to delete protected path: $T/home/.gradle"
  assert_exists "$T/home/.gradle/f"
}

# ═══════════════ install.sh ═══════════════
run_installer() { # run_installer [ENV=VAL ...]
  OUT="$(env HOME="$T/home" PATH="/usr/bin:/bin" "$@" bash "$INSTALLER" 2>&1)"; RC=$?
}
t_installer_symlinks_into_home_local_bin() {
  run_installer
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(readlink "$T/home/.local/bin/makestorage")" "$REPO/makestorage"
  assert_contains "$OUT" "Installed: $T/home/.local/bin/makestorage"
  assert_contains "$OUT" "Add to PATH:"
}
t_installer_honours_prefix_and_is_idempotent() {
  run_installer PREFIX="$T/prefix"
  run_installer PREFIX="$T/prefix"
  assert_eq "$RC" 0 "second run exit code"
  assert_eq "$(readlink "$T/prefix/bin/makestorage")" "$REPO/makestorage"
}
t_installer_omits_path_hint_when_bin_already_on_path() {
  mkdir -p "$T/prefix/bin"
  run_installer PREFIX="$T/prefix" PATH="$T/prefix/bin:/usr/bin:/bin"
  assert_lacks "$OUT" "Add to PATH"
}

# ═══════════════ regressions for fixed defects ═══════════════
t_setup_plist_is_valid_xml() {
  # setup embedded `2>&1` raw inside <string>: bare & is invalid XML, so launchd cannot load the job.
  command -v plutil >/dev/null || fail "plutil unavailable"
  run_ms setup --root "$T/proj"
  plutil -lint "$T/home/$PLIST_REL" >/dev/null 2>&1 || fail "plist not valid XML"
}
t_clean_yes_exits_0_on_success() {
  # cmd_clean ended with `[ "$SHOW_STATS" -eq 1 ] && say ...`: rc=1 without --stats.
  mkdir -p "$T/proj/.gradle"
  run_ms clean --yes --root "$T/proj"
  assert_eq "$RC" 0 "exit code of a successful clean"
}
t_clean_counts_refused_protected_path_as_freed() {
  # run_category added kb to the total before safe_rm decided; a refused path was reported as freed.
  mkdir -p "$T/home/.gradle"; dd if=/dev/zero of="$T/home/.gradle/f" bs=1024 count=100 2>/dev/null
  run_ms clean --yes --root "$T/home"
  assert_lacks "$OUT" "freed: "
}
t_non_git_folder_node_modules_not_treated_as_idle() {
  # git log fails outside a repo: age must come from folder mtime (fresh here), so node_modules is kept.
  mkdir -p "$T/proj/scratch/node_modules/p"
  run_ms clean --yes --root "$T/proj"
  assert_exists "$T/proj/scratch/node_modules/p"
}

# ═══════════════ runner ═══════════════
pass=0; failed=0; known=0; unexpected=0
KNOWN_FAIL_RE='^t_KNOWN_'
for fn in $(declare -F | awk '{print $3}' | grep '^t_'); do
  setup_env "$fn"
  log="$WORK/$fn.log"
  ( set +e; "$fn" ) > "$log" 2>&1; rc=$?
  if [[ $fn =~ $KNOWN_FAIL_RE ]]; then
    if [ $rc -ne 0 ]; then known=$((known+1)); printf 'KNOWN-FAIL %s  <- %s\n' "$fn" "$(grep -m1 'ASSERT FAILED' "$log")"
    else unexpected=$((unexpected+1)); printf 'UNEXPECTED-PASS %s (defect fixed? drop the KNOWN marker)\n' "$fn"; fi
  elif [ $rc -eq 0 ]; then pass=$((pass+1)); printf 'ok    %s\n' "$fn"
  else failed=$((failed+1)); printf 'FAIL  %s\n' "$fn"; sed 's/^/      /' "$log" | head -40; fi
done
printf '\n%d passed, %d failed, %d known-defect(s) still failing, %d unexpected pass(es)\n' \
  "$pass" "$failed" "$known" "$unexpected"
[ "$pass" -gt 0 ] && [ "$failed" -eq 0 ] && [ "$unexpected" -eq 0 ]
