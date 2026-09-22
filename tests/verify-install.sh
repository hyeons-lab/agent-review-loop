#!/usr/bin/env bash
# Installer verification using a fake HOME. Never touches the real home.
set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arl-verify-XXXXXX")"
cleanup() {
  if [ "${fail:-0}" -gt 0 ]; then
    echo "Verification failed (${fail} failure(s)). Retaining diagnostic logs in: ${LOG_DIR}"
  else
    rm -rf "${TEST_DIR}"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAKE="${TEST_DIR}/home"
LOG_DIR="${TEST_DIR}/logs"
mkdir -p "${FAKE}" "${LOG_DIR}"

export HOME="${FAKE}"
export XDG_CONFIG_HOME="${FAKE}/.config"
SKILLS="agent-review-loop agent-review-report address-pr-comments"

pass=0; fail=0
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
run_install() { # run_install <logfile> [args...]
  local log="$1"; shift
  if ! "${BUNDLE}/install.sh" "$@" > "${log}" 2>&1; then
    cat "${log}" >&2
    return 1
  fi
}
fresh_fake() { # reset the fake home between sections
  rm -rf "${FAKE}"
  mkdir -p "${FAKE}"
}

echo "--- 0. syntax ---"
check "bash -n" bash -n "${BUNDLE}/install.sh"
if command -v shellcheck >/dev/null; then
  if shellcheck -S warning "${BUNDLE}/install.sh"; then
    echo "PASS: shellcheck"
    pass=$((pass+1))
  else
    echo "FAIL: shellcheck reported warnings or errors"
    fail=$((fail+1))
  fi
else
  echo "SKIP: shellcheck not available"
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
check "installed files readable by non-owner" test -z "$(find "${FAKE}" -name "*.md" ! -perm -0444)"

echo "--- 2. re-run is fully unchanged ---"
check "re-run full install" run_install "${LOG_DIR}/rfl-run2.log"
if grep -qE "installed:|updated:|FAILED" "${LOG_DIR}/rfl-run2.log" || ! grep -q "unchanged" "${LOG_DIR}/rfl-run2.log"; then
  echo "FAIL: second run changed something:"; grep -E "installed:|updated:|FAILED" "${LOG_DIR}/rfl-run2.log"; fail=$((fail+1))
else
  echo "PASS: second run changed nothing"; pass=$((pass+1))
fi
check "all 35 files unchanged" test "$(grep -c "unchanged:" "${LOG_DIR}/rfl-run2.log")" = "35"

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
check "dry-run plans all 35 file installs" test "$(grep -c "\[dry-run\] install " "${LOG_DIR}/rfl-run7a.log")" = "35"
check "baseline install for populated dry-run" run_install "${LOG_DIR}/rfl-run7b.log"
check "dry-run on populated install" run_install "${LOG_DIR}/rfl-run7c.log" --dry-run
check "populated dry-run reports unchanged" grep -q "unchanged" "${LOG_DIR}/rfl-run7c.log"
check "populated dry-run has no pending changes" test "$(grep -c "\[dry-run\]" "${LOG_DIR}/rfl-run7c.log")" = "0"

echo "--- 8. no em dashes in bundle prose ---"
em_rc=0
grep -r "—" "${BUNDLE}" --exclude-dir=tests --exclude-dir=.git --exclude-dir=worktrees >/dev/null 2>&1 || em_rc=$?
if [ "${em_rc}" -eq 0 ]; then
  echo "FAIL: em dash found"
  grep -rn "—" "${BUNDLE}" --exclude-dir=tests --exclude-dir=.git --exclude-dir=worktrees
  fail=$((fail+1))
elif [ "${em_rc}" -eq 1 ]; then
  echo "PASS: no em dashes"
  pass=$((pass+1))
else
  echo "FAIL: grep error checking for em dashes (exit code ${em_rc})"
  fail=$((fail+1))
fi

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
rm -rf "${FAKE}/.claude/skills/address-pr-comments"
check "upgrade with skill removed" run_install "${LOG_DIR}/rfl-run9d.log" --upgrade --claude
check "upgrade adds no new skill" test ! -e "${FAKE}/.claude/skills/address-pr-comments"
check "upgrade keeps loop skill" test -f "${FAKE}/.claude/skills/agent-review-loop/SKILL.md"
check "upgrade keeps report skill" test -f "${FAKE}/.claude/skills/agent-review-report/SKILL.md"
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

echo
echo "RESULT: ${pass} passed, ${fail} failed"
test "${fail}" = "0"
