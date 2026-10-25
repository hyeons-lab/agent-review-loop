#!/usr/bin/env bash
# Installer verification using a fake HOME. Never touches the real home.
set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS="agent-review-loop agent-review-report agent-review-pr-comments agent-review-check-ci"
MIRROR_START='# Mirror: 8 run-root bootstraps'
MIRROR_END='Mirror end'
cleanup() {
  local exit_code=$?
  local f="${fail:-0}" ld="${LOG_DIR:-unknown}" td="${TEST_DIR:-}"
  if [ "${exit_code}" -ne 0 ] || [ "$f" -gt 0 ]; then
    echo "Verification failed (exit code ${exit_code}, ${f} failure(s)). Retaining diagnostic logs in: ${ld}"
  elif [ -n "$td" ]; then
    rm -rf "$td"
  fi
}
regen_cleanup() {
  if [ -n "${TEST_DIR:-}" ]; then rm -rf "${TEST_DIR}"; fi
  if [ -n "${tmpd:-}" ]; then rm -rf "${tmpd:-}"; fi
  if [ -n "${tmpg:-}" ]; then rm -f "${tmpg:-}"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'exit 131' QUIT
span_end() { # span_end <start_line> <file>: bounded end-anchor search; prints "" when anchorless
  awk -v s="$1" -v e="$MIRROR_END" -v m="$MIRROR_START" 'NR>s && ($0 ~ m){f=1; exit} NR>s && !f && $0 ~ e {print NR; exit}' "$2"
}
hb_escape() { # hb_escape <path>: quote-escape then sed-replacement-escape for '...'-context splices
  printf '%s' "$1" | sed "s/'/'\\\\''/g" | sed 's/[&|\\]/\\&/g'
}
if [ "${1:-}" = "--regen-golden" ]; then
  # Regen manages its own scratch and errors; silence the verify trap.
  # Pre-init scratch vars so regen_cleanup stays set -u safe on signals.
  # Regen dispatches before TEST_DIR exists, so a signal can never land
  # between scratch creation and this trap (no retain-on-failure window).
  tmpd=""; tmpg=""; TEST_DIR=""
  trap regen_cleanup EXIT
  # Refuse to re-baseline divergent or anchorless spans: fix drift first.
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/arl-regen.XXXXXX")" || { echo "ERROR: cannot create regen scratch" >&2; exit 1; }
  n=0; st1=""; en1=""
  for s in ${SKILLS}; do
    starts=$(grep -n "$MIRROR_START" "${BUNDLE}/skills/$s/SKILL.md" | cut -d: -f1) || true
    for stx in $starts; do
      n=$((n+1))
      enx=$(span_end "$stx" "${BUNDLE}/skills/$s/SKILL.md")
      [ -n "$enx" ] || { echo "ERROR: missing end anchor after line $stx in $s; fix drift first" >&2; rm -rf "$tmpd"; exit 1; }
      if [ "$n" -eq 1 ]; then st1="$stx"; en1="$enx"; fi
      sed -n "${stx},${enx}p" "${BUNDLE}/skills/$s/SKILL.md" | sed -f "${BUNDLE}/tests/fixtures/normalize.sed" > "$tmpd/span-$n.txt" || { echo "ERROR: span extraction failed for $s@$stx" >&2; rm -rf "$tmpd"; exit 1; }
      if [ "$n" -gt 1 ]; then
        cmp -s "$tmpd/span-1.txt" "$tmpd/span-$n.txt" || { echo "ERROR: span $n ($s@$stx) diverges; fix drift first" >&2; rm -rf "$tmpd"; exit 1; }
      fi
    done
  done
  [ "$n" -eq 8 ] || { echo "ERROR: expected 8 spans, found $n; fix drift first" >&2; rm -rf "$tmpd"; exit 1; }
  tmpg="$(mktemp "${BUNDLE}/tests/fixtures/.golden.XXXXXX")" || { echo "ERROR: cannot create golden temp" >&2; rm -rf "$tmpd"; exit 1; }
  cp "$tmpd/span-1.txt" "$tmpg" || { echo "ERROR: cannot stage golden temp" >&2; rm -f "$tmpg"; rm -rf "$tmpd"; exit 1; }
  chmod 644 "$tmpg" || { echo "ERROR: cannot set golden temp mode" >&2; rm -f "$tmpg"; rm -rf "$tmpd"; exit 1; }
  if [ ! -e "${BUNDLE}/tests/fixtures/bootstrap-golden.txt" ]; then
    echo "(new golden)"
  elif cmp -s "${BUNDLE}/tests/fixtures/bootstrap-golden.txt" "$tmpg" 2>/dev/null; then
    echo "(no changes)"
  else
    echo "--- golden diff (old -> new):"
    diff -u "${BUNDLE}/tests/fixtures/bootstrap-golden.txt" "$tmpg" || true
  fi
  mv "$tmpg" "${BUNDLE}/tests/fixtures/bootstrap-golden.txt" || { echo "ERROR: cannot write golden" >&2; rm -f "$tmpg"; rm -rf "$tmpd"; exit 1; }
  rm -rf "$tmpd"
  echo "regenerated tests/fixtures/bootstrap-golden.txt from span 1 (${st1}..${en1})"
  exit 0
fi
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arl-verify-XXXXXX")"
FAKE="${TEST_DIR}/home"
LOG_DIR="${TEST_DIR}/logs"
mkdir -p "${FAKE}" "${LOG_DIR}"
export HOME="${FAKE}"
export XDG_CONFIG_HOME="${FAKE}/.config"
pass=0; fail=0; stream_n=0



check() { # check <desc> <command...>
  local desc="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    echo "PASS: ${desc}"
    pass=$((pass+1))
  else
    echo "FAIL: ${desc}"
    if [ -n "${out}" ]; then
      printf '%s\n' "${out}" | sed 's/^/  /' >&2
    fi
    fail=$((fail+1))
  fi
}
check_streams() { # check_streams <desc> <want_rc> <err_pattern> <cmd...>: asserts rc, empty stdout, stderr match
  local desc="$1" want_rc="$2" err_pat="$3"; shift 3
  stream_n=$((stream_n+1))
  local out="${LOG_DIR}/streams-${stream_n}.out" err="${LOG_DIR}/streams-${stream_n}.err" rc=0
  "$@" >"$out" 2>"$err" || rc=$?
  if [ "$rc" = "$want_rc" ] && [ ! -s "$out" ] && grep -q "$err_pat" "$err"; then
    echo "PASS: ${desc}"
    pass=$((pass+1))
  else
    echo "FAIL: ${desc} (rc=${rc}, want ${want_rc})"
    sed 's/^/  out: /' "$out" >&2
    sed 's/^/  err: /' "$err" >&2
    fail=$((fail+1))
  fi
}
run_split() { # run_split <tag> <cmd...>: runs cmd, stores rc/out/err under LOG_DIR/split-<tag>.*
  local tag="$1"; shift
  rm -f "${LOG_DIR}/split-${tag}.rc"
  "$@" >"${LOG_DIR}/split-${tag}.out" 2>"${LOG_DIR}/split-${tag}.err" || echo "$?" >"${LOG_DIR}/split-${tag}.rc"
  [ -f "${LOG_DIR}/split-${tag}.rc" ] || echo "0" >"${LOG_DIR}/split-${tag}.rc"
}

run_install() { # run_install <logfile> [args...]
  local log="$1"; shift
  if ! "${BUNDLE}/install.sh" "$@" > "${log}" 2>&1; then
    cat "${log}" >&2
    return 1
  fi
}
is_missing() { # is_missing <path>: true when path does not exist and is not a dangling symlink
  [ ! -e "$1" ] && [ ! -L "$1" ]
}
fresh_fake() { # reset the fake home between sections
  rm -rf "${FAKE}"
  mkdir -p "${FAKE}"
}

echo "--- 0. syntax ---"
check "bash -n install.sh" bash -n "${BUNDLE}/install.sh"
check "bash -n verify-install.sh" bash -n "${BUNDLE}/tests/verify-install.sh"
if command -v shellcheck >/dev/null; then
  if shellcheck -S warning "${BUNDLE}/install.sh" "${BUNDLE}/tests/verify-install.sh"; then
    echo "PASS: shellcheck"
    pass=$((pass+1))
  else
    echo "FAIL: shellcheck reported warnings or errors"
    fail=$((fail+1))
  fi
else
  echo "SKIP: shellcheck not available"
  pass=$((pass+1))
fi

echo "--- 1. fresh full install ---"
check "fresh full install" run_install "${LOG_DIR}/rfl-run1.log"
cat "${LOG_DIR}/rfl-run1.log"
for d in .agents/skills .config/muse/skills .claude/skills .codex/skills .gemini/config/skills; do
  for s in ${SKILLS}; do
    check "skill installed: $d/$s" test -f "${FAKE}/$d/$s/SKILL.md"
    check "openai.yaml installed: $d/$s" test -f "${FAKE}/$d/$s/agents/openai.yaml"
  done
  check "pillars installed: $d" test -f "${FAKE}/$d/agent-review-loop/thematic-review-pillars.md"
done
check "refinements seeded" test -f "${FAKE}/.agents/review-refinements.md"
check "seed has 8 pillars" test "$(grep -c '^### Pillar' "${FAKE}/.agents/review-refinements.md")" = "8"
check "installed files readable by non-owner" test -z "$(find "${FAKE}" -type f ! -perm -0444)"

echo "--- 2. re-run is fully unchanged ---"
check "re-run full install" run_install "${LOG_DIR}/rfl-run2.log"
if grep -qE "installed:|updated:|FAILED" "${LOG_DIR}/rfl-run2.log" || ! grep -q "unchanged" "${LOG_DIR}/rfl-run2.log"; then
  echo "FAIL: second run changed something:"; grep -E "installed:|updated:|FAILED" "${LOG_DIR}/rfl-run2.log"; fail=$((fail+1))
else
  echo "PASS: second run changed nothing"; pass=$((pass+1))
fi
check "all 45 files unchanged" test "$(grep -c "unchanged:" "${LOG_DIR}/rfl-run2.log")" = "45"

echo "--- 3. learnings preserved across reinstall ---"
echo "- **Marker**: test bullet" >> "${FAKE}/.agents/review-refinements.md"
check "reinstall with marker" run_install "${LOG_DIR}/rfl-run3.log"
check "marker survives" grep -q "Marker" "${FAKE}/.agents/review-refinements.md"
check "run3 reports kept" grep -q "kept existing" "${LOG_DIR}/rfl-run3.log"

echo "--- 4. legacy file untouched, canonical seeded alongside ---"
rm -rf "${FAKE}/.agents/review-refinements.md"
mkdir -p "${FAKE}/.gemini"
echo "### Pillar 1: legacy" > "${FAKE}/.gemini/review-refinements.md"
check "install with legacy file present" run_install "${LOG_DIR}/rfl-run4.log"
check "legacy untouched" test "$(< "${FAKE}/.gemini/review-refinements.md")" = "### Pillar 1: legacy"
check "canonical seeded" grep -q "Shared Review Refinements" "${FAKE}/.agents/review-refinements.md"
check "legacy note printed" grep -q "legacy" "${LOG_DIR}/rfl-run4.log"
check "legacy opt-in mentioned" grep -q "REVIEW_REFINEMENTS_LEGACY=1" "${LOG_DIR}/rfl-run4.log"

echo "--- 5. selective install ---"
fresh_fake
check "selective install" run_install "${LOG_DIR}/rfl-run5.log" --claude --no-refinements
for s in ${SKILLS}; do
  check "selective install present: $s" test -f "${FAKE}/.claude/skills/$s/SKILL.md"
  check "selective install absent: $s" test ! -e "${FAKE}/.codex/skills/$s"
done
check "refinements skipped" test ! -e "${FAKE}/.agents/review-refinements.md"

echo "--- 6. link mode + converge ---"
fresh_fake
check "initial link install" run_install "${LOG_DIR}/rfl-run6.log" --link
for s in ${SKILLS}; do
  check "canonical is real dir: $s" test -f "${FAKE}/.agents/skills/$s/SKILL.md"
  check "claude is symlink: $s" test -L "${FAKE}/.claude/skills/$s"
  check "link points at canonical: $s" test "$(readlink "${FAKE}/.claude/skills/$s")" = "${FAKE}/.agents/skills/$s"
done
check "link re-run" run_install "${LOG_DIR}/rfl-run6b.log" --link
check "link re-run unchanged" grep -q "unchanged" "${LOG_DIR}/rfl-run6b.log"
check "link re-run no mutations" test "$(grep -cE "installed:|updated:|linked:|FAILED" "${LOG_DIR}/rfl-run6b.log")" = "0"
check "copy mode replaces links" run_install "${LOG_DIR}/rfl-run6c.log"
for s in ${SKILLS}; do
  check "copy mode replaces links: $s" test ! -L "${FAKE}/.claude/skills/$s"
  check "copy mode file valid: $s" grep -qxF "name: $s" "${FAKE}/.claude/skills/$s/SKILL.md"
done

echo "--- 7. dry-run changes nothing ---"
fresh_fake
check "dry-run on empty home" run_install "${LOG_DIR}/rfl-run7a.log" --dry-run
check "dry-run empty home" test -z "$(ls -A "${FAKE}")"
check "dry-run plans all 45 file installs" test "$(grep -c "\[dry-run\] install " "${LOG_DIR}/rfl-run7a.log")" = "45"
check "baseline install for populated dry-run" run_install "${LOG_DIR}/rfl-run7b.log"
check "dry-run on populated install" run_install "${LOG_DIR}/rfl-run7c.log" --dry-run
check "populated dry-run reports unchanged" grep -q "unchanged" "${LOG_DIR}/rfl-run7c.log"
check "populated dry-run has no pending changes" test "$(grep -c "\[dry-run\]" "${LOG_DIR}/rfl-run7c.log")" = "0"

echo "--- 8. ASCII-only bundle prose ---"
ascii_rc=0
TAB="$(printf '\t')"
LC_ALL=C grep -r -e "[^ -~${TAB}]" "${BUNDLE}/skills" "${BUNDLE}/install.sh" "${BUNDLE}/tests" "${BUNDLE}/templates" "${BUNDLE}/README.md" >/dev/null 2>&1 || ascii_rc=$?
if [ "${ascii_rc}" -eq 0 ]; then
  echo "FAIL: non-ASCII byte found"
  LC_ALL=C grep -r -n -e "[^ -~${TAB}]" "${BUNDLE}/skills" "${BUNDLE}/install.sh" "${BUNDLE}/tests" "${BUNDLE}/templates" "${BUNDLE}/README.md"
  fail=$((fail+1))
elif [ "${ascii_rc}" -eq 1 ]; then
  echo "PASS: ASCII-only bundle"
  pass=$((pass+1))
else
  echo "FAIL: grep error checking for non-ASCII bytes (exit code ${ascii_rc})"
  fail=$((fail+1))
fi

for s in ${SKILLS}; do
  check "skill named in README: $s" grep -q -F "$s" "${BUNDLE}/README.md"
done

echo "--- 9. upgrade refreshes skills, keeps learnings, skips missing ---"
fresh_fake
check "initial install for upgrade" run_install "${LOG_DIR}/rfl-run9a.log" --claude
echo "- **Marker**: upgrade bullet" >> "${FAKE}/.agents/review-refinements.md"
cp "${FAKE}/.agents/review-refinements.md" "${LOG_DIR}/rfl-before.md"
for s in ${SKILLS}; do
  echo "stale" >> "${FAKE}/.claude/skills/$s/SKILL.md"
done
check "upgrade command" run_install "${LOG_DIR}/rfl-run9b.log" --upgrade
for s in ${SKILLS}; do
  check "upgrade refreshes stale skill: $s" cmp -s "${BUNDLE}/skills/$s/SKILL.md" "${FAKE}/.claude/skills/$s/SKILL.md"
  check "upgrade skips missing target: $s" test ! -e "${FAKE}/.codex/skills/$s"
done
check "upgrade leaves refinements byte-identical" cmp -s "${LOG_DIR}/rfl-before.md" "${FAKE}/.agents/review-refinements.md"
check "upgrade reports skip" grep -q "not installed, skipping" "${LOG_DIR}/rfl-run9b.log"
for s in ${SKILLS}; do
  check "upgrade never installs missing canonical: $s" test ! -e "${FAKE}/.agents/skills/$s"
done
check "upgrade leaves refinements alone" grep -q "left untouched" "${LOG_DIR}/rfl-run9b.log"
rm -rf "${FAKE}/.claude/skills/agent-review-pr-comments"
check "upgrade with skill removed" run_install "${LOG_DIR}/rfl-run9d.log" --upgrade --claude
check "upgrade adds no new skill" test ! -e "${FAKE}/.claude/skills/agent-review-pr-comments"
check "upgrade keeps loop skill" test -f "${FAKE}/.claude/skills/agent-review-loop/SKILL.md"
check "upgrade keeps report skill" test -f "${FAKE}/.claude/skills/agent-review-report/SKILL.md"
# Verify legacy skill migration under upgrade
mkdir -p "${FAKE}/.claude/skills/address-pr-comments/agents"
echo "stale legacy" > "${FAKE}/.claude/skills/address-pr-comments/SKILL.md"
echo "stale yaml" > "${FAKE}/.claude/skills/address-pr-comments/agents/openai.yaml"
check "upgrade legacy skill" run_install "${LOG_DIR}/rfl-run9-legacy.log" --upgrade --claude
check "legacy skill migrated to new name" test -f "${FAKE}/.claude/skills/agent-review-pr-comments/SKILL.md"
check "legacy skill updated to current content" cmp -s "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" "${FAKE}/.claude/skills/agent-review-pr-comments/SKILL.md"
check "legacy skill yaml updated to current content" cmp -s "${BUNDLE}/skills/agent-review-pr-comments/agents/openai.yaml" "${FAKE}/.claude/skills/agent-review-pr-comments/agents/openai.yaml"
check "legacy skill old directory removed" is_missing "${FAKE}/.claude/skills/address-pr-comments"

# Verify legacy skill migration for symlink installs under upgrade
mkdir -p "${FAKE}/.agents/skills/agent-review-pr-comments/agents"
cp "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" "${FAKE}/.agents/skills/agent-review-pr-comments/"
cp "${BUNDLE}/skills/agent-review-pr-comments/agents/openai.yaml" "${FAKE}/.agents/skills/agent-review-pr-comments/agents/"
rm -rf "${FAKE}/.claude/skills/agent-review-pr-comments"
ln -s "${FAKE}/.agents/skills/address-pr-comments" "${FAKE}/.claude/skills/address-pr-comments"
check "upgrade legacy symlink skill" run_install "${LOG_DIR}/rfl-run9-legacy-symlink.log" --upgrade --claude
check "legacy symlink migrated to new canonical" test -L "${FAKE}/.claude/skills/agent-review-pr-comments"
check "legacy symlink points to new canonical" test "$(readlink "${FAKE}/.claude/skills/agent-review-pr-comments")" = "${FAKE}/.agents/skills/agent-review-pr-comments"
check "legacy symlink resolves to skill file" test -f "${FAKE}/.claude/skills/agent-review-pr-comments/SKILL.md"
check "legacy symlink resolves to yaml metadata" test -f "${FAKE}/.claude/skills/agent-review-pr-comments/agents/openai.yaml"
check "legacy symlink old link removed" is_missing "${FAKE}/.claude/skills/address-pr-comments"

# Verify dry-run plans cleanup of obsolete legacy skill without modifying disk
mkdir -p "${FAKE}/.claude/skills/address-pr-comments"
echo "obsolete" > "${FAKE}/.claude/skills/address-pr-comments/SKILL.md"
check "dry-run reports obsolete legacy skill cleanup" run_install "${LOG_DIR}/rfl-dry-run-cleanup.log" --dry-run --claude
check "dry-run plans obsolete skill removal" grep -q -F -- "clean up obsolete skill: ${FAKE}/.claude/skills/address-pr-comments" "${LOG_DIR}/rfl-dry-run-cleanup.log"
check "dry-run leaves obsolete legacy skill untouched" test "$(< "${FAKE}/.claude/skills/address-pr-comments/SKILL.md")" = "obsolete"

# Verify dry-run plans migration of legacy skill under upgrade without modifying disk
rm -rf "${FAKE}/.claude/skills/agent-review-pr-comments"
check "dry-run reports legacy skill migration under upgrade" run_install "${LOG_DIR}/rfl-dry-run-upgrade.log" --dry-run --upgrade --claude
check "dry-run plans legacy skill migration" grep -q -F -- "migrate legacy skill: ${FAKE}/.claude/skills/address-pr-comments -> ${FAKE}/.claude/skills/agent-review-pr-comments" "${LOG_DIR}/rfl-dry-run-upgrade.log"
check "dry-run upgrade leaves legacy skill untouched" test "$(< "${FAKE}/.claude/skills/address-pr-comments/SKILL.md")" = "obsolete"
check "dry-run upgrade leaves destination uncreated" is_missing "${FAKE}/.claude/skills/agent-review-pr-comments"

# Verify fresh install cleans up obsolete legacy skill
check "fresh install cleans up obsolete legacy skill" run_install "${LOG_DIR}/rfl-fresh-cleanup.log" --claude
check "obsolete legacy skill removed on fresh install" is_missing "${FAKE}/.claude/skills/address-pr-comments"
check "fresh install installs renamed skill" cmp -s "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" "${FAKE}/.claude/skills/agent-review-pr-comments/SKILL.md"
check "fresh install installs subordinate metadata" cmp -s "${BUNDLE}/skills/agent-review-pr-comments/agents/openai.yaml" "${FAKE}/.claude/skills/agent-review-pr-comments/agents/openai.yaml"
rm "${FAKE}/.agents/review-refinements.md"
check "upgrade without refinements file" run_install "${LOG_DIR}/rfl-run9c.log" --upgrade
check "upgrade never seeds refinements" test ! -e "${FAKE}/.agents/review-refinements.md"

echo "--- 10. upgrade respects linked installs ---"
fresh_fake
check "initial link install for upgrade" run_install "${LOG_DIR}/rfl-run10a.log" --link
for s in ${SKILLS}; do
  echo "stale" >> "${FAKE}/.agents/skills/$s/SKILL.md"
done
check "upgrade linked install" run_install "${LOG_DIR}/rfl-run10b.log" --upgrade
for s in ${SKILLS}; do
  check "upgrade refreshes canonical: $s" cmp -s "${BUNDLE}/skills/$s/SKILL.md" "${FAKE}/.agents/skills/$s/SKILL.md"
  check "upgrade leaves symlink: $s" test -L "${FAKE}/.claude/skills/$s"
  check "upgrade symlink resolves to refreshed content: $s" cmp -s "${BUNDLE}/skills/$s/SKILL.md" "${FAKE}/.claude/skills/$s/SKILL.md"
done
check "upgrade reports link kept" grep -q "leaving in place" "${LOG_DIR}/rfl-run10b.log"

echo "--- 11. upgrade ignores link flag ---"
fresh_fake
check "install claude for link-ignore test" run_install "${LOG_DIR}/rfl-run11a.log" --claude
check "upgrade claude" run_install "${LOG_DIR}/rfl-run11b.log" --upgrade --claude
fresh_fake
check "second install claude" run_install "${LOG_DIR}/rfl-run11d.log" --claude
check "upgrade with link flag" run_install "${LOG_DIR}/rfl-run11c.log" --upgrade --link --claude
check "upgrade ignores link note" grep -q "ignores --link" "${LOG_DIR}/rfl-run11c.log"
check "link flag changes nothing under upgrade" cmp -s "${LOG_DIR}/rfl-run11b.log" <(grep -v "ignores --link" "${LOG_DIR}/rfl-run11c.log")
check "upgrade covers canonical scope" grep -q ".agents/skills" "${LOG_DIR}/rfl-run11b.log"
for s in ${SKILLS}; do
  check "upgrade never installs missing canonical: $s" test ! -e "${FAKE}/.agents/skills/$s"
  check "upgrade adds no new targets: $s" test ! -e "${FAKE}/.codex/skills/$s"
  check "upgrade keeps copy type: $s" test ! -L "${FAKE}/.claude/skills/$s"
done

echo "--- 12. skill code blocks parse ---"
for s in ${SKILLS}; do
  block=0
  in_block=0
  while IFS= read -r line || [ -n "$line" ]; do
    stripped="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$stripped" in
      '```bash'*|'```sh'*)
        block=$((block+1))
        : > "${LOG_DIR}/snippet-${s}-${block}.sh"
        in_block=1
        ;;
      '```')
        in_block=0
        ;;
      *)
        if [ "$in_block" = "1" ]; then
          printf '%s\n' "$line" >> "${LOG_DIR}/snippet-${s}-${block}.sh"
        fi
        ;;
    esac
  done < "${BUNDLE}/skills/$s/SKILL.md"
  case "$s" in
    agent-review-loop) want_snippets=3;;
    agent-review-report) want_snippets=5;;
    agent-review-pr-comments) want_snippets=9;;
    agent-review-check-ci) want_snippets=10;;
  esac
  check "skill snippets pinned: $s" test "$block" -eq "$want_snippets"
