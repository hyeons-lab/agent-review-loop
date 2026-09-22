#!/usr/bin/env bash
# Installer verification using a fake HOME. Never touches the real home.
set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arl-verify-XXXXXX")"
trap 'rm -rf "${TEST_DIR}"' EXIT INT TERM
FAKE="${TEST_DIR}/home"
LOG_DIR="${TEST_DIR}/logs"
mkdir -p "${FAKE}" "${LOG_DIR}"

export HOME="${FAKE}"
export XDG_CONFIG_HOME="${FAKE}/.config"
SKILLS="agent-review-loop agent-review-report address-pr-comments"

pass=0; fail=0
check() { # check <desc> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "PASS: ${desc}"; pass=$((pass+1));
  else echo "FAIL: ${desc}"; fail=$((fail+1)); fi
}
fresh_fake() { # reset the fake home between sections
  rm -rf "${FAKE}"
  mkdir -p "${FAKE}"
}

echo "--- 0. syntax ---"
bash -n "${BUNDLE}/install.sh" && echo "PASS: bash -n" && pass=$((pass+1))
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
"${BUNDLE}/install.sh" > "${LOG_DIR}/rfl-run1.log" 2>&1
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

echo "--- 2. re-run is fully unchanged ---"
"${BUNDLE}/install.sh" > "${LOG_DIR}/rfl-run2.log" 2>&1 || true
if grep -qE "installed:|updated:|FAILED" "${LOG_DIR}/rfl-run2.log" || ! grep -q "unchanged" "${LOG_DIR}/rfl-run2.log"; then
  echo "FAIL: second run changed something:"; grep -E "installed:|updated:|FAILED" "${LOG_DIR}/rfl-run2.log"; fail=$((fail+1))
else
  echo "PASS: second run changed nothing"; pass=$((pass+1))
fi
check "all 35 files unchanged" test "$(grep -c "unchanged:" "${LOG_DIR}/rfl-run2.log")" = "35"

echo "--- 3. learnings preserved across reinstall ---"
echo "- **Marker**: test bullet" >> "${FAKE}/.agents/review-refinements.md"
"${BUNDLE}/install.sh" > "${LOG_DIR}/rfl-run3.log" 2>&1 || true
check "marker survives" grep -q "Marker" "${FAKE}/.agents/review-refinements.md"
check "run3 reports kept" grep -q "kept existing" "${LOG_DIR}/rfl-run3.log"

echo "--- 4. legacy file untouched, canonical seeded alongside ---"
rm -rf "${FAKE}/.agents/review-refinements.md"
mkdir -p "${FAKE}/.gemini"
echo "### Pillar 1: legacy" > "${FAKE}/.gemini/review-refinements.md"
"${BUNDLE}/install.sh" > "${LOG_DIR}/rfl-run4.log" 2>&1 || true
check "legacy untouched" test "$(< "${FAKE}/.gemini/review-refinements.md")" = "### Pillar 1: legacy"
check "canonical seeded" grep -q "Shared Review Refinements" "${FAKE}/.agents/review-refinements.md"
check "legacy note printed" grep -q "legacy" "${LOG_DIR}/rfl-run4.log"
check "legacy opt-in mentioned" grep -q "REVIEW_REFINEMENTS_LEGACY=1" "${LOG_DIR}/rfl-run4.log"

echo "--- 5. selective install ---"
fresh_fake
"${BUNDLE}/install.sh" --claude --no-refinements > "${LOG_DIR}/rfl-run5.log" 2>&1 || true
for s in ${SKILLS}; do
  check "selective install present: $s" test -f "${FAKE}/.claude/skills/$s/SKILL.md"
  check "selective install absent: $s" test ! -e "${FAKE}/.codex/skills/$s"
done
check "refinements skipped" test ! -e "${FAKE}/.agents/review-refinements.md"

echo "--- 6. link mode + converge ---"
fresh_fake
"${BUNDLE}/install.sh" --link > "${LOG_DIR}/rfl-run6.log" 2>&1 || true
for s in ${SKILLS}; do
  check "canonical is real dir: $s" test -f "${FAKE}/.agents/skills/$s/SKILL.md"
  check "claude is symlink: $s" test -L "${FAKE}/.claude/skills/$s"
  check "link points at canonical: $s" test "$(readlink "${FAKE}/.claude/skills/$s")" = "${FAKE}/.agents/skills/$s"