done
for f in "${LOG_DIR}"/snippet-*.sh; do
  check "snippet parses: $(basename "$f" .sh)" bash -n "$f"
done

echo "--- 13. run-root bootstraps identical ---"
bootstrap_count=0
for s in ${SKILLS}; do
  case "$s" in
    agent-review-loop) want_bootstraps=2; forbid='agent-review-report|pr-comments|check-ci|PATTOP|PATPER|ROUNDS|REAPERR';;
    agent-review-report) want_bootstraps=4; forbid='agent-review-loop|pr-comments|check-ci|PATTOP|PATPER|ROUNDS|REAPERR';;
    agent-review-pr-comments) want_bootstraps=1; forbid='agent-review-loop|agent-review-report|check-ci|PATTOP|PATPER|ROUNDS|REAPERR';;
    agent-review-check-ci) want_bootstraps=1; forbid='agent-review-loop|agent-review-report|pr-comments|PATTOP|PATPER|ROUNDS|REAPERR';;
  esac
  starts=$(grep -n "$MIRROR_START" "${BUNDLE}/skills/$s/SKILL.md" | cut -d: -f1) || true
  check "bootstrap copies pinned: $s" test "$(printf '%s' "$starts" | wc -w)" -eq "$want_bootstraps"
  for st in $starts; do
    bootstrap_count=$((bootstrap_count+1))
    en=$(span_end "$st" "${BUNDLE}/skills/$s/SKILL.md")
    if [ -z "$en" ]; then check "bootstrap end anchor present after line $st in $s" false; en=$st; fi
    sed -n "${st},${en}p" "${BUNDLE}/skills/$s/SKILL.md" > "${LOG_DIR}/bootstrap-${bootstrap_count}.raw.txt"
    check "bootstrap own skill only: $s@$st" test "$(grep -c -E -e "$forbid" "${LOG_DIR}/bootstrap-${bootstrap_count}.raw.txt")" = "0"
    sed -f "${BUNDLE}/tests/fixtures/normalize.sed" "${LOG_DIR}/bootstrap-${bootstrap_count}.raw.txt" > "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap reaps top level: $s@$st" grep -q 'reaping stale run path' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap reaps archive: $s@$st" grep -q 'reaping stale run archive' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap unsets git env: $s@$st" grep -q -F 'unset GIT_DIR GIT_WORK_TREE' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap unsets diff env: $s@$st" grep -q -F 'GIT_EXTERNAL_DIFF GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap clears env config: $s@$st" grep -q -F 'unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap caps hygiene loop: $s@$st" grep -q -F '[ "$cfg_i" -lt 128 ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap quiets hygiene compare: $s@$st" grep -q -F '[ "$cfg_i" -lt "$cfg_n" ] 2>/dev/null' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap gates toplevel ownership: $s@$st" grep -q -F '&& [ -O "$toplevel" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap gates toplevel writable: $s@$st" grep -q -F '[ -w "$toplevel" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap notices unusable toplevel: $s@$st" grep -q -F 'unusable (unwritable or foreign-owned); using per-user TMPDIR fallback' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap clears toplevel in fallback: $s@$st" test "$(grep -c -F 'toplevel=""' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap resolves tmpbase: $s@$st" grep -q -F 'cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap strips tmpbase slash: $s@$st" grep -q -F 'tmpbase="${tmpbase%/}"' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap defaults tmpbase: $s@$st" grep -q -F '|| tmpbase=""' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap keeps root tmpbase: $s@$st" grep -q -F '[ "$tmpbase" = "/" ] || tmpbase=' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap requires absolute tmpdir: $s@$st" test "$(grep -c -F 'is not absolute; refusing' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap absolute-pattern shape: $s@$st" test "$(grep -c -F 'in /*)' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap guards tmpbase nonempty: $s@$st" test "$(grep -c -F '[ -n "$tmpbase" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap guards tmpbase length: $s@$st" test "$(grep -c -F 'shorten TMPDIR or unset it' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap numeric id fallback: $s@$st" test "$(grep -c -F 'id -un 2>/dev/null || id -u 2>/dev/null' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap run-root fallthrough: $s@$st" grep -q -F 'using per-user fallback (before restoring repo-local runs' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap quotes residue remedy: $s@$st" grep -q -F 'sudo rm -rf '"'"'$root_base_safe'"'" "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap escapes remedy path: $s@$st" grep -q -F 'root_base_safe="$(printf' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap quotes remedy ls: $s@$st" grep -q -F 'ls '"'"'$root_base_safe'"'" "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap no unquoted residue remedy: $s@$st" test -z "$(grep -F 'sudo rm -rf $root_base' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt" || true)"
    check "bootstrap fallthrough tests ownership op: $s@$st" grep -q -F '[ ! -O "$root_base/.agent-tmp" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap refuses fallback link: $s@$st" grep -q -F 'fallback parent $root_base is a symlink; refusing' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap creates fallback parent: $s@$st" grep -q -F 'cannot create fallback parent' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap atomic fallback mkdir: $s@$st" test "$(grep -c -F 'mkdir -m 700 "$root_base"' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap owns fallback: $s@$st" grep -q -F 'fallback parent $root_base not owned by effective user; refusing' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap owns fallback op: $s@$st" test "$(grep -c -F '[ -O "$root_base" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap secures fallback: $s@$st" grep -q -F 'cannot secure fallback parent' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap owns before chmod: $s@$st" test "$(grep -n -F '[ -O "$root_base" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F 'chmod 700 "$root_base"' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt" | cut -d: -f1 | head -n 1)"
    check "bootstrap re-asserts fallback: $s@$st" grep -q -F 'fallback parent $root_base changed under us; refusing' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap fallback link checked sixfold: $s@$st" test "$(grep -c -F '[ ! -L "$root_base" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "6"
    check "bootstrap pre-chmod order: $s@$st" awk '/fallback parent \$root_base changed under us/{prev=NR} /chmod 700 "\$root_base"/{if (NR==prev+1) ok++} END{exit (ok==2)?0:1}' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap refuses run-root link: $s@$st" grep -q -F 'run root $root_base/.agent-tmp is a symlink; refusing' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap creates run root: $s@$st" grep -q -F 'cannot create run root' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap atomic run-root mkdir: $s@$st" grep -q -F 'mkdir -m 700 "$run_root"' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap owns run root: $s@$st" grep -q -F 'run root $run_root not owned by effective user; refusing' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap owns run root op: $s@$st" grep -q -F '[ -O "$run_root" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap re-asserts run root: $s@$st" grep -q -F 'run root $run_root changed under us; refusing' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap run-root link checked twice: $s@$st" test "$(grep -c -F '[ ! -L "$run_root" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap run-root pre-chmod order: $s@$st" awk '/run root \$run_root changed under us/{prev=NR} /chmod 700 "\$run_root"/{if (NR==prev+1) ok++} END{exit (ok==1)?0:1}' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap gates reaper shell: $s@$st" grep -q -F 'BASH_VERSION:-}${ZSH_VERSION:-}' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap warns reaping skip: $s@$st" grep -q -F 'WARNING: skipping 7-day reaping' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap captures reaper scan errors: $s@$st" test "$(grep -c -F 'reap_err="' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap checks find status: $s@$st" test "$(grep -c -F 'if ! fresh="' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap treats scan errors as fresh: $s@$st" test "$(grep -c -F '[ -n "$fresh" ] || [ -s "$reap_err" ]' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap warns mktemp failure: $s@$st" test "$(grep -c -F 'WARNING: cannot vet stale entry' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt")" = "2"
    check "bootstrap skips rounds dir: $s@$st" grep -q -F "! \\( -name 'ROUNDS' -type d \\)" "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap reaps top level to stderr: $s@$st" grep -q -F 'echo "reaping stale run path: $p" >&2' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
    check "bootstrap reaps archive to stderr: $s@$st" grep -q -F 'echo "reaping stale run archive: $p" >&2' "${LOG_DIR}/bootstrap-${bootstrap_count}.txt"
  done
done
check "eight bootstraps extracted" test "$bootstrap_count" -eq 8
i=2
while [ "$i" -le "$bootstrap_count" ]; do
  check "bootstrap matches: bootstrap-$i" cmp "${LOG_DIR}/bootstrap-1.txt" "${LOG_DIR}/bootstrap-$i.txt"
  i=$((i+1))
done
# Golden: drift equality ties every span to span 1, but uniform change passes
# all spans at once; pin span 1 content so uniform loss or substitution fails.
# Regenerate deliberately after an intended mirror change with:
#   ./tests/verify-install.sh --regen-golden
check "bootstrap golden unchanged" cmp "${BUNDLE}/tests/fixtures/bootstrap-golden.txt" "${LOG_DIR}/bootstrap-1.txt"

echo "--- 13b. static pins: echo contracts, chmod-arm lifecycles, anchor single-sourcing ---"
check "progress echo shape: loop" grep -q -F 'echo "progress_dir=$progress_dir"' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "rounds echo shape: loop" grep -q -F 'echo "rounds_dir=$rounds_dir"' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "toplevel echo shape: loop" grep -q -F 'echo "toplevel=${toplevel:-}"' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "progress echo shape: report" grep -q -F 'echo "progress_dir=$progress_dir"' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "rounds echo shape: report" grep -q -F 'echo "rounds_dir=$rounds_dir"' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "toplevel echo shape: report" grep -q -F 'echo "toplevel=${toplevel:-}"' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "scratch echo shape: prc" grep -q -F 'echo "scratch_dir=$scratch_dir"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "rounds echo shape: prc" grep -q -F 'echo "rounds_dir=$rounds_dir"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "toplevel echo shape: prc" grep -q -F 'echo "toplevel=${toplevel:-}"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "chmod arm cleans archive and progress: loop" grep -q 'cannot chmod rounds parent.*rm -rf "${rounds_dir:?}" "${progress_dir:?}"; exit 1' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "chmod arm cleans archive and progress: report" grep -q 'cannot chmod rounds parent.*rm -rf "${rounds_dir:?}" "${progress_dir:?}"; exit 1' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "run-root guarded: loop mktemp" grep -q -F 'mktemp -d "${run_root:?}/agent-review-loop' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "run-root guarded: loop rounds refuse" grep -q -F '[ ! -L "${run_root:?}/agent-review-loop-rounds" ]' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "run-root guarded: loop rounds mkdir" grep -q -F 'rounds_dir="${run_root:?}/agent-review-loop-rounds/' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "run-root guarded: loop rounds chmod" grep -q -F 'chmod 700 "${run_root:?}/agent-review-loop-rounds"' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "run-root guarded: report mktemp" grep -q -F 'mktemp -d "${run_root:?}/agent-review-report' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "run-root guarded: report rounds refuse" grep -q -F '[ ! -L "${run_root:?}/agent-review-report-rounds" ]' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "run-root guarded: report rounds mkdir" grep -q -F 'rounds_dir="${run_root:?}/agent-review-report-rounds/' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "run-root guarded: report rounds chmod" grep -q -F 'chmod 700 "${run_root:?}/agent-review-report-rounds"' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "prc trap covers rounds" grep -q -F '[ -n "${rounds_dir:-}" ] && rm -rf "${rounds_dir:?}"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc trap chains prior" grep -q -F '_prev_exit_trap' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc chmod arm keeps no cleanup (single-shot)" test -z "$(grep 'cannot chmod rounds parent' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | grep 'rm -rf')"
# Anchor literals stay single-sourced: build the search patterns from halves
# so these very lines do not count themselves.
lit_start='Mirror: 8 run-root boot'
check "mirror-start literal single-sourced" test "$(grep -c "${lit_start}straps" "${BUNDLE}/tests/verify-install.sh")" = "1"
lit_end='Mirror e'
check "mirror-end literal single-sourced" test "$(grep -c "${lit_end}nd" "${BUNDLE}/tests/verify-install.sh")" = "1"
check "refuse arm cleans progress: loop" grep -q 'rounds parent .* is a symlink; refusing.*rm -rf "${progress_dir:?}"; exit 1' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "refuse arm cleans progress: report" grep -q 'rounds parent .* is a symlink; refusing.*rm -rf "${progress_dir:?}"; exit 1' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "atomic rounds parent: loop" grep -q -F 'mkdir -m 700 "${run_root:?}/agent-review-loop-rounds"' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "atomic rounds parent: report" grep -q -F 'mkdir -m 700 "${run_root:?}/agent-review-report-rounds"' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "atomic rounds parent: prc" grep -q -F 'mkdir -m 700 "$run_root/pr-comments-rounds"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "blocker named: loop" grep -q -F 'may block the rounds parent' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "blocker named: report" grep -q -F 'may block the rounds parent' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "blocker named: prc" grep -q -F 'may block the rounds parent' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "rounds parent owned: loop" grep -q -F '[ -O "${run_root:?}/agent-review-loop-rounds" ]' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "rounds parent owned: report" grep -q -F '[ -O "${run_root:?}/agent-review-report-rounds" ]' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "rounds parent owned: prc" grep -q -F '[ -O "$run_root/pr-comments-rounds" ]' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "rounds parent re-asserted: loop" test "$(grep -c -F 'rounds parent ${run_root:?}/agent-review-loop-rounds changed under us' "${BUNDLE}/skills/agent-review-loop/SKILL.md")" = "3"
check "rounds parent re-asserted: report" test "$(grep -c -F 'rounds parent ${run_root:?}/agent-review-report-rounds changed under us' "${BUNDLE}/skills/agent-review-report/SKILL.md")" = "3"
check "rounds parent re-asserted: prc" test "$(grep -c -F 'rounds parent $run_root/pr-comments-rounds changed under us' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")" = "3"
check "rounds re-assert cleans progress: loop" test "$(grep -c 'rounds parent .* changed under us; refusing.*rm -rf' "${BUNDLE}/skills/agent-review-loop/SKILL.md")" = "3"
check "rounds re-assert cleans progress: report" test "$(grep -c 'rounds parent .* changed under us; refusing.*rm -rf' "${BUNDLE}/skills/agent-review-report/SKILL.md")" = "3"
check "rounds owned before chmod: loop" test "$(grep -n -F '[ -O "${run_root:?}/agent-review-loop-rounds" ]' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F 'chmod 700 "${run_root:?}/agent-review-loop-rounds"' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1)"
check "rounds owned before chmod: report" test "$(grep -n -F '[ -O "${run_root:?}/agent-review-report-rounds" ]' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F 'chmod 700 "${run_root:?}/agent-review-report-rounds"' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1)"
check "rounds owned before chmod: prc" test "$(grep -n -F '[ -O "$run_root/pr-comments-rounds" ]' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F 'chmod 700 "$run_root/pr-comments-rounds"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | cut -d: -f1 | head -n 1)"
check "prc rounds arms keep no cleanup (single-shot)" test -z "$(grep -F 'rounds parent $run_root/pr-comments-rounds changed under us' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | grep 'rm -rf' || true)"
check "heartbeat asserts toplevel: loop" grep -q -F 'toplevel drift: heartbeat' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "heartbeat asserts toplevel: report" grep -q -F 'toplevel drift: heartbeat' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "drift template single-quoted: loop" grep -q -F "_record='<toplevel-from-section-4>'" "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "drift template single-quoted: report" grep -q -F "_record='<toplevel-from-section-1>'" "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "escape note count: loop" test "$(grep -c -F 'embedded single quote' "${BUNDLE}/skills/agent-review-loop/SKILL.md")" = "3"
check "escape note count: report" test "$(grep -c -F 'embedded single quote' "${BUNDLE}/skills/agent-review-report/SKILL.md")" = "3"
check "escape note count: prc" test "$(grep -c -F 'embedded single quote' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")" = "4"
drift_loop_ln=$(grep -n -F 'toplevel drift: heartbeat' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1 || true)
mk_loop_ln=$(grep -n -F 'mktemp -d "${run_root:?}/agent-review-loop' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 || true)
check "drift marker present: loop" test -n "$drift_loop_ln"
check "progress marker present: loop" test -n "$mk_loop_ln"
check "drift precedes progress alloc: loop" test "$drift_loop_ln" -lt "$mk_loop_ln"
drift_rep_ln=$(grep -n -F 'toplevel drift: heartbeat' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1 || true)
mk_rep_ln=$(grep -n -F 'mktemp -d "${run_root:?}/agent-review-report' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 || true)
check "drift marker present: report" test -n "$drift_rep_ln"
check "progress marker present: report" test -n "$mk_rep_ln"
check "drift precedes progress alloc: report" test "$drift_rep_ln" -lt "$mk_rep_ln"
check "unset count: loop" test "$(grep -c -F 'unset GIT_DIR GIT_WORK_TREE' "${BUNDLE}/skills/agent-review-loop/SKILL.md")" = "4"
check "unset count: report" test "$(grep -c -F 'unset GIT_DIR GIT_WORK_TREE' "${BUNDLE}/skills/agent-review-report/SKILL.md")" = "7"
check "unset count: prc" test "$(grep -c -F 'unset GIT_DIR GIT_WORK_TREE' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")" = "2"
check "hygiene count: loop" test "$(grep -c -F 'unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS' "${BUNDLE}/skills/agent-review-loop/SKILL.md")" = "4"
check "hygiene count: report" test "$(grep -c -F 'unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS' "${BUNDLE}/skills/agent-review-report/SKILL.md")" = "7"
check "hygiene count: prc" test "$(grep -c -F 'unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")" = "2"
check "unset precedes diff probe: loop" test "$(grep -n -F 'unset GIT_DIR GIT_WORK_TREE' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F 'git diff --quiet HEAD' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1)"
check "unset precedes diff probe: report" test "$(grep -n -F 'unset GIT_DIR GIT_WORK_TREE' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F 'git diff --quiet HEAD' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1)"
check "unset precedes resolve: prc" test "$(grep -n -F 'unset GIT_DIR GIT_WORK_TREE' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F '# Resolve once' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | cut -d: -f1 | head -n 1)"
check "innermost worktree: loop" grep -q -F 'INNERMOST worktree' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "innermost worktree: report" grep -q -F 'INNERMOST worktree' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "innermost worktree: prc" grep -q -F 'INNERMOST worktree' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "never nest: loop" grep -q -F 'never nest a worktree' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "never nest: report" grep -q -F 'never nest a worktree' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "never nest: prc" grep -q -F 'never nest a worktree' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
hup1="trap 'exit 12"
check "trap HUP installed" grep -q -F "${hup1}9' HUP" "${BUNDLE}/tests/verify-install.sh"
quit1="trap 'exit 13"
check "trap QUIT installed" grep -q -F "${quit1}1' QUIT" "${BUNDLE}/tests/verify-install.sh"
int1="trap 'exit 130' I"
check "trap INT installed" grep -q -F "${int1}NT" "${BUNDLE}/tests/verify-install.sh"
check "prc trap warns unchainable prior" grep -q -F 'cannot chain prior EXIT trap' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc trap gated on bash" grep -q -F 'if [ -n "${BASH_VERSION:-}" ]; then' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc trap warns outside bash" grep -q -F 'cannot chain prior EXIT trap outside bash' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "pr input quoted: prc" grep -q -F "gh pr view '<pr_input>'" "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "pr input quoted: report" grep -q -F "gh pr view '<pr_input>'" "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "git add quoted: prc" grep -q -F "git add -- '<file1>' '<file2>'" "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "git push quoted: prc" grep -q -F "git push -u origin 'HEAD:refs/heads/<type>/<branch-name>'" "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "pr url quoted: prc" test "$(grep -c -F 'gh api --paginate "/repos/{owner}/{repo}/' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")" = "5"
check "prc annotations fetch paginates" grep -q -F 'gh api --paginate "/repos/{owner}/{repo}/check-runs/$c_id/annotations"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc check-runs uses triage variable" grep -q -F 'gh api --paginate "/repos/{owner}/{repo}/commits/$triage_sha/check-runs"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "pr number quoted: prc" test "$(grep -c -F 'gh pr view "<pr_number>"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")" = "6"
check "prc omitted counts open PRs" grep -q -F 'expected exactly one open PR for the current branch' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "cci cancel bound disclosed" grep -q -F 'newest 100 runs' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "prc cancel bound disclosed" grep -q -F 'newest 100 runs' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "pr checks quoted: prc" grep -q -F 'gh pr checks "<pr_number>"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "pr comment quoted: report" grep -q -F 'gh pr comment "<pr_number>"' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "pr numeric posix: report" grep -q -F 'case "$pr_number" in ""|*[!0-9]*)' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "prc end rm guarded" test -z "$(grep -F 'rm -rf "${scratch_dir}"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")"
check "scratch redirects guarded: prc" test "$(grep -c -F '> "${scratch_dir:?}/' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")" = "6"
check "single-shell mandate: loop" grep -q -F 'ONE bash invocation' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "single-shell mandate: report" grep -q -F 'ONE bash invocation' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "fresh-run guard: loop" grep -q -F 'FRESH RUN ONLY' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "fresh-run guard: report" grep -q -F 'FRESH RUN ONLY' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "fresh-run guards heartbeat: loop" test "$(grep -n -F 'FRESH RUN ONLY' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n "$MIRROR_START" "${BUNDLE}/skills/agent-review-loop/SKILL.md" | sed -n '2p' | cut -d: -f1)"
check "fresh-run guards heartbeat: report" test "$(grep -n -F 'FRESH RUN ONLY' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n "$MIRROR_START" "${BUNDLE}/skills/agent-review-report/SKILL.md" | sed -n '3p' | cut -d: -f1)"
check "drift precheck: loop" grep -q -F "heartbeat is not the section-4 toplevel" "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "drift precheck: report" grep -q -F "heartbeat is not the section-1 toplevel" "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "precheck precedes mirror: loop" test "$(grep -n -F 'heartbeat is not the section-4 toplevel' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1)" -lt "$(grep -n "$MIRROR_START" "${BUNDLE}/skills/agent-review-loop/SKILL.md" | sed -n '2p' | cut -d: -f1)"
check "precheck precedes mirror: report" test "$(grep -n -F 'heartbeat is not the section-1 toplevel' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1)" -lt "$(grep -n "$MIRROR_START" "${BUNDLE}/skills/agent-review-report/SKILL.md" | sed -n '3p' | cut -d: -f1)"
check "precheck derives effective toplevel: loop" grep -q -F '_pre="$(git rev-parse --show-toplevel 2>/dev/null)"' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "precheck derives effective toplevel: report" grep -q -F '_pre="$(git rev-parse --show-toplevel 2>/dev/null)"' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "precheck clears on residue: loop" grep -q -F '[ -e "$_pre/.agent-tmp" ] && [ ! -O "$_pre/.agent-tmp" ]' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "precheck clears on residue: report" grep -q -F '[ -e "$_pre/.agent-tmp" ] && [ ! -O "$_pre/.agent-tmp" ]' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "precheck compares effective: loop" grep -q -F '[ "$_pre" = "$_record" ]' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "precheck compares effective: report" grep -q -F '[ "$_pre" = "$_record" ]' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "postcheck compares recorded: loop" grep -q -F '[ "${toplevel:-}" = "$_record" ]' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "postcheck compares recorded: report" grep -q -F '[ "${toplevel:-}" = "$_record" ]' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "postcheck echo references var: loop" grep -q -F "!= section-4 '\$_record'" "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "postcheck echo references var: report" grep -q -F "!= section-1 '\$_record'" "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "no git -C in skills" test -z "$(grep -rn 'git -C' "${BUNDLE}/skills" || true)"
check "no narrow pathspec: loop" test -z "$(grep -F -- '-- .' "${BUNDLE}/skills/agent-review-loop/SKILL.md" || true)"
check "no narrow pathspec: report" test -z "$(grep -F -- '-- .' "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)"
check "no ext diff placed: loop" grep -q -F 'diff --no-ext-diff' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "no ext diff placed: report" grep -q -F 'diff --no-ext-diff' "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "diff mktemp arm: loop" test "$(grep -c -F 'failed to create diff scratch file' "${BUNDLE}/skills/agent-review-loop/SKILL.md" || true)" = "1"
check "diff fail arm: loop" test "$(grep -c -F 'git diff failed for' "${BUNDLE}/skills/agent-review-loop/SKILL.md" || true)" = "1"
check "diff empty arm: loop" test "$(grep -c -F 'empty diff for' "${BUNDLE}/skills/agent-review-loop/SKILL.md" || true)" = "1"
check "diff scratch exclusion: loop" test "$(grep -c -F "':!.agent-tmp/**'" "${BUNDLE}/skills/agent-review-loop/SKILL.md" || true)" = "1"
check "diff mktemp arms: report" test "$(grep -c -F 'failed to create diff scratch file' "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)" = "2"
check "diff fail arm: report" test "$(grep -c -F 'git diff failed for' "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)" = "1"
check "diff empty arms: report" test "$(grep -c -F 'empty diff for' "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)" = "2"
check "diff scratch exclusion: report" test "$(grep -c -F "':!.agent-tmp/**'" "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)" = "1"
check "pr resolve arm: report" test "$(grep -c -F 'gh pr view failed for PR' "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)" = "2"
check "pr sha arm: report" test "$(grep -c -F 'head SHA missing for PR' "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)" = "1"
check "pr diff arm: report" test "$(grep -c -F 'gh pr diff failed for PR' "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)" = "1"
check "pr numeric arm: report" test "$(grep -c -F 'resolved PR number is non-numeric' "${BUNDLE}/skills/agent-review-report/SKILL.md" || true)" = "1"
check "toplevel echo count: loop" test "$(grep -c -F 'echo "toplevel=' "${BUNDLE}/skills/agent-review-loop/SKILL.md")" = "2"
check "toplevel echo count: report" test "$(grep -c -F 'echo "toplevel=' "${BUNDLE}/skills/agent-review-report/SKILL.md")" = "3"
check "toplevel echo count: prc" test "$(grep -c -F 'echo "toplevel=' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md")" = "1"
check "newest bounds enumeration" grep -q -F 'sort -rn | head -20' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "newest lists dirs only" grep -q -F -- '-mindepth 1 -maxdepth 1 -type d' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "newest per-root substitution" grep -q -F 'substitute each candidate root for R' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "newest skips links" grep -q -F 'skip any candidate where `[ -L ]` regardless' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "newest matches headers only" grep -q -F 'head -c 2000' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "newest notes zsh" grep -q -F 'no matches found' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "newest root single-quoted" grep -q -F "'R/.agent-tmp/agent-review-loop-rounds' -mindepth" "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "newest zero-candidates arm" grep -q -F 'zero candidates under every root' "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "newest enumerates roots" grep -q -F "git worktree list --porcelain | grep '^worktree ' | cut -d' ' -f2-" "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "cd-first: loop" grep -q -F "cd '<recorded toplevel>' || { echo \"ERROR: cannot cd to recorded toplevel" "${BUNDLE}/skills/agent-review-loop/SKILL.md"
check "cd-first: report" grep -q -F "cd '<recorded toplevel>' || { echo \"ERROR: cannot cd to recorded toplevel" "${BUNDLE}/skills/agent-review-report/SKILL.md"
check "cd-first: prc" grep -q -F "cd '<recorded toplevel>' || { echo \"ERROR: cannot cd to recorded toplevel" "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc fence-range start present" grep -q -F "# ${lit_end}nd" "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc fence-range end present" grep -q -F '# Inline diff comments' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc 1A setup one fence" test "$(sed -n "/# ${lit_end}nd/,/# Inline diff comments/p" "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | grep -c '^```' || true)" = "0"
check "golden mode 644" test "$(stat -f %Lp "${BUNDLE}/tests/fixtures/bootstrap-golden.txt" 2>/dev/null || stat -c %a "${BUNDLE}/tests/fixtures/bootstrap-golden.txt")" = "644"
pre1='tmpd=""; tmp'
check "regen pre-inits scratch" grep -q -F "${pre1}g=\"\"" "${BUNDLE}/tests/verify-install.sh"
rt1='trap regen_cleanup EX'
check "regen traps EXIT" grep -q -F "${rt1}IT" "${BUNDLE}/tests/verify-install.sh"
tdm='TEST_DIR="$(mk'
check "regen dispatch precedes scratch" test "$(grep -n -F "${rt1}IT" "${BUNDLE}/tests/verify-install.sh" | cut -d: -f1)" -lt "$(grep -n -F "${tdm}temp" "${BUNDLE}/tests/verify-install.sh" | cut -d: -f1 | head -n 1)"
cf1='local f="${fail:-'
check "cleanup defaults fail" grep -q -F "${cf1}0}\"" "${BUNDLE}/tests/verify-install.sh"
cd1='${LOG_DIR:-un'
check "cleanup defaults dirs" grep -q -F "${cd1}known}" "${BUNDLE}/tests/verify-install.sh"
sed -n '/# Resolve once/,/^trap - EXIT$/p' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/prc-resolve-range.txt"
check "prc resolve range nonempty" test -s "${LOG_DIR}/prc-resolve-range.txt"
check "prc 1A ERRORs route to stderr" test -z "$(grep -F 'echo "ERROR:' "${LOG_DIR}/prc-resolve-range.txt" | grep -v '>&2' || true)"
trap_ln=$(grep -n '^trap ' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | cut -d: -f1 | head -n 1 || true)
mk_ln=$(grep -n -F 'mktemp -d "$run_root/pr-comments' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | cut -d: -f1 || true)
check "trap marker present: prc" test -n "$trap_ln"
check "scratch marker present: prc" test -n "$mk_ln"
check "prc trap precedes mktemp" test "$trap_ln" -lt "$mk_ln"
check "scratch echo shape: cci" grep -q -F 'echo "scratch_dir=$scratch_dir"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "rounds echo shape: cci" grep -q -F 'echo "rounds_dir=$rounds_dir"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "toplevel echo shape: cci" grep -q -F 'echo "toplevel=${toplevel:-}"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci trap covers rounds" grep -q -F '[ -n "${rounds_dir:-}" ] && rm -rf "${rounds_dir:?}"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci trap chains prior" grep -q -F '_prev_exit_trap' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci chmod arm keeps no cleanup (single-shot)" test -z "$(grep 'cannot chmod rounds parent' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | grep 'rm -rf' || true)"
check "atomic rounds parent: cci" grep -q -F 'mkdir -m 700 "$run_root/check-ci-rounds"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "blocker named: cci" grep -q -F 'may block the rounds parent' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "rounds parent owned: cci" grep -q -F '[ -O "$run_root/check-ci-rounds" ]' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "rounds parent re-asserted: cci" test "$(grep -c -F 'rounds parent $run_root/check-ci-rounds changed under us' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" || true)" = "3"
check "rounds owned before chmod: cci" test "$(grep -n -F '[ -O "$run_root/check-ci-rounds" ]' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F 'chmod 700 "$run_root/check-ci-rounds"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | cut -d: -f1 | head -n 1)"
check "cci rounds arms keep no cleanup (single-shot)" test -z "$(grep -F 'rounds parent $run_root/check-ci-rounds changed under us' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | grep 'rm -rf' || true)"
check "escape note count: cci" test "$(grep -c -F 'embedded single quote' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" || true)" = "4"
check "unset count: cci" test "$(grep -c -F 'unset GIT_DIR GIT_WORK_TREE' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" || true)" = "2"
check "hygiene count: cci" test "$(grep -c -F 'unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" || true)" = "2"
check "unset precedes resolve: cci" test "$(grep -n -F 'unset GIT_DIR GIT_WORK_TREE' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | cut -d: -f1 | head -n 1)" -lt "$(grep -n -F '# Resolve once' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | cut -d: -f1 | head -n 1)"
check "innermost worktree: cci" grep -q -F 'INNERMOST worktree' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "never nest: cci" grep -q -F 'never nest a worktree' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci trap warns unchainable prior" grep -q -F 'cannot chain prior EXIT trap' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci trap gated on bash" grep -q -F 'if [ -n "${BASH_VERSION:-}" ]; then' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci trap warns outside bash" grep -q -F 'cannot chain prior EXIT trap outside bash' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "pr input quoted: cci" grep -q -F "gh pr view '<pr_input>'" "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "git add quoted: cci" grep -q -F "git add -- '<file1>' '<file2>'" "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "git push quoted: cci" grep -q -F "git push -u origin 'HEAD:refs/heads/<type>/<branch-name>'" "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci cancel lists via encoded branch" grep -q -F 'gh api --method GET "/repos/{owner}/{repo}/actions/runs" -f branch="$branch"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci cancel single page" test -z "$(grep -F 'actions/runs' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | grep -F -- '--paginate' || true)"
check "prc cancel single page" test -z "$(grep -F 'actions/runs' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | grep -F -- '--paginate' || true)"
check "pr number quoted: cci" test "$(grep -c -F 'gh pr view "<pr_number>"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" || true)" = "6"
check "pr checks quoted: cci" grep -q -F 'gh pr checks "<pr_number>"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci checks captured not fatal" grep -q -F 'checks_out=$(gh pr checks "$pr_number"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci snapshot runs by triage commit" grep -q -F 'gh run list --commit "$triage_sha" --limit 100' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci omitted counts open PRs" grep -q -F 'expected exactly one open PR for the current branch' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "prc comment fetch paginates" grep -q -F 'gh api --paginate "/repos/{owner}/{repo}/pulls/$pr_number/comments"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc review fetch paginates" grep -q -F 'gh api --paginate "/repos/{owner}/{repo}/pulls/$pr_number/reviews"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc issue fetch paginates" grep -q -F 'gh api --paginate "/repos/{owner}/{repo}/issues/$pr_number/comments"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "cci snapshot sha bound" grep -q -F 'snapshot_sha=$(gh pr view "$pr_number"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci omitted input contract" grep -q -F 'open exactly one PR for the current branch' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci rerun warns and continues" grep -q -F 'WARNING: rerun failed for <run-id>; continuing' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci poll timeout warns" grep -q -F 'checks still pending for PR <pr_number> after 30 polls' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci cancel pages bounded" grep -q -F -- '-F per_page=100' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "prc cancel pages bounded" grep -q -F -- '-F per_page=100' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "cci end rm guarded" test -z "$(grep -F 'rm -rf "${scratch_dir}"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" || true)"
check "scratch redirects guarded: cci" test "$(grep -c -F '> "${scratch_dir:?}/' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" || true)" = "2"
check "toplevel echo count: cci" test "$(grep -c -F 'echo "toplevel=' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" || true)" = "1"
check "cd-first: cci" grep -q -F "cd '<recorded toplevel>' || { echo \"ERROR: cannot cd to recorded toplevel" "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci fence-range start present" grep -q -F "# ${lit_end}nd" "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci fence-range end present" grep -q -F '# Check snapshot plus branch run list for the triage SHA' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci 1A setup one fence" test "$(sed -n "/# ${lit_end}nd/,/# Check snapshot plus branch run list for the triage SHA/p" "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | grep -c '^```' || true)" = "0"
sed -n '/# Resolve once/,/^trap - EXIT$/p' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/cci-resolve-range.txt"
check "cci resolve range nonempty" test -s "${LOG_DIR}/cci-resolve-range.txt"
check "cci 1A ERRORs route to stderr" test -z "$(grep -F 'echo "ERROR:' "${LOG_DIR}/cci-resolve-range.txt" | grep -v '>&2' || true)"
cci_trap_ln=$(grep -n '^trap ' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | cut -d: -f1 | head -n 1 || true)
cci_mk_ln=$(grep -n -F 'mktemp -d "$run_root/check-ci' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | cut -d: -f1 || true)
check "trap marker present: cci" test -n "$cci_trap_ln"
check "scratch marker present: cci" test -n "$cci_mk_ln"
check "cci trap precedes mktemp" test "$cci_trap_ln" -lt "$cci_mk_ln"
sed -n '/^cleanup() {/,/^}/p' "${BUNDLE}/tests/verify-install.sh" > "${LOG_DIR}/cleanup-fn.sh"
printf 'set -u\n. "$RW_LD/cleanup-fn.sh"\nunset fail LOG_DIR TEST_DIR\n(exit 3)\ncleanup\n' > "${LOG_DIR}/cleanup-run.sh"
run_split cleanup-unset env "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/cleanup-run.sh"
check "cleanup runs unset under set -u" test "$(cat "${LOG_DIR}/split-cleanup-unset.rc")" = "0"
check "cleanup unset reports failure" grep -q "Verification failed (exit code 3, 0 failure(s)). Retaining diagnostic logs in: unknown" "${LOG_DIR}/split-cleanup-unset.out"

sed -n '/# Check snapshot plus branch run list/,/snapshot_sha.*triage_sha/p' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/cci-checks.sh" || true
check "cci checks block extracted" grep -q -F 'checks_out=$(gh pr checks' "${LOG_DIR}/cci-checks.sh"
check "cci checks json fields exact" grep -q -F 'gh pr checks "$pr_number" --json name,bucket,workflow' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci checks workflow selector exact" grep -q -F '(.workflow // "external")' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
mkdir -p "${TEST_DIR}/stubbin-cci-checks"
cat > "${TEST_DIR}/stubbin-cci-checks/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
"pr checks")
  json_fields=""; prev=""; for a in "$@"; do if [ "$prev" = "--json" ]; then json_fields="$a"; fi; prev="$a"; done
  [ "$json_fields" = "name,bucket,workflow" ] || { echo "Unknown JSON field in: $json_fields" >&2; exit 1; }
  case "$STUB_MODE" in
    pass|manyruns) printf '[{"name":"build","bucket":"pass","workflow":"CI"}]\n'; exit 0;;
    fail) printf '[{"name":"build","bucket":"fail","workflow":"CI"}]\n'; exit 1;;
    pending) printf '[{"name":"build","bucket":"pending","workflow":"CI"}]\n'; exit 8;;
    empty) echo "no checks reported on the 'feat/test' branch" >&2; exit 1;;
    invalid) printf 'not-json\n'; exit 1;;
    shape) printf '[{"name":"build"}]\n'; exit 0;;
    emptyerr) echo 'authentication required' >&2; exit 1;;
  esac;;
"run list")
  if [ "$STUB_MODE" = "manyruns" ]; then
    printf '['; i=1; while [ $i -le 100 ]; do if [ $i -gt 1 ]; then printf ','; fi; printf '{"databaseId":%s,"conclusion":"success","name":"build","status":"completed","headSha":"%s"}' "$i" "$STUB_SHA"; i=$((i+1)); done; printf ']\n'; exit 0
  fi
  printf '[{"databaseId":1,"conclusion":"success","name":"build","status":"completed","headSha":"%s"},{"databaseId":2,"conclusion":"failure","name":"other","status":"completed","headSha":"1111111111111111111111111111111111111111"}]\n' "$STUB_SHA"; exit 0;;
"pr view") printf '%s\n' "${STUB_VIEW_SHA:-$STUB_SHA}"; exit 0;;
*) exit 1;;
esac
EOF
chmod +x "${TEST_DIR}/stubbin-cci-checks/gh"
cat > "${LOG_DIR}/cci-checks-run.sh" <<'EOF'
set -u
scratch_dir="$RW_TD/cci-checks-$STUB_MODE"; mkdir -p "$scratch_dir"
pr_number=6; triage_sha="$STUB_SHA"; branch='feat/test'
. "$RW_LD/cci-checks.sh"
printf 'CHECKS=%s\n' "$(cat "$scratch_dir/checks.json")"
EOF
stub_sha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
for mode in pass fail pending empty; do
  run_split "cci-checks-$mode" env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=$mode" "STUB_SHA=$stub_sha" PATH="${TEST_DIR}/stubbin-cci-checks:${PATH}" bash "${LOG_DIR}/cci-checks-run.sh"
  check "cci checks $mode rc" test "$(cat "${LOG_DIR}/split-cci-checks-$mode.rc")" = "0"
done
check "cci checks pass payload kept" grep -q '"bucket":"pass"' "${LOG_DIR}/split-cci-checks-pass.out"
check "cci checks pass renders workflow" grep -q 'pass: build \[CI\]' "${LOG_DIR}/split-cci-checks-pass.out"
check "cci checks fail payload kept" grep -q '"bucket":"fail"' "${LOG_DIR}/split-cci-checks-fail.out"
check "cci checks pending payload kept" grep -q '"bucket":"pending"' "${LOG_DIR}/split-cci-checks-pending.out"
check "cci checks empty becomes array" grep -q 'CHECKS=\[\]' "${LOG_DIR}/split-cci-checks-empty.out"
check "cci checks empty names no-ci" grep -q 'no checks reported for PR 6; report no CI' "${LOG_DIR}/split-cci-checks-empty.err"
check "cci checks runs bound to triage sha" grep -q '#1 @ deadbee' "${LOG_DIR}/split-cci-checks-pass.out"
check "cci checks foreign sha run filtered" test -z "$(grep '#2 @' "${LOG_DIR}/split-cci-checks-pass.out" || true)"
for mode in shape emptyerr invalid; do
  run_split "cci-checks-$mode" env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=$mode" "STUB_SHA=$stub_sha" PATH="${TEST_DIR}/stubbin-cci-checks:${PATH}" bash "${LOG_DIR}/cci-checks-run.sh"
  check "cci checks $mode rc" test "$(cat "${LOG_DIR}/split-cci-checks-$mode.rc")" = "1"
done
check "cci checks emptyerr named" grep -q 'checks fetch failed' "${LOG_DIR}/split-cci-checks-emptyerr.err"
run_split cci-checks-drift env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=pass" "STUB_SHA=$stub_sha" "STUB_VIEW_SHA=1111111111111111111111111111111111111111" PATH="${TEST_DIR}/stubbin-cci-checks:${PATH}" bash "${LOG_DIR}/cci-checks-run.sh"
check "cci checks drift rc" test "$(cat "${LOG_DIR}/split-cci-checks-drift.rc")" = "1"
check "cci checks drift named" grep -q 'PR head moved during snapshot' "${LOG_DIR}/split-cci-checks-drift.err"

awk '/^   ```$/{if (f) exit} /poll_sha_start=/{f=1} f' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/poll-cci.txt" || true
awk '/^   ```$/{if (f) exit} /poll_sha_start=/{f=1} f' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/poll-prc.txt" || true
check "poll span extracted: cci" test -s "${LOG_DIR}/poll-cci.txt"
check "poll span extracted: prc" test -s "${LOG_DIR}/poll-prc.txt"
check "cci/prc poll spans identical" cmp -s "${LOG_DIR}/poll-cci.txt" "${LOG_DIR}/poll-prc.txt"
awk '/^   ```$/{if (f) exit} /snap=.*gh pr view/{f=1} f' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/cancel-cci.txt" || true
awk '/^   ```$/{if (f) exit} /snap=.*gh pr view/{f=1} f' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/cancel-prc.txt" || true
check "cancel span extracted: cci" test -s "${LOG_DIR}/cancel-cci.txt"
check "cancel span extracted: prc" test -s "${LOG_DIR}/cancel-prc.txt"
check "cci/prc cancel spans identical" cmp -s "${LOG_DIR}/cancel-cci.txt" "${LOG_DIR}/cancel-prc.txt"
for s in agent-review-loop agent-review-report agent-review-pr-comments agent-review-check-ci; do
  check "filing bullet template: $s" grep -q -F -- '- **Title**: Trigger condition' "${BUNDLE}/skills/$s/SKILL.md"
  check "filing attribution ban: $s" grep -q -F 'Zero attribution: no signatures' "${BUNDLE}/skills/$s/SKILL.md"
  check "filing heading verify: $s" grep -q -F "must equal 8" "${BUNDLE}/skills/$s/SKILL.md"
  check "filing outside-workspace fallback: $s" grep -q -F 'absolute path is outside the' "${BUNDLE}/skills/$s/SKILL.md"
done
for s in agent-review-loop agent-review-report agent-review-pr-comments agent-review-check-ci; do
  sed -n '/backup_tmp=/,/failed to snapshot/p' "${BUNDLE}/skills/$s/SKILL.md" > "${LOG_DIR}/backup-$s.txt" || true
  check "backup unique shape: $s" grep -q -F -- '-$$-${backup_tmp##*.}' "${BUNDLE}/skills/$s/SKILL.md"
done
check "backup spans identical: report" cmp -s "${LOG_DIR}/backup-agent-review-check-ci.txt" "${LOG_DIR}/backup-agent-review-report.txt"
check "backup spans identical: pr-comments" cmp -s "${LOG_DIR}/backup-agent-review-check-ci.txt" "${LOG_DIR}/backup-agent-review-pr-comments.txt"
check "backup spans identical: loop" cmp -s "${LOG_DIR}/backup-agent-review-check-ci.txt" "${LOG_DIR}/backup-agent-review-loop.txt"
mkdir -p "${TEST_DIR}/stubbin-poll"
cat > "${TEST_DIR}/stubbin-poll/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
"pr view")
  case "$*" in
    *statusCheckRollup*)
      jqexpr=""; prev=""
      for a in "$@"; do if [ "$prev" = "--jq" ]; then jqexpr="$a"; fi; prev="$a"; done
      printf '{"statusCheckRollup":[]}' | jq -r "${jqexpr:-length}"
      exit 0;;
  esac
  printf 'x\n' >> "$STUB_VIEWS"
  if [ "${STUB_FAIL_OPEN:-0}" = "1" ] && [ "$(wc -l < "$STUB_VIEWS" | tr -d ' ')" = "1" ]; then exit 1; fi
  if [ "${STUB_FAIL_CLOSE:-0}" = "1" ] && [ "$(wc -l < "$STUB_VIEWS" | tr -d ' ')" -gt 1 ]; then exit 1; fi
  if [ "${STUB_DRIFT:-0}" = "1" ] && [ "$(wc -l < "$STUB_VIEWS" | tr -d ' ')" -gt 1 ]; then printf '%s\n' "$STUB_SHA2"; else printf '%s\n' "$STUB_SHA"; fi
  exit 0;;
"pr checks")
  printf 'x\n' >> "$STUB_COUNT"
  case "$STUB_MODE" in
    empty) echo "no checks reported on the 'feat/test' branch" >&2; exit 1;;
    garbage) printf 'not-json\n'; exit 1;;
    shape) printf '["x"]\n'; exit 0;;
    elem) printf '[{"name":"build"}]\n'; exit 0;;
    vanish) n=$(wc -l < "$STUB_COUNT" | tr -d ' '); if [ "$n" -le 29 ]; then printf '[{"name":"build","bucket":"pending"}]\n'; exit 8; fi; exit 1;;
    vanish3) n=$(wc -l < "$STUB_COUNT" | tr -d ' '); if [ "$n" -le 2 ]; then printf '[{"name":"build","bucket":"pending"}]\n'; exit 8; fi; exit 1;;
    mixpending) n=$(wc -l < "$STUB_COUNT" | tr -d ' '); case $((n % 4)) in 2|3) printf '[]\n'; exit 0;; *) printf '[{"name":"build","bucket":"pending"}]\n'; exit 8;; esac;;
    mixfetch) n=$(wc -l < "$STUB_COUNT" | tr -d ' '); case "$n" in 1|3|4) printf '[]\n'; exit 0;; 2) printf 'not-json\n'; exit 1;; *) printf '[{"name":"build","bucket":"pass"}]\n'; exit 1;; esac;;
    pending) printf '[{"name":"build","bucket":"pending"}]\n'; exit 8;;
    settle)
      n=$(wc -l < "$STUB_COUNT")
      if [ "$n" -lt 2 ]; then printf '[{"name":"build","bucket":"pending"}]\n'; exit 8; fi
      printf '[{"name":"build","bucket":"pass"}]\n'; exit 1;;
  esac;;
*) exit 1;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "${TEST_DIR}/stubbin-poll/sleep"
chmod +x "${TEST_DIR}/stubbin-poll/gh" "${TEST_DIR}/stubbin-poll/sleep"
cat > "${LOG_DIR}/poll-run.sh" <<'EOF'
set -u
pr_number=6; run_root="$RW_TD"
STUB_VIEWS="${STUB_VIEWS:-$RW_TD/poll-views}"; export STUB_VIEWS
: > "$STUB_COUNT"; : > "$STUB_VIEWS"
. "${RW_SPAN:-$RW_LD/poll-cci.txt}"
printf 'CALLS=%s\n' "$(wc -l < "$STUB_COUNT" | tr -d ' ')"
EOF
for mode in empty settle pending; do
  run_split "poll-$mode" env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=$mode" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-$mode" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
  check "poll $mode rc" test "$(cat "${LOG_DIR}/split-poll-$mode.rc")" = "0"
done
check "poll empty breaks at three" grep -qx 'CALLS=3' "${LOG_DIR}/split-poll-empty.out"
check "poll empty names no-checks" grep -q 'reporting no-checks outcome' "${LOG_DIR}/split-poll-empty.err"
check "poll done settles pass" grep -q '"bucket":"pass"' "${LOG_DIR}/split-poll-settle.out"
check "poll pending times out marked" grep -q 'still pending' "${LOG_DIR}/split-poll-pending.err"
check "poll pending used all rounds" grep -q 'CALLS=30' "${LOG_DIR}/split-poll-pending.out"
grep -F 'gh run rerun "<run-id>" --failed' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/rerun-line.sh" || true
cat > "${LOG_DIR}/rerun-run.sh" <<'EOF'
set -u
. "$RW_LD/rerun-line.sh"
echo CONTINUED
EOF
mkdir -p "${TEST_DIR}/stubbin-rerun"
printf '#!/bin/sh\nexit 1\n' > "${TEST_DIR}/stubbin-rerun/gh"
chmod +x "${TEST_DIR}/stubbin-rerun/gh"
run_split poll-rerun env "RW_LD=${LOG_DIR}" PATH="${TEST_DIR}/stubbin-rerun:${PATH}" bash "${LOG_DIR}/rerun-run.sh"
check "rerun failure continues rc" test "$(cat "${LOG_DIR}/split-poll-rerun.rc")" = "0"
check "rerun failure warns" grep -q 'WARNING: rerun failed' "${LOG_DIR}/split-poll-rerun.err"
check "rerun failure reaches next step" grep -q 'CONTINUED' "${LOG_DIR}/split-poll-rerun.out"
sed -n '/backup_dir=/,/^     fi$/p' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/backup-block.sh" || true
cat > "${LOG_DIR}/backup-run.sh" <<'EOF'
set -u
target="$RW_TD/snap-target.md"
printf 'v1\n' > "$target"
. "$RW_LD/backup-block.sh"
printf 'v2\n' > "$target"
. "$RW_LD/backup-block.sh"
ls "$RW_TD/backups"/review-refinements-*.md | wc -l | tr -d ' '
grep -l '^v1$' "$RW_TD/backups"/review-refinements-*.md | wc -l | tr -d ' '
grep -l '^v2$' "$RW_TD/backups"/review-refinements-*.md | wc -l | tr -d ' '
EOF
run_split backup-double env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/backup-run.sh"
check "backup double rc" test "$(cat "${LOG_DIR}/split-backup-double.rc")" = "0"
check "backup double output" test "$(cat "${LOG_DIR}/split-backup-double.out")" = "$(printf '2\n1\n1')"
check "poll empty warns once" test "$(grep -c 'no checks reported for PR' "${LOG_DIR}/split-poll-empty.err")" = "1"
run_split poll-drift env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=settle" "STUB_DRIFT=1" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_SHA2=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "STUB_COUNT=${TEST_DIR}/poll-count-drift" "STUB_VIEWS=${TEST_DIR}/poll-views-drift" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll drift rc" test "$(cat "${LOG_DIR}/split-poll-drift.rc")" = "0"
check "poll drift warns" grep -q 'PR head moved during poll' "${LOG_DIR}/split-poll-drift.err"
run_split poll-garbage env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=garbage" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-garbage" "STUB_VIEWS=${TEST_DIR}/poll-views-garbage" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll garbage terminal names parse" grep -q 'payload unparseable after 30 polls' "${LOG_DIR}/split-poll-garbage.err"
check "snapshot truncation warned" grep -q -F 'run list truncated at 100 runs' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "cci fallback by tip commit" grep -q -F 'gh run list --commit "$tip"' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "prc fallback by tip commit" grep -q -F 'gh run list --commit "$tip"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "cci fallback tip validated" grep -q -F 'empty tip SHA; refusing fallback run list' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "prc fallback tip validated" grep -q -F 'empty tip SHA; refusing fallback run list' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
grep '^### Pillar' "${BUNDLE}/skills/agent-review-loop/thematic-review-pillars.md" > "${LOG_DIR}/pillar-titles.txt" || true
for s in agent-review-loop agent-review-report agent-review-pr-comments agent-review-check-ci; do
  grep -o '### Pillar [0-9]: [^`]*' "${BUNDLE}/skills/$s/SKILL.md" > "${LOG_DIR}/titles-$s.txt" || true
  check "pillar titles canonical: $s" cmp -s "${LOG_DIR}/pillar-titles.txt" "${LOG_DIR}/titles-$s.txt"
done
for s in agent-review-loop agent-review-report agent-review-pr-comments agent-review-check-ci; do
  check "filing prune consent: $s" grep -q -F 'Never prune or delete' "${BUNDLE}/skills/$s/SKILL.md"
  check "filing backup keep-five: $s" grep -q -F 'keeping the latest 5' "${BUNDLE}/skills/$s/SKILL.md"
  check "readme contents entry: $s" grep -q -F "skills/$s/SKILL.md" "${BUNDLE}/README.md"
  check "readme uninstall entry: $s" grep -q -F "muse/skills/$s" "${BUNDLE}/README.md"
done
awk '/tip=\$\(gh pr view/{f=1} f; f&&/^   ```$/{exit}' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/fallback-cci.txt" || true
awk '/tip=\$\(gh pr view/{f=1} f; f&&/^   ```$/{exit}' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/fallback-prc.txt" || true
check "fallback span extracted: cci" test -s "${LOG_DIR}/fallback-cci.txt"
check "fallback span extracted: prc" test -s "${LOG_DIR}/fallback-prc.txt"
check "cci/prc fallback spans identical" cmp -s "${LOG_DIR}/fallback-cci.txt" "${LOG_DIR}/fallback-prc.txt"
check "prc fetch counts line" grep -q -F '"$inline_count" "$reviews_count" "$issue_count"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
check "prc inline count slurps diff file" grep -q -F 'inline_count=$(jq -s' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
grep -E '(inline|reviews|issue)_count=\$\(jq -s' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/prc-counts.sh" || true
grep -F "printf 'fetched counts: inline=" "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" >> "${LOG_DIR}/prc-counts.sh" || true
check "prc counts block extracted" test "$(wc -l < "${LOG_DIR}/prc-counts.sh" | tr -d ' ')" = "4"
mkdir -p "${TEST_DIR}/prc-counts"
printf '[{},{}][{}]' > "${TEST_DIR}/prc-counts/diff-comments.json"
printf '[{}]' > "${TEST_DIR}/prc-counts/reviews.json"
printf '[][][{},{}]' > "${TEST_DIR}/prc-counts/issue-comments.json"
cat > "${LOG_DIR}/prc-counts-run.sh" <<'EOF'
set -u
scratch_dir="$RW_TD/prc-counts"
. "$RW_LD/prc-counts.sh"
EOF
run_split prc-counts env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/prc-counts-run.sh"
check "prc counts rc" test "$(cat "${LOG_DIR}/split-prc-counts.rc")" = "0"
check "prc counts sum paginated pages" test "$(cat "${LOG_DIR}/split-prc-counts.out")" = "fetched counts: inline=3 reviews=1 issue=2"
check "prc counts slurp totals x4" test "$(grep -c 'map(length) | add // 0' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" || true)" = "4"
mkdir -p "${TEST_DIR}/prc-counts-empty"
: > "${TEST_DIR}/prc-counts-empty/diff-comments.json"
: > "${TEST_DIR}/prc-counts-empty/reviews.json"
: > "${TEST_DIR}/prc-counts-empty/issue-comments.json"
cat > "${LOG_DIR}/prc-counts-empty-run.sh" <<'EOF'
set -u
scratch_dir="$RW_TD/prc-counts-empty"
. "$RW_LD/prc-counts.sh"
EOF
run_split prc-counts-empty env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/prc-counts-empty-run.sh"
check "prc counts empty rc" test "$(cat "${LOG_DIR}/split-prc-counts-empty.rc")" = "0"
check "prc counts empty are zero" test "$(cat "${LOG_DIR}/split-prc-counts-empty.out")" = "fetched counts: inline=0 reviews=0 issue=0"
check "prc gh stack prerequisite" grep -q -F 'the `gh stack` extension must also be installed' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
sed -n '/# Inline diff comments/,/re-run to re-triage/p' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/prc-fetch.sh" || true
check "prc fetch span extracted" grep -q -F 'PR head moved during comment fetch' "${LOG_DIR}/prc-fetch.sh"
mkdir -p "${TEST_DIR}/stubbin-prc-fetch"
cat > "${TEST_DIR}/stubbin-prc-fetch/gh" <<'EOF'
#!/bin/sh
if [ "$1" = "api" ]; then
  case "$3" in
    *annotations*) printf '[{"annotation_level":"warning","path":"a.md","start_line":3,"message":"note"}]\n';;
    *check-runs*) printf '{"total_count":1,"check_runs":[{"id":101,"name":"lint-job","output":{"annotations_count":1}}]}\n';;
    *pulls*reviews*) printf '[{"id":2,"state":"COMMENTED","user":{"login":"bot"},"body":"review body"}]\n';;
    *pulls*) printf '[{"id":1,"path":"a.md","line":3,"user":{"login":"bot"},"body":"diff body"}]\n';;
    *issues*) printf '[{"id":3,"user":{"login":"bot"},"body":"issue body"}]\n';;
    *) exit 1;;
  esac
  exit 0
fi
if [ "$1 $2" = "pr view" ]; then printf '%s\n' "${STUB_VIEW_SHA:?}"; exit 0; fi
exit 1
EOF
chmod +x "${TEST_DIR}/stubbin-prc-fetch/gh"
cat > "${LOG_DIR}/prc-fetch-run.sh" <<'EOF'
set -u
scratch_dir="$RW_TD/prc-fetch-run"; mkdir -p "$scratch_dir"
pr_number=6; triage_sha="$STUB_SHA"
. "$RW_LD/prc-fetch.sh"
EOF
run_split prc-fetch-match env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_VIEW_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" PATH="${TEST_DIR}/stubbin-prc-fetch:${PATH}" bash "${LOG_DIR}/prc-fetch-run.sh"
check "prc fetch match rc" test "$(cat "${LOG_DIR}/split-prc-fetch-match.rc")" = "0"
check "prc fetch match counts" grep -q 'fetched counts: inline=1 reviews=1 issue=1' "${LOG_DIR}/split-prc-fetch-match.out"
run_split prc-fetch-drift env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_VIEW_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" PATH="${TEST_DIR}/stubbin-prc-fetch:${PATH}" bash "${LOG_DIR}/prc-fetch-run.sh"
check "prc fetch drift rc" test "$(cat "${LOG_DIR}/split-prc-fetch-drift.rc")" = "1"
check "prc fetch drift named" grep -q 'PR head moved during comment fetch' "${LOG_DIR}/split-prc-fetch-drift.err"
check "prc snapshot rebinds head" grep -q -F 'PR head moved during comment fetch (triage $triage_sha, now $snapshot_sha); re-run to re-triage' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
run_split poll-shape env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=shape" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-shape" "STUB_VIEWS=${TEST_DIR}/poll-views-shape" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll shape terminal names parse" grep -q 'payload unparseable after 30 polls' "${LOG_DIR}/split-poll-shape.err"
run_split poll-elem env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=elem" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-elem" "STUB_VIEWS=${TEST_DIR}/poll-views-elem" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll elem terminal names parse" grep -q 'payload unparseable after 30 polls' "${LOG_DIR}/split-poll-elem.err"
run_split poll-vanish env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=vanish" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-vanish" "STUB_VIEWS=${TEST_DIR}/poll-views-vanish" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll vanish names disappeared" grep -q 'checks disappeared on the final poll' "${LOG_DIR}/split-poll-vanish.err"
run_split poll-vanish3 env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=vanish3" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-vanish3" "STUB_VIEWS=${TEST_DIR}/poll-views-vanish3" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll vanish early names disappeared" grep -q 'checks disappeared for PR' "${LOG_DIR}/split-poll-vanish3.err"
check "poll vanish early not no-checks" test -z "$(grep 'no-checks outcome' "${LOG_DIR}/split-poll-vanish3.err" || true)"
run_split poll-mixpending env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=mixpending" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-mixpending" "STUB_VIEWS=${TEST_DIR}/poll-views-mixpending" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll mixed pending no early break" grep -qx 'CALLS=30' "${LOG_DIR}/split-poll-mixpending.out"
check "poll mixed pending not no-checks" test -z "$(grep 'no-checks outcome' "${LOG_DIR}/split-poll-mixpending.err" || true)"
run_split poll-mixfetch env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=mixfetch" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-mixfetch" "STUB_VIEWS=${TEST_DIR}/poll-views-mixfetch" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll mixed fetch settles pass" grep -q '"bucket":"pass"' "${LOG_DIR}/split-poll-mixfetch.out"
check "poll mixed fetch not no-checks" test -z "$(grep 'no-checks outcome' "${LOG_DIR}/split-poll-mixfetch.err" || true)"
run_split poll-failopen env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=settle" "STUB_FAIL_OPEN=1" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-failopen" "STUB_VIEWS=${TEST_DIR}/poll-views-failopen" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll open failure unattributed" grep -q 'settled checks are unattributed (opening head unreadable)' "${LOG_DIR}/split-poll-failopen.err"
run_split cci-checks-manyruns env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=manyruns" "STUB_SHA=$stub_sha" PATH="${TEST_DIR}/stubbin-cci-checks:${PATH}" bash "${LOG_DIR}/cci-checks-run.sh"
check "cci checks manyruns warns truncated" grep -q 'run list truncated at 100 runs' "${LOG_DIR}/split-cci-checks-manyruns.err"
run_split poll-failclose env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=settle" "STUB_FAIL_CLOSE=1" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-failclose" "STUB_VIEWS=${TEST_DIR}/poll-views-failclose" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll closing failure inconclusive" grep -q 'closing head read failed; reporting inconclusive' "${LOG_DIR}/split-poll-failclose.err"
mkdir -p "${TEST_DIR}/stubbin-cancel"
cat > "${TEST_DIR}/stubbin-cancel/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
"pr view")
  case "$*" in
    *@tsv*) printf 'feat/test\t%s\n' "$STUB_OLD";;
    *) printf '%s\n' "$STUB_NEW";;
  esac
  exit 0;;
"api --method")
  jqexpr=""; prev=""
  for a in "$@"; do if [ "$prev" = "--jq" ]; then jqexpr="$a"; fi; prev="$a"; done
  printf '{"workflow_runs":[{"id":1,"head_sha":"%s","status":"in_progress"},{"id":2,"head_sha":"%s","status":"in_progress"},{"id":3,"head_sha":"%s","status":"completed"},{"id":4,"head_sha":"%s","status":"queued"},{"id":5,"head_sha":"%s","status":"waiting"}]}' "$STUB_OLD" "$STUB_NEW" "$STUB_OLD" "$STUB_OLD" "$STUB_OLD" | jq -r "$jqexpr"
  exit 0;;
"run cancel") printf '%s\n' "$3" >> "$STUB_CANCELLED"; exit 0;;
*) exit 1;;
esac
EOF
chmod +x "${TEST_DIR}/stubbin-cancel/gh"
cat > "${LOG_DIR}/cancel-run.sh" <<'EOF'
set -u
: > "$STUB_CANCELLED"
. "$RW_SPAN"
EOF
for s in cci prc; do
  run_split "cancel-$s" env "RW_SPAN=${LOG_DIR}/cancel-$s.txt" "STUB_OLD=old111" "STUB_NEW=new222" "STUB_CANCELLED=${TEST_DIR}/cancelled-$s" PATH="${TEST_DIR}/stubbin-cancel:${PATH}" bash "${LOG_DIR}/cancel-run.sh"
  check "cancel $s rc" test "$(cat "${LOG_DIR}/split-cancel-$s.rc")" = "0"
  check "cancel $s cancels superseded" grep -q '^1$' "${TEST_DIR}/cancelled-$s"
  check "cancel $s spares fresh tip" test -z "$(grep '^2$' "${TEST_DIR}/cancelled-$s" || true)"
  check "cancel $s spares completed" test -z "$(grep '^3$' "${TEST_DIR}/cancelled-$s" || true)"
  check "cancel $s cancels queued" grep -qx '4' "${TEST_DIR}/cancelled-$s"
  check "cancel $s cancels waiting" grep -qx '5' "${TEST_DIR}/cancelled-$s"
done
sed -n '/# Resolve once/,/^printf .number:/p' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" | sed "s/'<pr_input>'/''/" > "${LOG_DIR}/prc-resolve-omit.sh" || true
check "prc resolve omit extracted" grep -q 'open_count=' "${LOG_DIR}/prc-resolve-omit.sh"
mkdir -p "${TEST_DIR}/stubbin-prc-resolve"
cat > "${TEST_DIR}/stubbin-prc-resolve/gh" <<'EOF'
#!/bin/sh
json_fields=""; jq_expr=""; prev=""
for a in "$@"; do case "$prev" in --json) json_fields="$a";; --jq) jq_expr="$a";; esac; prev="$a"; done
case "$1 $2" in
"pr list")
  [ "$json_fields" = "number" ] || { echo "Unknown JSON field: $json_fields" >&2; exit 1; }
  [ "$jq_expr" = "length" ] || { echo "expected --jq length, got: $jq_expr" >&2; exit 1; }
  { printf '['; i=0; while [ "$i" -lt "${STUB_OPEN:-0}" ]; do if [ "$i" -gt 0 ]; then printf ','; fi; printf '{"number":6}'; i=$((i+1)); done; printf ']'; } | jq -r "$jq_expr"
  exit 0;;
"pr view")
  [ "$json_fields" = "number,headRefOid" ] || { echo "Unknown JSON field: $json_fields" >&2; exit 1; }
  printf '{"number":6,"headRefOid":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}\n'; exit 0;;
*) exit 1;;
esac
EOF
printf '#!/bin/sh\nprintf "feat/test\\n"\n' > "${TEST_DIR}/stubbin-prc-resolve/git"
chmod +x "${TEST_DIR}/stubbin-prc-resolve/gh" "${TEST_DIR}/stubbin-prc-resolve/git"
cat > "${LOG_DIR}/prc-resolve-run.sh" <<'EOF'
set -u
. "$RW_LD/prc-resolve-omit.sh"
EOF
for n in 0 1 2; do
  run_split "prc-resolve-$n" env "RW_LD=${LOG_DIR}" "STUB_OPEN=$n" PATH="${TEST_DIR}/stubbin-prc-resolve:${PATH}" bash "${LOG_DIR}/prc-resolve-run.sh"
done
check "prc resolve zero refuses" test "$(cat "${LOG_DIR}/split-prc-resolve-0.rc")" = "1"
check "prc resolve one resolves" test "$(cat "${LOG_DIR}/split-prc-resolve-1.rc")" = "0"
check "prc resolve two refuses" test "$(cat "${LOG_DIR}/split-prc-resolve-2.rc")" = "1"
run_split poll-prc-empty env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "RW_SPAN=${LOG_DIR}/poll-prc.txt" "STUB_MODE=empty" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_COUNT=${TEST_DIR}/poll-count-prc" "STUB_VIEWS=${TEST_DIR}/poll-views-prc" PATH="${TEST_DIR}/stubbin-poll:${PATH}" bash "${LOG_DIR}/poll-run.sh"
check "poll prc span executes" grep -q 'reporting no-checks outcome' "${LOG_DIR}/split-poll-prc-empty.err"
sed -n '/# Resolve once/,/^printf .number:/p' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" | sed "s/'<pr_input>'/''/" > "${LOG_DIR}/resolve-omit.sh" || true
check "resolve omit extracted" grep -q 'open_count=' "${LOG_DIR}/resolve-omit.sh"
mkdir -p "${TEST_DIR}/stubbin-resolve"
cat > "${TEST_DIR}/stubbin-resolve/gh" <<'EOF'
#!/bin/sh
json_fields=""; jq_expr=""; prev=""
for a in "$@"; do case "$prev" in --json) json_fields="$a";; --jq) jq_expr="$a";; esac; prev="$a"; done
case "$1 $2" in
"pr list")
  [ "$json_fields" = "number" ] || { echo "Unknown JSON field: $json_fields" >&2; exit 1; }
  [ "$jq_expr" = "length" ] || { echo "expected --jq length, got: $jq_expr" >&2; exit 1; }
  { printf '['; i=0; while [ "$i" -lt "${STUB_OPEN:-0}" ]; do if [ "$i" -gt 0 ]; then printf ','; fi; printf '{"number":6}'; i=$((i+1)); done; printf ']'; } | jq -r "$jq_expr"
  exit 0;;
"pr view")
  [ "$json_fields" = "number,headRefOid,headRefName" ] || { echo "Unknown JSON field: $json_fields" >&2; exit 1; }
  printf '{"number":6,"headRefOid":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","headRefName":"feat/test"}\n'; exit 0;;
*) exit 1;;
esac
EOF
printf '#!/bin/sh\nprintf "feat/test\\n"\n' > "${TEST_DIR}/stubbin-resolve/git"
chmod +x "${TEST_DIR}/stubbin-resolve/gh" "${TEST_DIR}/stubbin-resolve/git"
cat > "${LOG_DIR}/resolve-run.sh" <<'EOF'
set -u
. "$RW_LD/resolve-omit.sh"
EOF
for n in 0 1 2; do
  run_split "resolve-$n" env "RW_LD=${LOG_DIR}" "STUB_OPEN=$n" PATH="${TEST_DIR}/stubbin-resolve:${PATH}" bash "${LOG_DIR}/resolve-run.sh"
done
check "resolve zero refuses" test "$(cat "${LOG_DIR}/split-resolve-0.rc")" = "1"
check "resolve zero names count" grep -q 'expected exactly one open PR' "${LOG_DIR}/split-resolve-0.err"
check "resolve one resolves" test "$(cat "${LOG_DIR}/split-resolve-1.rc")" = "0"
check "resolve one prints number" grep -q 'number: 6' "${LOG_DIR}/split-resolve-1.out"
check "resolve two refuses" test "$(cat "${LOG_DIR}/split-resolve-2.rc")" = "1"
run_split cci-checks-invalid env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_MODE=invalid" "STUB_SHA=$stub_sha" PATH="${TEST_DIR}/stubbin-cci-checks:${PATH}" bash "${LOG_DIR}/cci-checks-run.sh"
check "cci checks invalid rc" test "$(cat "${LOG_DIR}/split-cci-checks-invalid.rc")" = "1"
check "cci checks invalid names fetch" grep -q 'checks fetch failed' "${LOG_DIR}/split-cci-checks-invalid.err"

echo "--- 14. regen guards refuse bad trees ---"
regen_bundle() { # regen_bundle <tag>: fresh mini-bundle copy under TEST_DIR/regen-<tag>, prints its path
  local tag="$1" s
  local rb="${TEST_DIR}/regen-$tag"
  rm -rf "$rb"
  mkdir -p "$rb/skills" "$rb/tests/fixtures"
  for s in ${SKILLS}; do
    mkdir -p "$rb/skills/$s"
    cp "${BUNDLE}/skills/$s/SKILL.md" "$rb/skills/$s/SKILL.md"
  done
  cp "${BUNDLE}/tests/verify-install.sh" "$rb/tests/verify-install.sh"
  cp "${BUNDLE}/tests/fixtures/normalize.sed" "${BUNDLE}/tests/fixtures/bootstrap-golden.txt" "$rb/tests/fixtures/"
  cp "$rb/tests/fixtures/bootstrap-golden.txt" "$rb/tests/fixtures/bootstrap-golden.orig.txt"
  printf '%s' "$rb"
}
rb="$(regen_bundle clean)"
run_split regen-clean "$rb/tests/verify-install.sh" --regen-golden
check "regen clean exits 0" test "$(cat "${LOG_DIR}/split-regen-clean.rc")" = "0"
check "regen clean reports no changes" grep -q "(no changes)" "${LOG_DIR}/split-regen-clean.out"
check "regen clean stderr empty" test ! -s "${LOG_DIR}/split-regen-clean.err"
check "regen clean leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
rb="$(regen_bundle drift)"
st2=$(grep -n "$MIRROR_START" "$rb/skills/agent-review-loop/SKILL.md" | sed -n '2p' | cut -d: -f1 || true)
check "regen drift marker present" test -n "$st2"
if [ -n "$st2" ]; then
ins=$((st2+3))
{ head -n "$ins" "$rb/skills/agent-review-loop/SKILL.md"; echo "drift-marker-true"; tail -n "+$((ins+1))" "$rb/skills/agent-review-loop/SKILL.md"; } > "$rb/skills/agent-review-loop/SKILL.md.new" && mv "$rb/skills/agent-review-loop/SKILL.md.new" "$rb/skills/agent-review-loop/SKILL.md"
fi
run_split regen-drift "$rb/tests/verify-install.sh" --regen-golden
check "regen drifted exits 1" test "$(cat "${LOG_DIR}/split-regen-drift.rc")" = "1"
check "regen drifted stdout empty" test ! -s "${LOG_DIR}/split-regen-drift.out"
check "regen drifted names divergence" grep -q "diverges" "${LOG_DIR}/split-regen-drift.err"
check "regen drifted leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
rb="$(regen_bundle anchorless)"
grep -v "${lit_end}nd" "$rb/skills/agent-review-pr-comments/SKILL.md" > "$rb/skills/agent-review-pr-comments/SKILL.md.new" && mv "$rb/skills/agent-review-pr-comments/SKILL.md.new" "$rb/skills/agent-review-pr-comments/SKILL.md"
run_split regen-anchorless "$rb/tests/verify-install.sh" --regen-golden
check "regen anchorless exits 1" test "$(cat "${LOG_DIR}/split-regen-anchorless.rc")" = "1"
check "regen anchorless stdout empty" test ! -s "${LOG_DIR}/split-regen-anchorless.out"
check "regen anchorless names missing end" grep -q "missing end anchor" "${LOG_DIR}/split-regen-anchorless.err"
check "regen anchorless leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
rb="$(regen_bundle count)"
grep -v "${lit_start}straps" "$rb/skills/agent-review-report/SKILL.md" > "$rb/skills/agent-review-report/SKILL.md.new" && mv "$rb/skills/agent-review-report/SKILL.md.new" "$rb/skills/agent-review-report/SKILL.md"
run_split regen-count "$rb/tests/verify-install.sh" --regen-golden
check "regen wrong count exits 1" test "$(cat "${LOG_DIR}/split-regen-count.rc")" = "1"
check "regen wrong count stdout empty" test ! -s "${LOG_DIR}/split-regen-count.out"
check "regen wrong count names count" grep -q "expected 8 spans" "${LOG_DIR}/split-regen-count.err"
check "regen wrong count leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
rb="$(regen_bundle fixturesfile)"
rm -rf "$rb/tests/fixtures"
touch "$rb/tests/fixtures"
run_split regen-fixturesfile "$rb/tests/verify-install.sh" --regen-golden
check "regen fixtures-file exits 1" test "$(cat "${LOG_DIR}/split-regen-fixturesfile.rc")" = "1"
check "regen fixtures-file stdout empty" test ! -s "${LOG_DIR}/split-regen-fixturesfile.out"
check "regen fixtures-file names extraction failure" grep -q "span extraction failed" "${LOG_DIR}/split-regen-fixturesfile.err"
rb="$(regen_bundle badsed)"
printf 's/[oops\n' >> "$rb/tests/fixtures/normalize.sed"
run_split regen-badsed "$rb/tests/verify-install.sh" --regen-golden
check "regen bad-sed exits 1" test "$(cat "${LOG_DIR}/split-regen-badsed.rc")" = "1"
check "regen bad-sed names extraction failure" grep -q "span extraction failed" "${LOG_DIR}/split-regen-badsed.err"
check "regen bad-sed leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
check "regen bad-sed stdout empty" test ! -s "${LOG_DIR}/split-regen-badsed.out"
rb="$(regen_bundle midanchor)"
st1=$(grep -n "$MIRROR_START" "$rb/skills/agent-review-loop/SKILL.md" | sed -n '1p' | cut -d: -f1 || true)
en1=$(span_end "$st1" "$rb/skills/agent-review-loop/SKILL.md" || true)
check "regen midanchor start present" test -n "$st1"
check "regen midanchor end present" test -n "$en1"
if [ -n "$st1" ] && [ -n "$en1" ]; then
{ head -n "$((en1-1))" "$rb/skills/agent-review-loop/SKILL.md"; tail -n "+$((en1+1))" "$rb/skills/agent-review-loop/SKILL.md"; } > "$rb/skills/agent-review-loop/SKILL.md.new" && mv "$rb/skills/agent-review-loop/SKILL.md.new" "$rb/skills/agent-review-loop/SKILL.md"
fi
run_split regen-midanchor "$rb/tests/verify-install.sh" --regen-golden
check "regen middle-anchor-loss exits 1" test "$(cat "${LOG_DIR}/split-regen-midanchor.rc")" = "1"
check "regen middle-anchor-loss stdout empty" test ! -s "${LOG_DIR}/split-regen-midanchor.out"
check "regen middle-anchor-loss names missing end" grep -q "missing end anchor after line $st1" "${LOG_DIR}/split-regen-midanchor.err"
check "regen middle-anchor-loss leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
rb="$(regen_bundle nogolden)"
rm "$rb/tests/fixtures/bootstrap-golden.txt"
run_split regen-nogolden "$rb/tests/verify-install.sh" --regen-golden
check "regen missing golden exits 0" test "$(cat "${LOG_DIR}/split-regen-nogolden.rc")" = "0"
check "regen missing golden says new" grep -q "(new golden)" "${LOG_DIR}/split-regen-nogolden.out"
check "regen missing golden stderr empty" test ! -s "${LOG_DIR}/split-regen-nogolden.err"
check "regen missing golden content right" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
check "regen missing golden mode 644" test "$(stat -f %Lp "$rb/tests/fixtures/bootstrap-golden.txt" 2>/dev/null || stat -c %a "$rb/tests/fixtures/bootstrap-golden.txt")" = "644"
rb="$(regen_bundle update)"
for sf in "$rb/skills/agent-review-loop/SKILL.md" "$rb/skills/agent-review-report/SKILL.md" "$rb/skills/agent-review-pr-comments/SKILL.md" "$rb/skills/agent-review-check-ci/SKILL.md"; do
  awk -v me="$MIRROR_END" '{if (index($0, me)) print "# regen update waypoint"; print}' "$sf" > "$sf.new" && mv "$sf.new" "$sf"
done
check "regen update waypoint in all spans" test "$(grep -h -F 'regen update waypoint' "$rb/skills/agent-review-loop/SKILL.md" "$rb/skills/agent-review-report/SKILL.md" "$rb/skills/agent-review-pr-comments/SKILL.md" "$rb/skills/agent-review-check-ci/SKILL.md" | grep -c -F 'regen update waypoint' || true)" = "8"
run_split regen-update "$rb/tests/verify-install.sh" --regen-golden
check "regen update exits 0" test "$(cat "${LOG_DIR}/split-regen-update.rc")" = "0"
check "regen update prints diff" grep -q -F -- '--- golden diff (old -> new):' "${LOG_DIR}/split-regen-update.out"
check "regen update stderr empty" test ! -s "${LOG_DIR}/split-regen-update.err"
check "regen update golden carries waypoint" grep -q -F 'regen update waypoint' "$rb/tests/fixtures/bootstrap-golden.txt"
check "regen update golden mode 644" test "$(stat -f %Lp "$rb/tests/fixtures/bootstrap-golden.txt" 2>/dev/null || stat -c %a "$rb/tests/fixtures/bootstrap-golden.txt")" = "644"
run_split regen-update2 "$rb/tests/verify-install.sh" --regen-golden
check "regen update rerun exits 0" test "$(cat "${LOG_DIR}/split-regen-update2.rc")" = "0"
check "regen update rerun reports no changes" grep -q "(no changes)" "${LOG_DIR}/split-regen-update2.out"
mkdir -p "${TEST_DIR}/stubbin-failcp"
printf '#!/bin/sh\necho "STUB-CP-REFUSED" >&2\nexit 1\n' > "${TEST_DIR}/stubbin-failcp/cp"; chmod +x "${TEST_DIR}/stubbin-failcp/cp"
real_mktemp="$(command -v mktemp)"
rb="$(regen_bundle failcp)"
run_split regen-failcp env PATH="${TEST_DIR}/stubbin-failcp:${PATH}" bash "$rb/tests/verify-install.sh" --regen-golden
check "regen cp-fail exits 1" test "$(cat "${LOG_DIR}/split-regen-failcp.rc")" = "1"
check "regen cp-fail stdout empty" test ! -s "${LOG_DIR}/split-regen-failcp.out"
check "regen cp-fail names stage failure" grep -q "cannot stage golden temp" "${LOG_DIR}/split-regen-failcp.err"
check "regen cp-fail leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
check "regen cp-fail no leftovers" test -z "$(ls "$rb/tests/fixtures/.golden."* 2>/dev/null || true)"
rb="$(regen_bundle failchmod)"
mkdir -p "${TEST_DIR}/stubbin-failchmod"; printf '#!/bin/sh\nexit 1\n' > "${TEST_DIR}/stubbin-failchmod/chmod"; chmod +x "${TEST_DIR}/stubbin-failchmod/chmod"
run_split regen-failchmod env PATH="${TEST_DIR}/stubbin-failchmod:${PATH}" bash "$rb/tests/verify-install.sh" --regen-golden
check "regen chmod-fail exits 1" test "$(cat "${LOG_DIR}/split-regen-failchmod.rc")" = "1"
check "regen chmod-fail stdout empty" test ! -s "${LOG_DIR}/split-regen-failchmod.out"
check "regen chmod-fail names stage failure" grep -q "cannot set golden temp mode" "${LOG_DIR}/split-regen-failchmod.err"
check "regen chmod-fail leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
check "regen chmod-fail no leftovers" test -z "$(ls "$rb/tests/fixtures/.golden."* 2>/dev/null || true)"
rb="$(regen_bundle failmv)"
mkdir -p "${TEST_DIR}/stubbin-failmv"; printf '#!/bin/sh\nexit 1\n' > "${TEST_DIR}/stubbin-failmv/mv"; chmod +x "${TEST_DIR}/stubbin-failmv/mv"
run_split regen-failmv env PATH="${TEST_DIR}/stubbin-failmv:${PATH}" bash "$rb/tests/verify-install.sh" --regen-golden
check "regen mv-fail exits 1" test "$(cat "${LOG_DIR}/split-regen-failmv.rc")" = "1"
check "regen mv-fail reports no changes first" grep -q "(no changes)" "${LOG_DIR}/split-regen-failmv.out"
check "regen mv-fail names stage failure" grep -q "cannot write golden" "${LOG_DIR}/split-regen-failmv.err"
check "regen mv-fail leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
check "regen mv-fail no leftovers" test -z "$(ls "$rb/tests/fixtures/.golden."* 2>/dev/null || true)"
rb="$(regen_bundle failmktemp)"
mkdir -p "${TEST_DIR}/stubbin-failmktemp"
printf '#!/bin/sh\nif [ "$1" = "-d" ]; then echo "STUB-MKTEMP-REFUSED" >&2; exit 1; fi\nexec "%s" "$@"\n' "$real_mktemp" > "${TEST_DIR}/stubbin-failmktemp/mktemp"; chmod +x "${TEST_DIR}/stubbin-failmktemp/mktemp"
run_split regen-failmktemp env PATH="${TEST_DIR}/stubbin-failmktemp:${PATH}" bash "$rb/tests/verify-install.sh" --regen-golden
check "regen mktemp-fail exits 1" test "$(cat "${LOG_DIR}/split-regen-failmktemp.rc")" = "1"
check "regen mktemp-fail stdout empty" test ! -s "${LOG_DIR}/split-regen-failmktemp.out"
check "regen mktemp-fail names stage failure" grep -q "cannot create regen scratch" "${LOG_DIR}/split-regen-failmktemp.err"
check "regen mktemp-fail leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
rb="$(regen_bundle failgoldmk)"
mkdir -p "${TEST_DIR}/stubbin-failgoldmk"
printf '#!/bin/sh\ncase "$1" in *.golden.*) echo "STUB-GOLDEN-MKTEMP-REFUSED" >&2; exit 1;; esac\nexec "%s" "$@"\n' "$real_mktemp" > "${TEST_DIR}/stubbin-failgoldmk/mktemp"; chmod +x "${TEST_DIR}/stubbin-failgoldmk/mktemp"
run_split regen-failgoldmk env PATH="${TEST_DIR}/stubbin-failgoldmk:${PATH}" bash "$rb/tests/verify-install.sh" --regen-golden
check "regen golden-mktemp-fail exits 1" test "$(cat "${LOG_DIR}/split-regen-failgoldmk.rc")" = "1"
check "regen golden-mktemp-fail stdout empty" test ! -s "${LOG_DIR}/split-regen-failgoldmk.out"
check "regen golden-mktemp-fail names stage failure" grep -q "cannot create golden temp" "${LOG_DIR}/split-regen-failgoldmk.err"
check "regen golden-mktemp-fail leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
check "regen golden-mktemp-fail no leftovers" test -z "$(ls "$rb/tests/fixtures/.golden."* 2>/dev/null || true)"
sigleaks=0
# INT/QUIT are deliberately absent from the storm: backgrounded children ignore
# SIGINT/SIGQUIT on entry (POSIX), shells refuse to trap OR reset ignored-on-entry
# signals (probed: bg INT/QUIT kills always miss, and a trap-reset wrapper fails
# the same way), so a backgrounded storm can never land those kills. Their
# one-line traps stay covered by the int1/hup1/quit1 static pins plus
# identical-form uniformity with the storm-tested TERM/HUP traps.
for storm_sig in TERM HUP; do
  case "$storm_sig" in TERM) storm_want=143;; HUP) storm_want=129;; esac
  storm_landed=0
  storm_post_landed=0
  sigi=1
  while [ "$sigi" -le 10 ]; do
    rm -rf "${TEST_DIR}/sigtmp"; mkdir -p "${TEST_DIR}/sigtmp"
    rb="$(regen_bundle "sig${storm_sig}${sigi}")"
    TMPDIR="${TEST_DIR}/sigtmp" "$rb/tests/verify-install.sh" --regen-golden >"${LOG_DIR}/split-regen-sig.out" 2>"${LOG_DIR}/split-regen-sig.err" &
    sigpid=$!
    storm_poll=0
    while [ "$storm_poll" -lt 100 ] && [ -z "$(ls -A "${TEST_DIR}/sigtmp" 2>/dev/null || true)" ] && [ -z "$(ls "$rb/tests/fixtures/.golden."* 2>/dev/null || true)" ]; do
      sleep 0.01
      storm_poll=$((storm_poll+1))
    done
    storm_post=0
    if [ -n "$(ls -A "${TEST_DIR}/sigtmp" 2>/dev/null || true)" ] || [ -n "$(ls "$rb/tests/fixtures/.golden."* 2>/dev/null || true)" ]; then storm_post=1; fi
    kill "-$storm_sig" "$sigpid" 2>/dev/null || true
    storm_rc=0; wait "$sigpid" 2>/dev/null || storm_rc=$?
    if [ "$storm_rc" = "$storm_want" ]; then storm_landed=$((storm_landed+1)); if [ "$storm_post" = "1" ]; then storm_post_landed=$((storm_post_landed+1)); fi; fi
    if [ -n "$(ls -A "${TEST_DIR}/sigtmp" 2>/dev/null || true)" ] || [ -n "$(ls "$rb/tests/fixtures/.golden."* 2>/dev/null || true)" ]; then sigleaks=$((sigleaks+1)); fi
    sigi=$((sigi+1))
  done
  check "regen SIG${storm_sig} storm landed a kill" test "$storm_landed" -gt 0
  check "regen SIG${storm_sig} storm landed post-alloc kill" test "$storm_post_landed" -gt 0
done
check "regen signal storm leaves nothing" test "$sigleaks" = "0"
if [ "$(id -u)" = "0" ]; then
  echo "SKIP (root): regen unwritable-fixtures exits 1"
  pass=$((pass+1))
  echo "SKIP (root): regen unwritable-fixtures stdout empty"
  pass=$((pass+1))
  echo "SKIP (root): regen unwritable-fixtures names stage failure"
  pass=$((pass+1))
  echo "SKIP (root): regen unwritable-fixtures leaves golden untouched"
  pass=$((pass+1))
else
  rb="$(regen_bundle nowrite)"
  chmod a-w "$rb/tests/fixtures"
  run_split regen-nowrite "$rb/tests/verify-install.sh" --regen-golden
  chmod u+w "$rb/tests/fixtures"
  check "regen unwritable-fixtures exits 1" test "$(cat "${LOG_DIR}/split-regen-nowrite.rc")" = "1"
  check "regen unwritable-fixtures stdout empty" test ! -s "${LOG_DIR}/split-regen-nowrite.out"
  check "regen unwritable-fixtures names stage failure" grep -q "cannot create golden temp" "${LOG_DIR}/split-regen-nowrite.err"
  check "regen unwritable-fixtures leaves golden untouched" cmp "$rb/tests/fixtures/bootstrap-golden.orig.txt" "$rb/tests/fixtures/bootstrap-golden.txt"
fi

echo "--- 15. live-fire refusal paths ---"
mkdir -p "${TEST_DIR}/stubbin-dead" "${TEST_DIR}/stubbin-top" "${TEST_DIR}/tmp" "${TEST_DIR}/victim" "${TEST_DIR}/victim2" "${TEST_DIR}/stubtop" "${TEST_DIR}/tmpreal"
echo sentinel > "${TEST_DIR}/victim/sentinel"
echo sentinel2 > "${TEST_DIR}/victim2/sentinel2"
printf '#!/bin/sh\nexit 1\n' > "${TEST_DIR}/stubbin-dead/git"
printf '#!/bin/sh\nif [ "$1 $2" = "rev-parse --show-toplevel" ]; then echo "$STUB_TOPLEVEL"; exit 0; fi\nexit 1\n' > "${TEST_DIR}/stubbin-top/git"
chmod +x "${TEST_DIR}/stubbin-dead/git" "${TEST_DIR}/stubbin-top/git"
whoami_here="$(id -un 2>/dev/null || id -u 2>/dev/null || echo "uid${UID:-unknown}")"
tmpbase_here="$(cd "${TEST_DIR}/tmp" && pwd -P)"
ln -s "${TEST_DIR}/victim" "${tmpbase_here}/agent-tmp-${whoami_here}"
ln -s "${TEST_DIR}/victim2" "${TEST_DIR}/stubtop/.agent-tmp"
check_streams "live-fire fallback symlink refuses" 1 'fallback parent .* is a symlink; refusing' env TMPDIR="${TEST_DIR}/tmp" PATH="${TEST_DIR}/stubbin-dead:${PATH}" bash "${LOG_DIR}/bootstrap-1.raw.txt"
check_streams "live-fire run-root symlink refuses" 1 'run root .* is a symlink; refusing' env STUB_TOPLEVEL="${TEST_DIR}/stubtop" PATH="${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/bootstrap-1.raw.txt"
check "live-fire fallback victim intact" test -f "${TEST_DIR}/victim/sentinel"
check "live-fire run-root victim intact" test -f "${TEST_DIR}/victim2/sentinel2"
ln -s "${TEST_DIR}/tmpreal" "${TEST_DIR}/tmplink"
run_split live-tmplink env TMPDIR="${TEST_DIR}/tmplink" PATH="${TEST_DIR}/stubbin-dead:${PATH}" bash "${LOG_DIR}/bootstrap-1.raw.txt"
check "live-fire tmplink succeeds" test "$(cat "${LOG_DIR}/split-live-tmplink.rc")" = "0"
check "live-fire tmplink stdout empty" test ! -s "${LOG_DIR}/split-live-tmplink.out"
check "live-fire tmplink lands under real path" test -d "${TEST_DIR}/tmpreal/agent-tmp-${whoami_here}/.agent-tmp"
check_streams "live-fire unresolvable tmpdir refuses" 1 'cannot resolve TMPDIR' env TMPDIR="${TEST_DIR}/does-not-exist" PATH="${TEST_DIR}/stubbin-dead:${PATH}" bash "${LOG_DIR}/bootstrap-1.raw.txt"
check_streams "live-fire relative tmpdir refuses" 1 'is not absolute; refusing' env TMPDIR=relative/path PATH="${TEST_DIR}/stubbin-dead:${PATH}" bash "${LOG_DIR}/bootstrap-1.raw.txt"
grep -F 'tmpbase=' "${LOG_DIR}/bootstrap-1.raw.txt" | head -n 2 > "${LOG_DIR}/tmpbase-lines.sh" || true
check "tmpbase lines extracted" test -s "${LOG_DIR}/tmpbase-lines.sh"
{ cat "${LOG_DIR}/tmpbase-lines.sh"; echo 'echo "TMPBASE=$tmpbase"'; } > "${LOG_DIR}/tmpbase-probe.sh"
run_split live-tmproot env TMPDIR=/ bash "${LOG_DIR}/tmpbase-probe.sh"
check "live-fire TMPDIR slash keeps root" grep -q 'TMPBASE=/$' "${LOG_DIR}/split-live-tmproot.out"
run_split live-tmpmissing env TMPDIR="${TEST_DIR}/does-not-exist" bash "${LOG_DIR}/tmpbase-probe.sh"
check "live-fire missing TMPDIR stays empty" grep -q 'TMPBASE=$' "${LOG_DIR}/split-live-tmpmissing.out"
run_split live-tmpsete env TMPDIR="${TEST_DIR}/does-not-exist" bash -e "${LOG_DIR}/tmpbase-probe.sh"
check "live-fire missing TMPDIR set-e rc" test "$(cat "${LOG_DIR}/split-live-tmpsete.rc")" = "0"
check "live-fire missing TMPDIR set-e stays empty" grep -q 'TMPBASE=$' "${LOG_DIR}/split-live-tmpsete.out"
mkdir -p "${TEST_DIR}/tmp755"
tmpbase755="$(cd "${TEST_DIR}/tmp755" && pwd -P)"
mkdir -p "${tmpbase755}/agent-tmp-${whoami_here}"
chmod 755 "${tmpbase755}/agent-tmp-${whoami_here}"
run_split live-repair env TMPDIR="${TEST_DIR}/tmp755" PATH="${TEST_DIR}/stubbin-dead:${PATH}" bash "${LOG_DIR}/bootstrap-1.raw.txt"
check "live-fire 755 repair succeeds" test "$(cat "${LOG_DIR}/split-live-repair.rc")" = "0"
check "live-fire 755 repaired to 700" test "$(stat -f %Lp "${tmpbase755}/agent-tmp-${whoami_here}" 2>/dev/null || stat -c %a "${tmpbase755}/agent-tmp-${whoami_here}")" = "700"
realuid_here="$(id -u)"
mkdir -p "${TEST_DIR}/stubbin-partid" "${TEST_DIR}/tmpnoid"
printf '#!/bin/sh\nif [ "$1" = "-un" ]; then exit 1; fi\necho "%s"\n' "$realuid_here" > "${TEST_DIR}/stubbin-partid/id"; chmod +x "${TEST_DIR}/stubbin-partid/id"
printf '#!/bin/sh\nexit 1\n' > "${TEST_DIR}/stubbin-partid/git"; chmod +x "${TEST_DIR}/stubbin-partid/git"
run_split live-uid env TMPDIR="${TEST_DIR}/tmpnoid" PATH="${TEST_DIR}/stubbin-partid:/usr/bin:/bin" bash "${LOG_DIR}/bootstrap-1.raw.txt"
check "live-fire uid fallback succeeds" test "$(cat "${LOG_DIR}/split-live-uid.rc")" = "0"
check "live-fire uid fallback names numerically" test -d "${TEST_DIR}/tmpnoid/agent-tmp-${realuid_here}/.agent-tmp"
mkdir -p "${TEST_DIR}/stubbin-noid" "${TEST_DIR}/tmpnoid2"
printf '#!/bin/sh\nexit 127\n' > "${TEST_DIR}/stubbin-noid/id"; chmod +x "${TEST_DIR}/stubbin-noid/id"
printf '#!/bin/sh\nexit 1\n' > "${TEST_DIR}/stubbin-noid/git"; chmod +x "${TEST_DIR}/stubbin-noid/git"
run_split live-uid2 env TMPDIR="${TEST_DIR}/tmpnoid2" PATH="${TEST_DIR}/stubbin-noid:/usr/bin:/bin" bash "${LOG_DIR}/bootstrap-1.raw.txt"
check "live-fire double-id-fail succeeds" test "$(cat "${LOG_DIR}/split-live-uid2.rc")" = "0"
check "live-fire double-id-fail names uid" test -d "${TEST_DIR}/tmpnoid2/agent-tmp-uid${UID:-unknown}/.agent-tmp"
if [ "$(id -u)" = "0" ]; then
  echo "SKIP (root): live-fire unwritable toplevel falls back"
  pass=$((pass+1))
  echo "SKIP (root): live-fire unwritable toplevel stdout empty"
  pass=$((pass+1))
  echo "SKIP (root): live-fire unwritable toplevel notices"
  pass=$((pass+1))
  echo "SKIP (root): live-fire unwritable toplevel lands under TMPDIR"
  pass=$((pass+1))
else
  mkdir -p "${TEST_DIR}/ro-top" "${TEST_DIR}/tmprotop"
  chmod a-w "${TEST_DIR}/ro-top"
  tmpbase_ro="$(cd "${TEST_DIR}/tmprotop" && pwd -P)"
  run_split live-rotop env STUB_TOPLEVEL="${TEST_DIR}/ro-top" TMPDIR="${TEST_DIR}/tmprotop" PATH="${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/bootstrap-1.raw.txt"
  check "live-fire unwritable toplevel falls back" test "$(cat "${LOG_DIR}/split-live-rotop.rc")" = "0"
  check "live-fire unwritable toplevel stdout empty" test ! -s "${LOG_DIR}/split-live-rotop.out"
  check "live-fire unwritable toplevel notices" grep -q -F 'unusable (unwritable or foreign-owned); using per-user TMPDIR fallback' "${LOG_DIR}/split-live-rotop.err"
  check "live-fire unwritable toplevel lands under TMPDIR" test -d "${tmpbase_ro}/agent-tmp-${whoami_here}/.agent-tmp"
  chmod u+w "${TEST_DIR}/ro-top"
fi
mkdir -p "${TEST_DIR}/top755/.agent-tmp"
chmod 755 "${TEST_DIR}/top755/.agent-tmp"
top755canon="$(cd "${TEST_DIR}/top755" && pwd -P)"
run_split live-rootrepair env STUB_TOPLEVEL="${TEST_DIR}/top755" TMPDIR="${TEST_DIR}/tmp" PATH="${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/bootstrap-1.raw.txt"
check "live-fire run-root 755 repair succeeds" test "$(cat "${LOG_DIR}/split-live-rootrepair.rc")" = "0"
check "live-fire run-root 755 repaired to 700" test "$(stat -f %Lp "${top755canon}/.agent-tmp" 2>/dev/null || stat -c %a "${top755canon}/.agent-tmp")" = "700"
if command -v git >/dev/null 2>&1 && git init -q "${TEST_DIR}/gittop" 2>/dev/null; then
  (cd "${TEST_DIR}/gittop" && run_split live-gitunset env GIT_DIR=/nonexistent GIT_WORK_TREE=/nonexistent TMPDIR="${TEST_DIR}/tmp" bash "${LOG_DIR}/bootstrap-1.raw.txt")
  check "live-fire bogus git env still succeeds" test "$(cat "${LOG_DIR}/split-live-gitunset.rc")" = "0"
  check "live-fire bogus git env stays repo-local" test -d "${TEST_DIR}/gittop/.agent-tmp"
else
  echo "SKIP (no git): live-fire bogus git env still succeeds"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire bogus git env stays repo-local"
  pass=$((pass+1))
fi
difffence_st=$(grep -n '^```bash$' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1 || true)
difffence_en=$(grep -n -F '[ -s "$diff_file" ]' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1 || true)
check "difffence start present" test -n "$difffence_st"
check "difffence end present" test -n "$difffence_en"
if [ -n "$difffence_st" ] && [ -n "$difffence_en" ]; then
sed -n "$((difffence_st+1)),${difffence_en}p" "${BUNDLE}/skills/agent-review-loop/SKILL.md" > "${LOG_DIR}/difffence.sh"
fi
check "live-fire difffence extracted" grep -q -F 'diff --no-ext-diff' "${LOG_DIR}/difffence.sh"
repwd_st=$(grep -n '^  ```bash$' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1 || true)
repwd_en=$(grep -n -F '[ -s "$diff_file" ]' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1 || true)
check "report difffence start present" test -n "$repwd_st"
check "report difffence end present" test -n "$repwd_en"
: > "${LOG_DIR}/repwd-fence.sh"
if [ -n "$repwd_st" ] && [ -n "$repwd_en" ]; then
sed -n "$((repwd_st+1)),${repwd_en}p" "${BUNDLE}/skills/agent-review-report/SKILL.md" > "${LOG_DIR}/repwd-fence.sh"
fi
check "report difffence extracted" grep -q -F 'diff --no-ext-diff' "${LOG_DIR}/repwd-fence.sh"
check "report difffence parses" bash -n "${LOG_DIR}/repwd-fence.sh"
prfence_st=$(grep -n '^  ```bash$' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | sed -n '2p' || true)
prfence_en=$(grep -n -F 'sha_after=$(gh pr view' "${BUNDLE}/skills/agent-review-report/SKILL.md" | cut -d: -f1 | head -n 1 || true)
check "pr fence start present" test -n "$prfence_st"
check "pr fence end present" test -n "$prfence_en"
: > "${LOG_DIR}/pr-fence.sh"
if [ -n "$prfence_st" ] && [ -n "$prfence_en" ]; then
sed -n "$((prfence_st+1)),${prfence_en}p" "${BUNDLE}/skills/agent-review-report/SKILL.md" > "${LOG_DIR}/pr-fence.sh"
fi
check "pr fence extracted" grep -q -F "gh pr view '<pr_input>'" "${LOG_DIR}/pr-fence.sh"
check "pr fence parses" bash -n "${LOG_DIR}/pr-fence.sh"
if command -v git >/dev/null 2>&1 && git init -q "${TEST_DIR}/difftop" 2>/dev/null && git -C "${TEST_DIR}/difftop" config user.email t@t 2>/dev/null && git -C "${TEST_DIR}/difftop" config user.name t 2>/dev/null && echo a > "${TEST_DIR}/difftop/f" && git -C "${TEST_DIR}/difftop" add f 2>/dev/null && git -C "${TEST_DIR}/difftop" commit -qm init >/dev/null 2>&1 && echo b > "${TEST_DIR}/difftop/f"; then
  printf '#!/bin/sh\necho FIRED > "$RW_TD/trip-ext"\n' > "${TEST_DIR}/trip-ext.sh"; chmod +x "${TEST_DIR}/trip-ext.sh"
  printf '#!/bin/sh\necho FIRED > "$RW_TD/trip-fsmon"\n' > "${TEST_DIR}/trip-fsmon.sh"; chmod +x "${TEST_DIR}/trip-fsmon.sh"
  printf '#!/bin/sh\necho FIRED > "$RW_TD/trip-cfg"\n' > "${TEST_DIR}/trip-cfg.sh"; chmod +x "${TEST_DIR}/trip-cfg.sh"
  printf '#!/bin/sh\necho FIRED > "$RW_TD/trip-glob"\n' > "${TEST_DIR}/trip-glob.sh"; chmod +x "${TEST_DIR}/trip-glob.sh"
  printf '[diff]\n\texternal = %s/trip-cfg.sh\n[core]\n\tfsmonitor = %s/trip-glob.sh\n' "${TEST_DIR}" "${TEST_DIR}" > "${TEST_DIR}/hostile.gitconfig"
  (cd "${TEST_DIR}/difftop" && run_split live-hostilediff env "RW_TD=${TEST_DIR}" GIT_EXTERNAL_DIFF="${TEST_DIR}/trip-ext.sh" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0="${TEST_DIR}/trip-fsmon.sh" GIT_CONFIG_GLOBAL="${TEST_DIR}/hostile.gitconfig" TMPDIR="${TEST_DIR}/tmp" bash "${LOG_DIR}/difffence.sh")
  check "live-fire hostile diff env rc" test "$(cat "${LOG_DIR}/split-live-hostilediff.rc")" = "0"
  check "live-fire hostile ext-diff silent" test ! -e "${TEST_DIR}/trip-ext"
  check "live-fire hostile fsmonitor silent" test ! -e "${TEST_DIR}/trip-fsmon"
  check "live-fire hostile config silent" test ! -e "${TEST_DIR}/trip-cfg"
  # Combination pin: ext-diff silence needs --no-ext-diff (full diff never
  # invokes drivers) AND the env unsets; only the fsmonitor wires below pin
  # the unsets/hygiene behaviorally, since --quiet never invokes drivers.
  check "live-fire hostile global-fsmonitor silent" test ! -e "${TEST_DIR}/trip-glob"
  check "live-fire difffence toplevel single line" test "$(grep -c '' "${LOG_DIR}/split-live-hostilediff.out" || true)" = "1"
  check "live-fire difffence toplevel value exact" test "$(cat "${LOG_DIR}/split-live-hostilediff.out")" = "toplevel=$(git -C "${TEST_DIR}/difftop" rev-parse --show-toplevel)"
  check "live-fire difffence toplevel re-attaches" test -d "$(grep '^toplevel=' "${LOG_DIR}/split-live-hostilediff.out" | cut -d= -f2- || true)"
  # Cap path (COUNT parses, exceeds 128): loop runs capped, KEY_0 cleared.
  rm -f "${TEST_DIR}/trip-fsmon"
  (cd "${TEST_DIR}/difftop" && run_split live-capcount env "RW_TD=${TEST_DIR}" GIT_CONFIG_COUNT=1000 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0="${TEST_DIR}/trip-fsmon.sh" TMPDIR="${TEST_DIR}/tmp" bash "${LOG_DIR}/difffence.sh")
  check "live-fire capped COUNT rc" test "$(cat "${LOG_DIR}/split-live-capcount.rc")" = "0"
  check "live-fire capped COUNT silent" test ! -e "${TEST_DIR}/trip-fsmon"
  # Overflow path (20-digit COUNT fails the parse): skipped quietly, COUNT unset.
  rm -f "${TEST_DIR}/trip-fsmon"
  (cd "${TEST_DIR}/difftop" && run_split live-bigcount env "RW_TD=${TEST_DIR}" GIT_CONFIG_COUNT=99999999999999999999 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0="${TEST_DIR}/trip-fsmon.sh" TMPDIR="${TEST_DIR}/tmp" bash "${LOG_DIR}/difffence.sh")
  check "live-fire giant COUNT rc" test "$(cat "${LOG_DIR}/split-live-bigcount.rc")" = "0"
  check "live-fire giant COUNT silent" test ! -e "${TEST_DIR}/trip-fsmon"
  # Quiet-skip path (non-numeric COUNT): skipped quietly, stderr clean.
  rm -f "${TEST_DIR}/trip-fsmon"
  (cd "${TEST_DIR}/difftop" && run_split live-nancount env "RW_TD=${TEST_DIR}" GIT_CONFIG_COUNT=abc GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0="${TEST_DIR}/trip-fsmon.sh" TMPDIR="${TEST_DIR}/tmp" bash "${LOG_DIR}/difffence.sh")
  check "live-fire non-numeric COUNT rc" test "$(cat "${LOG_DIR}/split-live-nancount.rc")" = "0"
  check "live-fire non-numeric COUNT stderr empty" test ! -s "${LOG_DIR}/split-live-nancount.err"
  check "live-fire non-numeric COUNT silent" test ! -e "${TEST_DIR}/trip-fsmon"
  if git -C "${TEST_DIR}/difftop" commit -qam "clean for empty-diff legs" >/dev/null 2>&1 && git -C "${TEST_DIR}/difftop" update-ref refs/remotes/origin/main HEAD >/dev/null 2>&1 && git -C "${TEST_DIR}/difftop" diff --quiet HEAD -- 2>/dev/null; then
    rm -f "${TEST_DIR}"/difftop/.agent-tmp/agent-review-loop-diff.* "${TEST_DIR}"/difftop/.agent-tmp/agent-review-report-diff.*
    (cd "${TEST_DIR}/difftop" && run_split live-emptydiff env "RW_TD=${TEST_DIR}" TMPDIR="${TEST_DIR}/tmp" bash "${LOG_DIR}/difffence.sh")
    check "live-fire empty diff refuses" test "$(cat "${LOG_DIR}/split-live-emptydiff.rc")" = "1"
    check "live-fire empty diff names target" grep -q -F 'empty diff for' "${LOG_DIR}/split-live-emptydiff.err"
    check "live-fire empty diff removes scratch" test -z "$(ls "${TEST_DIR}"/difftop/.agent-tmp/agent-review-loop-diff.* 2>/dev/null || true)"
    (cd "${TEST_DIR}/difftop" && run_split live-repemptydiff env "RW_TD=${TEST_DIR}" TMPDIR="${TEST_DIR}/tmp" bash "${LOG_DIR}/repwd-fence.sh")
    check "live-fire report empty diff refuses" test "$(cat "${LOG_DIR}/split-live-repemptydiff.rc")" = "1"
    check "live-fire report empty diff names target" grep -q -F 'empty diff for' "${LOG_DIR}/split-live-repemptydiff.err"
    check "live-fire report empty diff removes scratch" test -z "$(ls "${TEST_DIR}"/difftop/.agent-tmp/agent-review-report-diff.* 2>/dev/null || true)"
  else
    echo "SKIP (dirty setup): live-fire empty diff refuses"
    pass=$((pass+1))
    echo "SKIP (dirty setup): live-fire empty diff names target"
    pass=$((pass+1))
    echo "SKIP (dirty setup): live-fire empty diff removes scratch"
    pass=$((pass+1))
    echo "SKIP (dirty setup): live-fire report empty diff refuses"
    pass=$((pass+1))
    echo "SKIP (dirty setup): live-fire report empty diff names target"
    pass=$((pass+1))
    echo "SKIP (dirty setup): live-fire report empty diff removes scratch"
    pass=$((pass+1))
  fi
  mkdir -p "${TEST_DIR}/stubbin-faildiff"
  cat > "${TEST_DIR}/stubbin-faildiff/git" <<'EOF'
#!/bin/sh
# Stub git: fail every diff subcommand, pass everything else to real git.
case "$1 $2" in
"diff "*|"--no-pager diff") exit 1;;
*) exec "${REALGIT:?}" "$@";;
esac
EOF
  chmod +x "${TEST_DIR}/stubbin-faildiff/git"
  rm -f "${TEST_DIR}"/difftop/.agent-tmp/agent-review-loop-diff.*
  (cd "${TEST_DIR}/difftop" && run_split live-difffail env "RW_TD=${TEST_DIR}" "REALGIT=$(command -v git)" TMPDIR="${TEST_DIR}/tmp" PATH="${TEST_DIR}/stubbin-faildiff:${PATH}" bash "${LOG_DIR}/difffence.sh")
  check "live-fire diff failure refuses" test "$(cat "${LOG_DIR}/split-live-difffail.rc")" = "1"
  check "live-fire diff failure names target" grep -q -F 'git diff failed for' "${LOG_DIR}/split-live-difffail.err"
  check "live-fire diff failure removes scratch" test -z "$(ls "${TEST_DIR}"/difftop/.agent-tmp/agent-review-loop-diff.* 2>/dev/null || true)"
else
  echo "SKIP (no git): live-fire hostile diff env rc"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire hostile ext-diff silent"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire hostile fsmonitor silent"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire hostile config silent"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire hostile global-fsmonitor silent"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire capped COUNT rc"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire capped COUNT silent"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire giant COUNT rc"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire giant COUNT silent"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire non-numeric COUNT rc"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire non-numeric COUNT stderr empty"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire non-numeric COUNT silent"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire difffence toplevel single line"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire difffence toplevel value exact"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire difffence toplevel re-attaches"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire diff failure refuses"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire diff failure names target"
  pass=$((pass+1))
  echo "SKIP (no git): live-fire diff failure removes scratch"
  pass=$((pass+1))
fi
mkdir -p "${TEST_DIR}/stubbin-ghok" "${TEST_DIR}/stubbin-ghfail" "${TEST_DIR}/prtop" "${TEST_DIR}/tmpprfail"
cat > "${TEST_DIR}/stubbin-ghok/gh" <<'EOF'
#!/bin/sh
# Stub gh for PR-fence live legs: canned number, SHA, and diff.
case "$1 $2" in
"pr view")
  case "$*" in
  *headRefOid*) echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"; exit 0;;
  *) echo "42"; exit 0;;
  esac;;
"pr diff") printf 'diff --git a/f b/f\n+stub\n'; exit 0;;
*) exit 1;;
esac
EOF
chmod +x "${TEST_DIR}/stubbin-ghok/gh"
cat > "${TEST_DIR}/stubbin-ghfail/gh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "${TEST_DIR}/stubbin-ghfail/gh"
sed "s|<pr_input>|42|g" "${LOG_DIR}/pr-fence.sh" > "${LOG_DIR}/pr-ok.sh" || true
run_split live-prok env STUB_TOPLEVEL="${TEST_DIR}/prtop" TMPDIR="${TEST_DIR}/tmp" PATH="${TEST_DIR}/stubbin-ghok:${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/pr-ok.sh"
check "live-fire PR fence succeeds" test "$(cat "${LOG_DIR}/split-live-prok.rc")" = "0"
check "live-fire PR fence fetches diff" test -n "$(ls "${TEST_DIR}"/prtop/.agent-tmp/agent-review-report-diff.* 2>/dev/null || true)"
check "live-fire PR fence stderr empty" test ! -s "${LOG_DIR}/split-live-prok.err"
sed "s|<pr_input>|42|g" "${LOG_DIR}/pr-fence.sh" > "${LOG_DIR}/pr-failview.sh" || true
check_streams "live-fire PR resolve refuses" 1 'gh pr view failed; check PR number or URL' env STUB_TOPLEVEL="${TEST_DIR}/prtopfail" TMPDIR="${TEST_DIR}/tmpprfail" PATH="${TEST_DIR}/stubbin-ghfail:${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/pr-failview.sh"
check "live-fire PR resolve allocates nothing" test -z "$(ls -A "${TEST_DIR}/tmpprfail" 2>/dev/null || true)"
grep -F 'pr_number="$(gh pr view' "${BUNDLE}/skills/agent-review-report/SKILL.md" > "${LOG_DIR}/pr-resolve-line.sh" || true
check "pr resolve line extracted" test -s "${LOG_DIR}/pr-resolve-line.sh"
check_streams "live-fire PR resolve fails clean under set -u" 1 'gh pr view failed; check PR number or URL' env PATH="${TEST_DIR}/stubbin-ghfail:${PATH}" bash -u "${LOG_DIR}/pr-resolve-line.sh"
hb_st=$(grep -n -F 'FRESH RUN ONLY' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | cut -d: -f1 | head -n 1 || true)
hb_en=$(awk -v s="$hb_st" 'NR>s && index($0,"rounds_dir=$rounds_dir"){print NR; exit}' "${BUNDLE}/skills/agent-review-loop/SKILL.md" || true)
check "heartbeat start present" test -n "$hb_st"
check "heartbeat end present" test -n "$hb_en"
if [ -z "$hb_st" ] || [ -z "$hb_en" ]; then hb_st=1; hb_en=1; fi
sed -n "${hb_st},${hb_en}p" "${BUNDLE}/skills/agent-review-loop/SKILL.md" > "${LOG_DIR}/heartbeat.raw.sh"
mkdir -p "${TEST_DIR}/hbtop" "${TEST_DIR}/hbtopwrong" "${TEST_DIR}/hbtmp"
hbcanon="$(cd "${TEST_DIR}/hbtop" && pwd -P)"
hbwrongcanon="$(cd "${TEST_DIR}/hbtopwrong" && pwd -P)"
hb_esc=$(hb_escape "$TEST_DIR")
meta_in="/tmp/mc&'a|b\\c"
meta_line=$(echo "v='TEMPLATE'" | sed "s|TEMPLATE|$(hb_escape "$meta_in")/hbtop|g")
meta_v=""; v=""
if eval "$meta_line" 2>/dev/null; then meta_v="$v"; fi; unset v
check "hb escape roundtrips metachars" test "$meta_v" = "$meta_in/hbtop"
escape_raw=$(grep -F 'root_base_safe="$(printf' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | head -n 1 || true)
check "escape line extracted" test -n "$escape_raw"
{ printf '%s\n' "root_base=\"/tmp/r15o'brien\""; printf '%s\n' "$escape_raw"; printf '%s\n' 'printf "%s\n" "$root_base_safe"'; } > "${LOG_DIR}/escape-probe.sh"
run_split live-escape bash "${LOG_DIR}/escape-probe.sh"
check "escape probe succeeds" test "$(cat "${LOG_DIR}/split-live-escape.rc")" = "0"
check "escape maps quote" test "$(cat "${LOG_DIR}/split-live-escape.out")" = "/tmp/r15o'\\''brien/.agent-tmp"
printf "ls '%s'\n" "$(cat "${LOG_DIR}/split-live-escape.out")" > "${LOG_DIR}/escape-use.sh"
check "escaped use site parses" bash -n "${LOG_DIR}/escape-use.sh"
sed "s|<toplevel-from-section-4>|${hb_esc}/hbtop|g" "${LOG_DIR}/heartbeat.raw.sh" > "${LOG_DIR}/heartbeat-match.sh"
run_split live-hbmatch env STUB_TOPLEVEL="${TEST_DIR}/hbtop" TMPDIR="${TEST_DIR}/hbtmp" PATH="${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/heartbeat-match.sh"
check "live-fire heartbeat match succeeds" test "$(cat "${LOG_DIR}/split-live-hbmatch.rc")" = "0"
check "live-fire heartbeat match allocates" test -n "$(ls -d "${hbcanon}"/.agent-tmp/agent-review-loop.?????? 2>/dev/null || true)"
check "live-fire heartbeat stdout is contract-only" test "$(grep -c -E '^(progress_dir|toplevel|rounds_dir)=' "${LOG_DIR}/split-live-hbmatch.out" || true)" = "3"
check "live-fire heartbeat stdout line count" test "$(grep -c '' "${LOG_DIR}/split-live-hbmatch.out" || true)" = "3"
check "live-fire heartbeat match stderr empty" test ! -s "${LOG_DIR}/split-live-hbmatch.err"
check "live-fire heartbeat progress re-attaches" test -d "$(grep '^progress_dir=' "${LOG_DIR}/split-live-hbmatch.out" | cut -d= -f2- || true)"
check "live-fire heartbeat rounds re-attaches" test -d "$(grep '^rounds_dir=' "${LOG_DIR}/split-live-hbmatch.out" | cut -d= -f2- || true)"
sed "s|<toplevel-from-section-4>|${hb_esc}/elsewhere|g" "${LOG_DIR}/heartbeat.raw.sh" > "${LOG_DIR}/heartbeat-wrong.sh"
check_streams "live-fire heartbeat drift refuses" 1 'toplevel drift' env STUB_TOPLEVEL="${TEST_DIR}/hbtopwrong" TMPDIR="${TEST_DIR}/hbtmp" PATH="${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/heartbeat-wrong.sh"
check "live-fire heartbeat drift leaks nothing" test -z "$(ls -A "${hbwrongcanon}/.agent-tmp" 2>/dev/null || true)"
mkdir -p "${TEST_DIR}/hbtop2" "${TEST_DIR}/hbvictim"; echo v > "${TEST_DIR}/hbvictim/sentinel"
hb2canon="$(cd "${TEST_DIR}/hbtop2" && pwd -P)"
mkdir -p "${hb2canon}/.agent-tmp"
ln -s "${TEST_DIR}/hbvictim" "${hb2canon}/.agent-tmp/agent-review-loop-rounds"
sed "s|<toplevel-from-section-4>|${hb_esc}/hbtop2|g" "${LOG_DIR}/heartbeat.raw.sh" > "${LOG_DIR}/heartbeat-link.sh"
run_split live-hblink env STUB_TOPLEVEL="${TEST_DIR}/hbtop2" TMPDIR="${TEST_DIR}/hbtmp" PATH="${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/heartbeat-link.sh"
check "live-fire heartbeat rounds-link refuses" test "$(cat "${LOG_DIR}/split-live-hblink.rc")" = "1"
check "live-fire heartbeat rounds-link names link" grep -q "rounds parent .* is a symlink; refusing" "${LOG_DIR}/split-live-hblink.err"
check "live-fire heartbeat rounds-link cleans progress" test "$(ls -A "${hb2canon}/.agent-tmp" 2>/dev/null || true)" = "agent-review-loop-rounds"
check "live-fire heartbeat rounds-link victim intact" test -f "${TEST_DIR}/hbvictim/sentinel"
mkdir -p "${TEST_DIR}/hbdrift"
sed "s|<toplevel-from-section-4>||g" "${LOG_DIR}/heartbeat.raw.sh" > "${LOG_DIR}/heartbeat-fbdrift.sh" || true
check_streams "live-fire heartbeat fallback-record drift refuses" 1 'toplevel drift' env STUB_TOPLEVEL="${TEST_DIR}/hbdrift" TMPDIR="${TEST_DIR}/hbtmp" PATH="${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/heartbeat-fbdrift.sh"
check "live-fire heartbeat fallback-record drift allocates nothing" test -z "$(ls -A "${TEST_DIR}/hbdrift" 2>/dev/null || true)"
if [ "$(id -u)" = "0" ]; then
  echo "SKIP (root): live-fire heartbeat fallback mode succeeds"
  pass=$((pass+1))
  echo "SKIP (root): live-fire heartbeat fallback mode allocates under TMPDIR"
  pass=$((pass+1))
  echo "SKIP (root): live-fire heartbeat fallback mode records empty toplevel"
  pass=$((pass+1))
else
  mkdir -p "${TEST_DIR}/hbro" "${TEST_DIR}/hbtmpfb"
  chmod a-w "${TEST_DIR}/hbro"
  tmpbase_hbfb="$(cd "${TEST_DIR}/hbtmpfb" && pwd -P)"
  sed "s|<toplevel-from-section-4>||g" "${LOG_DIR}/heartbeat.raw.sh" > "${LOG_DIR}/heartbeat-fbmode.sh" || true
  run_split live-hbfbmode env STUB_TOPLEVEL="${TEST_DIR}/hbro" TMPDIR="${TEST_DIR}/hbtmpfb" PATH="${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/heartbeat-fbmode.sh"
  check "live-fire heartbeat fallback mode succeeds" test "$(cat "${LOG_DIR}/split-live-hbfbmode.rc")" = "0"
  check "live-fire heartbeat fallback mode allocates under TMPDIR" test -n "$(ls -d "${tmpbase_hbfb}/agent-tmp-${whoami_here}/.agent-tmp/agent-review-loop."?????? 2>/dev/null || true)"
  check "live-fire heartbeat fallback mode records empty toplevel" grep -q '^toplevel=$' "${LOG_DIR}/split-live-hbfbmode.out"
  chmod u+w "${TEST_DIR}/hbro"
fi
mkdir -p "${TEST_DIR}/stubbin-chmodrounds" "${TEST_DIR}/hbchmod"
cat > "${TEST_DIR}/stubbin-chmodrounds/chmod" <<'EOF'
#!/bin/sh
# Stub chmod: refuse the rounds parent, pass everything else to real chmod.
case "$*" in
*/agent-review-loop-rounds) exit 1;;
*) exec "${REALCHMOD:?}" "$@";;
esac
EOF
chmod +x "${TEST_DIR}/stubbin-chmodrounds/chmod"
hbchmodcanon="$(cd "${TEST_DIR}/hbchmod" && pwd -P)"
sed "s|<toplevel-from-section-4>|${hb_esc}/hbchmod|g" "${LOG_DIR}/heartbeat.raw.sh" > "${LOG_DIR}/heartbeat-chmod.sh" || true
run_split live-hbchmod env STUB_TOPLEVEL="${TEST_DIR}/hbchmod" TMPDIR="${TEST_DIR}/hbtmp" "REALCHMOD=$(command -v chmod)" PATH="${TEST_DIR}/stubbin-chmodrounds:${TEST_DIR}/stubbin-top:${PATH}" bash "${LOG_DIR}/heartbeat-chmod.sh"
check "live-fire chmod-fail refuses" test "$(cat "${LOG_DIR}/split-live-hbchmod.rc")" = "1"
check "live-fire chmod-fail names parent" grep -q -F 'cannot chmod rounds parent' "${LOG_DIR}/split-live-hbchmod.err"
check "live-fire chmod-fail removes progress" test -z "$(ls -d "${hbchmodcanon}"/.agent-tmp/agent-review-loop.?????? 2>/dev/null || true)"
check "live-fire chmod-fail removes partial archive" test -z "$(ls -A "${hbchmodcanon}/.agent-tmp/agent-review-loop-rounds" 2>/dev/null || true)"
hb_hostile='h "x'"'"'y$z`w(a)b&c|d\e*f?g[h;i'
hb_hostile_esc=$(hb_escape "$hb_hostile")
hbpost_raw=$(grep -F 'toplevel drift: heartbeat ${toplevel' "${BUNDLE}/skills/agent-review-loop/SKILL.md" | head -n 1 || true)
check "postcheck echo line extracted" test -n "$hbpost_raw"
{ printf '%s\n' "_record='<HBPOST>'"; printf '%s\n' 'toplevel="nomatch"'; printf '%s\n' "$hbpost_raw"; } > "${LOG_DIR}/hb-postecho.tpl.sh"
sed "s|<HBPOST>|${hb_hostile_esc}|g" "${LOG_DIR}/hb-postecho.tpl.sh" > "${LOG_DIR}/hb-postecho.sh" || true
check "postcheck echo probe parses" bash -n "${LOG_DIR}/hb-postecho.sh"
run_split live-hbpostecho bash "${LOG_DIR}/hb-postecho.sh"
check "postcheck echo refuses mismatch" test "$(cat "${LOG_DIR}/split-live-hbpostecho.rc")" = "1"
check "postcheck echo stdout empty" test ! -s "${LOG_DIR}/split-live-hbpostecho.out"
check "postcheck echo prints record verbatim" grep -q -F "$hb_hostile" "${LOG_DIR}/split-live-hbpostecho.err"
sed "s|<toplevel-from-section-4>|${hb_hostile_esc}|g" "${LOG_DIR}/heartbeat.raw.sh" > "${LOG_DIR}/heartbeat-hostile.sh" || true
check "hostile record fence parses" bash -n "${LOG_DIR}/heartbeat-hostile.sh"

echo "--- 16. live-fire reaper matrix ---"
grep -F 'reaping stale run path' "${LOG_DIR}/bootstrap-1.raw.txt" | head -n 1 > "${LOG_DIR}/reapline1.sh" || true
grep -F 'reaping stale run archive' "${LOG_DIR}/bootstrap-1.raw.txt" | head -n 1 > "${LOG_DIR}/reapline2.sh" || true
check "reapline1 extracted" test -s "${LOG_DIR}/reapline1.sh"
check "reapline2 extracted" test -s "${LOG_DIR}/reapline2.sh"
mkdir -p "${TEST_DIR}/reap/agent-review-loop.old" "${TEST_DIR}/reap/agent-review-loop.live" "${TEST_DIR}/reap/agent-review-loop.locked/inner" "${TEST_DIR}/reap/agent-review-loop-rounds/agent-review-loop.old1" "${TEST_DIR}/reap/agent-review-loop-rounds/agent-review-loop.new1"
echo x > "${TEST_DIR}/reap/agent-review-loop.live/fresh.txt"
echo x > "${TEST_DIR}/reap/agent-review-loop.locked/inner/fresh.txt"
echo x > "${TEST_DIR}/reap/agent-review-loop.locked/old.txt"
echo x > "${TEST_DIR}/reap/agent-review-loop-rounds/agent-review-loop.new1/f.txt"
oldstamp=$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)
touch -t "$oldstamp" "${TEST_DIR}/reap/agent-review-loop.old" "${TEST_DIR}/reap/agent-review-loop.live" "${TEST_DIR}/reap/agent-review-loop.locked" "${TEST_DIR}/reap/agent-review-loop.locked/inner" "${TEST_DIR}/reap/agent-review-loop.locked/inner/fresh.txt" "${TEST_DIR}/reap/agent-review-loop.locked/old.txt" "${TEST_DIR}/reap/agent-review-loop-rounds" "${TEST_DIR}/reap/agent-review-loop-rounds/agent-review-loop.old1"
if [ "$(id -u)" != "0" ]; then chmod 000 "${TEST_DIR}/reap/agent-review-loop.locked/inner"; fi
run_split reap-top env "rootcanon=${TEST_DIR}/reap" bash "${LOG_DIR}/reapline1.sh"
check "reaper stale-empty reaped" test ! -e "${TEST_DIR}/reap/agent-review-loop.old"
check "reaper fresh spared" test -f "${TEST_DIR}/reap/agent-review-loop.live/fresh.txt"
if [ "$(id -u)" = "0" ]; then
  echo "SKIP (root): reaper unreadable spared"
  pass=$((pass+1))
  echo "SKIP (root): reaper locked sibling spared"
  pass=$((pass+1))