done
"${BUNDLE}/install.sh" --link > "${LOG_DIR}/rfl-run6b.log" 2>&1 || true
check "link re-run unchanged" grep -q "unchanged" "${LOG_DIR}/rfl-run6b.log"
check "link re-run no mutations" test "$(grep -cE "installed:|updated:|linked:|FAILED" "${LOG_DIR}/rfl-run6b.log")" = "0"
"${BUNDLE}/install.sh" > "${LOG_DIR}/rfl-run6c.log" 2>&1 || true
for s in ${SKILLS}; do
  check "copy mode replaces links: $s" test ! -L "${FAKE}/.claude/skills/$s"
  check "copy mode file valid: $s" grep -qxF "name: $s" "${FAKE}/.claude/skills/$s/SKILL.md"
done

echo "--- 7. dry-run changes nothing ---"
fresh_fake
"${BUNDLE}/install.sh" --dry-run > "${LOG_DIR}/rfl-run7.log" 2>&1 || true
check "dry-run empty home" test -z "$(ls -A "${FAKE}")"

echo "--- 8. no em dashes in bundle prose ---"
if grep -r "—" "${BUNDLE}" --exclude-dir=tests --exclude-dir=.git >/dev/null 2>&1; then echo "FAIL: em dash found"; grep -rn "—" "${BUNDLE}" --exclude-dir=tests --exclude-dir=.git; fail=$((fail+1));
else echo "PASS: no em dashes"; pass=$((pass+1)); fi

echo "--- 9. upgrade refreshes skills, keeps learnings, skips missing ---"
fresh_fake
"${BUNDLE}/install.sh" --claude > "${LOG_DIR}/rfl-run9a.log" 2>&1 || true
echo "- **Marker**: upgrade bullet" >> "${FAKE}/.agents/review-refinements.md"
cp "${FAKE}/.agents/review-refinements.md" "${LOG_DIR}/rfl-before.md"
for s in ${SKILLS}; do
  echo "stale" >> "${FAKE}/.claude/skills/$s/SKILL.md"
done
"${BUNDLE}/install.sh" --upgrade > "${LOG_DIR}/rfl-run9b.log" 2>&1 || true
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
"${BUNDLE}/install.sh" --upgrade --claude > "${LOG_DIR}/rfl-run9d.log" 2>&1 || true
check "upgrade adds no new skill" test ! -e "${FAKE}/.claude/skills/address-pr-comments"
check "upgrade keeps loop skill" test -f "${FAKE}/.claude/skills/agent-review-loop/SKILL.md"
check "upgrade keeps report skill" test -f "${FAKE}/.claude/skills/agent-review-report/SKILL.md"
rm "${FAKE}/.agents/review-refinements.md"
"${BUNDLE}/install.sh" --upgrade > "${LOG_DIR}/rfl-run9c.log" 2>&1 || true
check "upgrade never seeds refinements" test ! -e "${FAKE}/.agents/review-refinements.md"

echo "--- 10. upgrade respects linked installs ---"
fresh_fake
"${BUNDLE}/install.sh" --link > "${LOG_DIR}/rfl-run10a.log" 2>&1 || true
for s in ${SKILLS}; do
  echo "stale" >> "${FAKE}/.agents/skills/$s/SKILL.md"
done
"${BUNDLE}/install.sh" --upgrade > "${LOG_DIR}/rfl-run10b.log" 2>&1 || true
for s in ${SKILLS}; do
  check "upgrade refreshes canonical: $s" cmp -s "${BUNDLE}/skills/$s/SKILL.md" "${FAKE}/.agents/skills/$s/SKILL.md"
  check "upgrade leaves symlink: $s" test -L "${FAKE}/.claude/skills/$s"
done
check "upgrade reports link kept" grep -q "leaving in place" "${LOG_DIR}/rfl-run10b.log"

echo "--- 11. upgrade ignores link flag ---"
fresh_fake
"${BUNDLE}/install.sh" --claude > "${LOG_DIR}/rfl-run11a.log" 2>&1 || true
"${BUNDLE}/install.sh" --upgrade --claude > "${LOG_DIR}/rfl-run11b.log" 2>&1 || true
fresh_fake
"${BUNDLE}/install.sh" --claude > "${LOG_DIR}/rfl-run11d.log" 2>&1 || true
"${BUNDLE}/install.sh" --upgrade --link --claude > "${LOG_DIR}/rfl-run11c.log" 2>&1 || true
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