else
  chmod 755 "${TEST_DIR}/reap/agent-review-loop.locked/inner"
  check "reaper unreadable spared" test -f "${TEST_DIR}/reap/agent-review-loop.locked/inner/fresh.txt"
  check "reaper locked sibling spared" test -f "${TEST_DIR}/reap/agent-review-loop.locked/old.txt"
fi
check "reaper rounds parent spared" test -d "${TEST_DIR}/reap/agent-review-loop-rounds"
check "reaper top stdout empty" test ! -s "${LOG_DIR}/split-reap-top.out"
check "reaper top notice on stderr" grep -q "reaping stale run path" "${LOG_DIR}/split-reap-top.err"
run_split reap-arc env "rootcanon=${TEST_DIR}/reap" bash "${LOG_DIR}/reapline2.sh"
check "reaper stale archive reaped" test ! -e "${TEST_DIR}/reap/agent-review-loop-rounds/agent-review-loop.old1"
check "reaper fresh archive spared" test -f "${TEST_DIR}/reap/agent-review-loop-rounds/agent-review-loop.new1/f.txt"
check "reaper archive stdout empty" test ! -s "${LOG_DIR}/split-reap-arc.out"
check "reaper archive notice on stderr" grep -q "reaping stale run archive" "${LOG_DIR}/split-reap-arc.err"
check "reaper no err turds" test -z "$(ls "${TEST_DIR}"/reap/agent-review-loop-reap-err.* 2>/dev/null || true)"
mkdir -p "${TEST_DIR}/stubbin-failmk" "${TEST_DIR}/reap2"
printf '#!/bin/sh\nexit 1\n' > "${TEST_DIR}/stubbin-failmk/mktemp"; chmod +x "${TEST_DIR}/stubbin-failmk/mktemp"
mkdir -p "${TEST_DIR}/reap2/agent-review-loop.stale"
touch -t "$oldstamp" "${TEST_DIR}/reap2/agent-review-loop.stale"
run_split reap-mkfail env "rootcanon=${TEST_DIR}/reap2" PATH="${TEST_DIR}/stubbin-failmk:${PATH}" bash "${LOG_DIR}/reapline1.sh"
check "reaper mktemp-fail warns" grep -q "WARNING: cannot vet stale entry" "${LOG_DIR}/split-reap-mkfail.err"
check "reaper mktemp-fail skips" test -d "${TEST_DIR}/reap2/agent-review-loop.stale"
check "reaper mktemp-fail stdout empty" test ! -s "${LOG_DIR}/split-reap-mkfail.out"
echo data > "${TEST_DIR}/reap2/agent-review-loop-rounds"
touch -t "$oldstamp" "${TEST_DIR}/reap2/agent-review-loop-rounds"
run_split reap-file env "rootcanon=${TEST_DIR}/reap2" bash "${LOG_DIR}/reapline1.sh"
check "reaper rounds-named file reaped" test ! -e "${TEST_DIR}/reap2/agent-review-loop-rounds"
mkdir -p "${TEST_DIR}/reap3" "${TEST_DIR}/reap3victim"; echo v > "${TEST_DIR}/reap3victim/sentinel"
touch -t "$oldstamp" "${TEST_DIR}/reap3victim/sentinel"
ln -s "${TEST_DIR}/reap3victim" "${TEST_DIR}/reap3/agent-review-loop-rounds"
touch -h -t "$oldstamp" "${TEST_DIR}/reap3/agent-review-loop-rounds"
run_split reap-link env "rootcanon=${TEST_DIR}/reap3" bash "${LOG_DIR}/reapline1.sh"
check "reaper rounds-named link removed" test ! -L "${TEST_DIR}/reap3/agent-review-loop-rounds"
check "reaper link victim intact" test -f "${TEST_DIR}/reap3victim/sentinel"
if command -v dash >/dev/null 2>&1; then
  mkdir -p "${TEST_DIR}/dashtmp"
  dashbase="$(cd "${TEST_DIR}/dashtmp" && pwd -P)/agent-tmp-${whoami_here}/.agent-tmp"
  mkdir -p "${dashbase}/agent-review-loop.stale"
  touch -t "$oldstamp" "${dashbase}/agent-review-loop.stale"
  run_split live-dash env TMPDIR="${TEST_DIR}/dashtmp" PATH="${TEST_DIR}/stubbin-dead:${PATH}" dash "${LOG_DIR}/bootstrap-1.raw.txt"
  check "live-fire dash succeeds" test "$(cat "${LOG_DIR}/split-live-dash.rc")" = "0"
  check "live-fire dash warns reaping skip" grep -q "WARNING: skipping 7-day reaping" "${LOG_DIR}/split-live-dash.err"
  check "live-fire dash creates run root" test -d "${dashbase}"
  check "live-fire dash skips reaping" test -d "${dashbase}/agent-review-loop.stale"
else
  echo "SKIP (no dash): live-fire dash succeeds"
  pass=$((pass+1))
  echo "SKIP (no dash): live-fire dash warns reaping skip"
  pass=$((pass+1))
  echo "SKIP (no dash): live-fire dash creates run root"
  pass=$((pass+1))
  echo "SKIP (no dash): live-fire dash skips reaping"
  pass=$((pass+1))
fi

echo "--- 17. prc trap lifecycle ---"
awk '/^scratch_dir=""; rounds_dir=""$/{f=1} f{print} f&&/echo "toplevel=/{exit}' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/prc-setup.sh" || true
awk '/^trap - EXIT$/{f=1} f{print} f&&/rm -rf "/{exit}' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/prc-end.sh" || true
check "prc setup extracted" grep -q -F 'mktemp -d "$run_root/pr-comments' "${LOG_DIR}/prc-setup.sh"
check "prc setup has trap" grep -q "^trap '" "${LOG_DIR}/prc-setup.sh"
check "prc end extracted" grep -q -F 'trap - EXIT' "${LOG_DIR}/prc-end.sh"
cat > "${LOG_DIR}/prc-t1.sh" <<'EOF'
set -u
run_root="$RW_TD/prct1"; mkdir -p "$run_root"; toplevel="$RW_TD"
. "$RW_LD/prc-setup.sh" >/dev/null
touch "$rounds_dir/partial.json"
exit 1
EOF
run_split prc-t1 env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/prc-t1.sh"
check "prc trap failure rc" test "$(cat "${LOG_DIR}/split-prc-t1.rc")" = "1"
check "prc trap removes scratch on failure" test -z "$(ls -d "${TEST_DIR}"/prct1/pr-comments.?????? 2>/dev/null || true)"
check "prc trap removes partial rounds" test -z "$(ls "${TEST_DIR}"/prct1/pr-comments-rounds/*/partial.json 2>/dev/null || true)"
cat > "${LOG_DIR}/prc-t2.sh" <<'EOF'
set -u
run_root="$RW_TD/prct2"; mkdir -p "$run_root"; toplevel="$RW_TD"
rm -f "$RW_TD/prior-fired"
trap "touch \"\$RW_TD/prior-fired\"" EXIT
. "$RW_LD/prc-setup.sh" >/dev/null
exit 3
EOF
run_split prc-t2 env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/prc-t2.sh"
check "prc trap failure rc preserved" test "$(cat "${LOG_DIR}/split-prc-t2.rc")" = "3"
check "prc trap chains prior" test -f "${TEST_DIR}/prior-fired"
check "prc trap removes scratch with prior" test -z "$(ls -d "${TEST_DIR}"/prct2/pr-comments.?????? 2>/dev/null || true)"
cat > "${LOG_DIR}/prc-t3.sh" <<'EOF'
set -u
run_root="$RW_TD/prct3"; mkdir -p "$run_root"; toplevel="$RW_TD"
trap "echo prior" EXIT
. "$RW_LD/prc-setup.sh" >"$RW_TD/prct3-setup.out"
touch "$rounds_dir/summary.md"; rd="$rounds_dir"
. "$RW_LD/prc-end.sh" >/dev/null
[ -f "$rd/summary.md" ] && echo "ROUNDS_KEPT=yes"
[ -e "$run_root"/pr-comments.?????? ] && echo "SCRATCH_LEFT=yes" || echo "SCRATCH_GONE=yes"
trap -p EXIT
EOF
run_split prc-t3 env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/prc-t3.sh"
check "prc success rc" test "$(cat "${LOG_DIR}/split-prc-t3.rc")" = "0"
check "prc trap keeps rounds on success" grep -q "ROUNDS_KEPT=yes" "${LOG_DIR}/split-prc-t3.out"
check "prc trap removes scratch on success" grep -q "SCRATCH_GONE=yes" "${LOG_DIR}/split-prc-t3.out"
check "prc trap restores prior" grep -q "trap -- 'echo prior' EXIT" "${LOG_DIR}/split-prc-t3.out"
check "prc setup stdout is contract-only" test "$(grep -c -E '^(scratch_dir|rounds_dir|toplevel)=' "${TEST_DIR}/prct3-setup.out" || true)" = "3"
check "prc setup stdout line count" test "$(grep -c '' "${TEST_DIR}/prct3-setup.out" || true)" = "3"
check "prc setup rounds re-attaches" test -d "$(grep '^rounds_dir=' "${TEST_DIR}/prct3-setup.out" | cut -d= -f2- || true)"
awk '/^scratch_dir=""; rounds_dir=""$/{f=1} f{print} f&&/echo "toplevel=/{exit}' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/cci-setup.sh" || true
awk '/^trap - EXIT$/{f=1} f{print} f&&/rm -rf "/{exit}' "${BUNDLE}/skills/agent-review-check-ci/SKILL.md" > "${LOG_DIR}/cci-end.sh" || true
check "cci setup extracted" grep -q -F 'mktemp -d "$run_root/check-ci' "${LOG_DIR}/cci-setup.sh"
check "cci setup has trap" grep -q "^trap '" "${LOG_DIR}/cci-setup.sh"
check "cci end extracted" grep -q -F 'trap - EXIT' "${LOG_DIR}/cci-end.sh"
cat > "${LOG_DIR}/cci-t1.sh" <<'EOF'
set -u
run_root="$RW_TD/ccit1"; mkdir -p "$run_root"; toplevel="$RW_TD"
. "$RW_LD/cci-setup.sh" >/dev/null
touch "$rounds_dir/partial.json"
exit 1
EOF
run_split cci-t1 env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/cci-t1.sh"
check "cci trap failure rc" test "$(cat "${LOG_DIR}/split-cci-t1.rc")" = "1"
check "cci trap removes scratch on failure" test -z "$(ls -d "${TEST_DIR}"/ccit1/check-ci.?????? 2>/dev/null || true)"
check "cci trap removes partial rounds" test -z "$(ls "${TEST_DIR}"/ccit1/check-ci-rounds/*/partial.json 2>/dev/null || true)"
cat > "${LOG_DIR}/cci-t2.sh" <<'EOF'
set -u
run_root="$RW_TD/ccit2"; mkdir -p "$run_root"; toplevel="$RW_TD"
rm -f "$RW_TD/prior-fired-cci"
trap "touch \"\$RW_TD/prior-fired-cci\"" EXIT
. "$RW_LD/cci-setup.sh" >/dev/null
exit 3
EOF
run_split cci-t2 env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/cci-t2.sh"
check "cci trap failure rc preserved" test "$(cat "${LOG_DIR}/split-cci-t2.rc")" = "3"
check "cci trap chains prior" test -f "${TEST_DIR}/prior-fired-cci"
check "cci trap removes scratch with prior" test -z "$(ls -d "${TEST_DIR}"/ccit2/check-ci.?????? 2>/dev/null || true)"
cat > "${LOG_DIR}/cci-t3.sh" <<'EOF'
set -u
run_root="$RW_TD/ccit3"; mkdir -p "$run_root"; toplevel="$RW_TD"
trap "echo prior" EXIT
. "$RW_LD/cci-setup.sh" >"$RW_TD/ccit3-setup.out"
touch "$rounds_dir/summary.md"; rd="$rounds_dir"
. "$RW_LD/cci-end.sh" >/dev/null
[ -f "$rd/summary.md" ] && echo "ROUNDS_KEPT=yes"
[ -e "$run_root"/check-ci.?????? ] && echo "SCRATCH_LEFT=yes" || echo "SCRATCH_GONE=yes"
trap -p EXIT
EOF
run_split cci-t3 env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" bash "${LOG_DIR}/cci-t3.sh"
check "cci success rc" test "$(cat "${LOG_DIR}/split-cci-t3.rc")" = "0"
check "cci trap keeps rounds on success" grep -q "ROUNDS_KEPT=yes" "${LOG_DIR}/split-cci-t3.out"
check "cci trap removes scratch on success" grep -q "SCRATCH_GONE=yes" "${LOG_DIR}/split-cci-t3.out"
check "cci trap restores prior" grep -q "trap -- 'echo prior' EXIT" "${LOG_DIR}/split-cci-t3.out"
check "cci setup stdout is contract-only" test "$(grep -c -E '^(scratch_dir|rounds_dir|toplevel)=' "${TEST_DIR}/ccit3-setup.out" || true)" = "3"
check "cci setup stdout line count" test "$(grep -c '' "${TEST_DIR}/ccit3-setup.out" || true)" = "3"
check "cci setup rounds re-attaches" test -d "$(grep '^rounds_dir=' "${TEST_DIR}/ccit3-setup.out" | cut -d= -f2- || true)"
{
  echo '_prev_trap_line="trap -- '"'"'unclosed"'
  grep -F '_prev_body="${_prev_trap_line#trap -- }"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" || true
  echo '_prev_exit_trap=""'
  grep -F 'eval "_prev_exit_trap=$_prev_body"' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" || true
  echo '[ -z "$_prev_exit_trap" ] && echo "CHAIN_EMPTY=yes"'
} > "${LOG_DIR}/prc-warn.sh"
check "prc warn body extracted" grep -q -F '_prev_body=' "${LOG_DIR}/prc-warn.sh"
check "prc warn eval extracted" grep -q -F '_prev_exit_trap=$_prev_body' "${LOG_DIR}/prc-warn.sh"
run_split prc-warn bash "${LOG_DIR}/prc-warn.sh"
check "prc trap warn rc" test "$(cat "${LOG_DIR}/split-prc-warn.rc")" = "0"
check "prc trap warns unparseable body" grep -q "WARNING: cannot chain prior EXIT trap; dropping it" "${LOG_DIR}/split-prc-warn.err"
check "prc trap drops unparseable body" grep -q "CHAIN_EMPTY=yes" "${LOG_DIR}/split-prc-warn.out"
awk '/^if \[ -n "\$\{BASH_VERSION:-\}" \]; then$/{f=1} f{print} f&&/^fi$/{exit}' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/prc-gate.sh" || true
check "prc gate extracted" grep -q -F 'BASH_VERSION' "${LOG_DIR}/prc-gate.sh"
run_split prc-gate-bash bash "${LOG_DIR}/prc-gate.sh"
check "prc gate quiet under bash without prior" test "$(cat "${LOG_DIR}/split-prc-gate-bash.rc")" = "0"
check "prc gate bash stderr empty" test ! -s "${LOG_DIR}/split-prc-gate-bash.err"
if command -v dash >/dev/null 2>&1; then
  run_split prc-gate-dash dash "${LOG_DIR}/prc-gate.sh"
  check "prc gate dash rc" test "$(cat "${LOG_DIR}/split-prc-gate-dash.rc")" = "0"
  check "prc gate warns outside bash" grep -q "cannot chain prior EXIT trap outside bash" "${LOG_DIR}/split-prc-gate-dash.err"
else
  echo "SKIP (no dash): prc gate dash rc"
  pass=$((pass+1))
  echo "SKIP (no dash): prc gate warns outside bash"
  pass=$((pass+1))
fi

echo "--- 18. prc check-run annotations filter ---"
check "prc check-runs annotations_count: output nested" grep -q -F '.output.annotations_count' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
cat > "${LOG_DIR}/check-runs-sample.json" <<'EOF'
{
  "total_count": 3,
  "check_runs": [
    {
      "id": 101,
      "name": "lint-job",
      "annotations_count": null,
      "output": {
        "annotations_count": 2
      }
    },
    {
      "id": 102,
      "name": "test-job",
      "annotations_count": null,
      "output": {
        "annotations_count": 0
      }
    },
    {
      "id": 103,
      "name": "build-job",
      "annotations_count": null,
      "output": null
    },
    {
      "id": 104,
      "name": "legacy-job",
      "annotations_count": 3,
      "output": null
    }
  ]
}
EOF
prc_jq_expr="$(grep -o -E "jq -sr '[^']*check_runs[^']*'" "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" || true)"
check "prc check-runs selector extracted" test -n "$prc_jq_expr"
eval "${prc_jq_expr} \"${LOG_DIR}/check-runs-sample.json\"" > "${LOG_DIR}/check-runs-sample.out" 2>"${LOG_DIR}/check-runs-sample.err" || true
check "prc check-runs filter output non-empty" test -s "${LOG_DIR}/check-runs-sample.out"
check "prc check-runs filter extracts positive count" test "$(cat "${LOG_DIR}/check-runs-sample.out")" = "$(printf '101\tlint-job\t2\n104\tlegacy-job\t3')"
check "prc check-runs filter ignores zero count" test -z "$(grep '102' "${LOG_DIR}/check-runs-sample.out" || true)"
check "prc check-runs filter ignores null count" test -z "$(grep '103' "${LOG_DIR}/check-runs-sample.out" || true)"
check "prc annotations render pinned" grep -q -F 'ANNOTATION [\(.annotation_level // "notice")]' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
sed -n '/# Check-run annotations/,/re-run to re-triage/p' "${BUNDLE}/skills/agent-review-pr-comments/SKILL.md" > "${LOG_DIR}/prc-ann.sh" || true
check "prc annotations span extracted" grep -q -F 'fetched counts: annotations=' "${LOG_DIR}/prc-ann.sh"
mkdir -p "${TEST_DIR}/stubbin-prc-ann"
cat > "${TEST_DIR}/stubbin-prc-ann/gh" <<'EOF'
#!/bin/sh
if [ "$1" = "api" ]; then
  case "$3" in
    *"/check-runs") case "${STUB_ANN_MODE:-}" in badshape) printf '{"message":"Not Found"}\n';; badjson) printf 'not-json\n';; *) printf '{"total_count":1,"check_runs":[{"id":101,"name":"lint-job","output":{"annotations_count":2}}]}\n';; esac;;
    *"/annotations") case "${STUB_ANN_MODE:-}" in fetchfail) exit 1;; badann) printf '{"a":{"annotation_level":"warning","path":"x","start_line":1,"message":"m"}}\n';; *) printf '[{"annotation_level":"warning","path":"Sources/App.swift","start_line":42,"message":"unused variable"},{"annotation_level":"failure","path":"Sources/Main.swift","start_line":7,"message":"compile error"}]\n';; esac;;
    *) exit 1;;
  esac
  exit 0
fi
if [ "$1 $2" = "pr view" ]; then printf '%s\n' "${STUB_VIEW_SHA:?}"; exit 0; fi
exit 1
EOF
chmod +x "${TEST_DIR}/stubbin-prc-ann/gh"
cat > "${LOG_DIR}/prc-ann-run.sh" <<'EOF'
set -u
scratch_dir="$RW_TD/prc-ann-run"; mkdir -p "$scratch_dir"
pr_number=6; triage_sha="$STUB_SHA"
. "$RW_LD/prc-ann.sh"
EOF
run_split prc-ann-match env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_VIEW_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" PATH="${TEST_DIR}/stubbin-prc-ann:${PATH}" bash "${LOG_DIR}/prc-ann-run.sh"
check "prc annotations match rc" test "$(cat "${LOG_DIR}/split-prc-ann-match.rc")" = "0"
check "prc annotations rendered" grep -q -F 'ANNOTATION [warning] Sources/App.swift:42 by lint-job:' "${LOG_DIR}/split-prc-ann-match.out"
check "prc annotations counted" grep -q -F 'fetched counts: annotations=2' "${LOG_DIR}/split-prc-ann-match.out"
check "prc annotations render second" grep -q -F 'ANNOTATION [failure] Sources/Main.swift:7 by lint-job:' "${LOG_DIR}/split-prc-ann-match.out"
check "prc annotations render both" test "$(grep -c '^ANNOTATION ' "${LOG_DIR}/split-prc-ann-match.out" || true)" = "2"
run_split prc-ann-drift env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_VIEW_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" PATH="${TEST_DIR}/stubbin-prc-ann:${PATH}" bash "${LOG_DIR}/prc-ann-run.sh"
check "prc annotations drift rc" test "$(cat "${LOG_DIR}/split-prc-ann-drift.rc")" = "1"
check "prc annotations drift named" grep -q 'PR head moved during comment fetch' "${LOG_DIR}/split-prc-ann-drift.err"
for annmode in fetchfail badshape badjson badann; do
  run_split "prc-ann-$annmode" env "RW_TD=${TEST_DIR}" "RW_LD=${LOG_DIR}" "STUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_VIEW_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "STUB_ANN_MODE=$annmode" PATH="${TEST_DIR}/stubbin-prc-ann:${PATH}" bash "${LOG_DIR}/prc-ann-run.sh"
  check "prc annotations $annmode rc" test "$(cat "${LOG_DIR}/split-prc-ann-$annmode.rc")" = "1"
done
check "prc annotations fetchfail named" grep -q 'annotations fetch failed for check run 101' "${LOG_DIR}/split-prc-ann-fetchfail.err"
check "prc annotations badshape named" grep -q 'check-runs parse failed' "${LOG_DIR}/split-prc-ann-badshape.err"
check "prc annotations badjson named" grep -q 'check-runs parse failed' "${LOG_DIR}/split-prc-ann-badjson.err"
check "prc annotations badann named" grep -q 'annotations payload invalid for check run 101' "${LOG_DIR}/split-prc-ann-badann.err"

# Convergence features of agent-review-loop (section 5 protocol and section 2).
LOOP_SKILL="${BUNDLE}/skills/agent-review-loop/SKILL.md"
REPORT_SKILL="${BUNDLE}/skills/agent-review-report/SKILL.md"
for anchor in \
  '### Convergence phase and severity gate' \
  '### Finding provenance and the plateau rule' \
  '### Redundancy and the residual-defect estimate' \
  '### Effort routing per scope' \
  '#### Tooling ladder' \
  '#### Unreproduced findings' \
  '#### Coverage ledger and sharding' \
  '### Step 2b: Class sweep across scopes'; do
  check "convergence anchor: ${anchor}" grep -q -F -- "${anchor}" "${LOOP_SKILL}"
done
check "convergence: all-severities escape hatch" grep -q -F 'all-severities' "${LOOP_SKILL}"
check "convergence: gate severities named" grep -q -F '**Gate severities**: `bug`, `correctness`, and `convention`' "${LOOP_SKILL}"
check "convergence: backlog file named" grep -q -F '$rounds_dir/backlog.md' "${LOOP_SKILL}"
check "convergence: class ledger named" grep -q -F '$rounds_dir/classes.md' "${LOOP_SKILL}"
check "convergence: coverage ledger named" grep -q -F '$rounds_dir/coverage.tsv' "${LOOP_SKILL}"
check "convergence: sweeps file named" grep -q -F '$rounds_dir/sweeps.md' "${LOOP_SKILL}"
check "convergence: tools file named" grep -q -F '$rounds_dir/tools.md' "${LOOP_SKILL}"
check "convergence: Chapman estimate formula" grep -q -F 'N = (n1+1)(n2+1)/(m+1) - 1' "${LOOP_SKILL}"
check "convergence: Backlog Only class" grep -q -F '**Backlog Only**' "${LOOP_SKILL}"
check "convergence: plateau never finishes alone" grep -q -F 'Never finish on your own' "${LOOP_SKILL}"
check "convergence: step 6 lines present" test "$(grep -c -E '^- \*\*(Backlog|Provenance|Redundancy|Unreproduced|Sweeps|Routing)\*\*:' "${LOOP_SKILL}")" = "6"
check "convergence: evidence types in loop" grep -q -F '`trace` (an explicit' "${LOOP_SKILL}"
check "convergence: evidence types in report" grep -q -F '`trace` (an explicit' "${REPORT_SKILL}"
check "convergence: tool evidence mirrored in report" grep -q -F 'Tool evidence:' "${REPORT_SKILL}"
check "convergence: clean reports carry READ lines" grep -q -F 'returns `NO FINDINGS` followed by its' "${LOOP_SKILL}"
check "convergence: finish needs zero debt after READ merge" grep -q -F 'ended with zero coverage debt after its' "${LOOP_SKILL}"
check "convergence: reviewer limit is concurrency" grep -q -F 'at most 24 reviewers run at once' "${LOOP_SKILL}"
check "convergence: polish runs at most once" grep -q -F 'The polish pass runs' "${LOOP_SKILL}"
check "convergence: twin skipped without isolation" grep -q -F 'Redundancy: n/a (no' "${LOOP_SKILL}"
check "convergence: estimate only under redundancy 2" grep -q -F 'only when both sets ran unconditionally' "${LOOP_SKILL}"
check "convergence: clean round is never a plateau" grep -q -F 'A clean round is never a plateau' "${LOOP_SKILL}"
check "convergence: routing file named" grep -q -F '$rounds_dir/routing.md' "${LOOP_SKILL}"
check "convergence: backlog items never make a lens dirty" grep -q -F 'backlog-severity findings never make a lens dirty' "${LOOP_SKILL}"
check "convergence: commit invariant names plateau finish" grep -q -F 'user-approved' "${LOOP_SKILL}"
check "convergence: finding format has class in loop" grep -q -F 'class=<slug>' "${LOOP_SKILL}"
check "convergence: finding format has class in report" grep -q -F 'class=<slug>' "${REPORT_SKILL}"
check "convergence: ladder runs after run setup" grep -q -F 'After the run setup below (which creates `$rounds_dir`)' "${LOOP_SKILL}"
check "convergence: no em dash in loop skill" test "$(grep -c "$(printf '\342\200\224')" "${LOOP_SKILL}" || true)" = "0"
check "convergence: no em dash in report skill" test "$(grep -c "$(printf '\342\200\224')" "${REPORT_SKILL}" || true)" = "0"
check "convergence: pillar names untouched" test "$(grep -c -E '^[1-8]\. (Functional Correctness, Logic & Edge Cases|Security, Authentication & Input Sanitization|Concurrency, Asynchrony & Lifecycle Management|Error Handling, Resilience & Diagnostics|Interface Contracts, API Design & Compatibility|Performance, Resource Efficiency & Scalability|Code Simplification, Clean Architecture & Maintainability|Testing, Observability & Verification Invariants)$' "${LOOP_SKILL}")" = "8"

# Learnings slicing and bullet budget (token cost control).
PILLARS_FILE="${BUNDLE}/skills/agent-review-loop/thematic-review-pillars.md"
PRC_SKILL="${BUNDLE}/skills/agent-review-pr-comments/SKILL.md"
CHECKCI_SKILL="${BUNDLE}/skills/agent-review-check-ci/SKILL.md"
check "slicing: loop reviewers get own-pillar slices" grep -q -F 'only the learnings slices for its own pillars' "${LOOP_SKILL}"
check "slicing: report reviewers get own-pillar slices" grep -q -F 'only the learnings slices for its own pillars' "${REPORT_SKILL}"
check "slicing: loop hands a learnings titles index" grep -q -F 'learnings titles index' "${LOOP_SKILL}"
check "slicing: report hands a learnings titles index" grep -q -F 'learnings titles index' "${REPORT_SKILL}"
check "slicing: no whole-learnings instruction in loop" test "$(grep -c -F 'every shared learnings file that' "${LOOP_SKILL}" || true)" = "0"
check "slicing: no whole-learnings instruction in report" test "$(grep -c -F 'every shared learnings file that' "${REPORT_SKILL}" || true)" = "0"
check "slicing: pillars define the slicing rule" grep -q -F 'Slice learnings by pillar before spawning reviewers' "${PILLARS_FILE}"
check "concise: bullet budget in pillars" grep -q -F 'at or under 600 characters' "${PILLARS_FILE}"
check "concise: bullet budget in loop filing" grep -q -F 'at or under 600 characters' "${LOOP_SKILL}"
check "concise: bullet budget in report filing" grep -q -F 'at or under 600 characters' "${REPORT_SKILL}"
check "concise: bullet budget in pr-comments filing" grep -q -F 'at or under 600 characters' "${PRC_SKILL}"
check "concise: bullet budget in check-ci filing" grep -q -F 'at or under 600 characters' "${CHECKCI_SKILL}"

echo
echo "RESULT: ${pass} passed, ${fail} failed"
test "${fail}" = "0"

