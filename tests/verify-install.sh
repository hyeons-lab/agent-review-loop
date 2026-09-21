#!/usr/bin/env bash
# Installer verification using a fake HOME. Never touches the real home.
set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE="${TMPDIR:-/tmp}/arl-test-home"

rm -rf "${FAKE}"
mkdir -p "${FAKE}"
export HOME="${FAKE}"
export XDG_CONFIG_HOME="${FAKE}/.config"
SKILLS="agent-review-loop address-pr-comments"

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
command -v shellcheck >/dev/null && shellcheck -S warning "${BUNDLE}/install.sh" && echo "PASS: shellcheck" && pass=$((pass+1)) || echo "(shellcheck not available or warnings above)"

echo "--- 1. fresh full install ---"
"${BUNDLE}/install.sh" > /tmp/rfl-run1.log 2>&1
cat /tmp/rfl-run1.log
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
"${BUNDLE}/install.sh" > /tmp/rfl-run2.log 2>&1
if grep -qE "installed:|updated:|FAILED" /tmp/rfl-run2.log || ! grep -q "unchanged" /tmp/rfl-run2.log; then
  echo "FAIL: second run changed something:"; grep -E "installed:|updated:|FAILED" /tmp/rfl-run2.log; fail=$((fail+1))
else
  echo "PASS: second run changed nothing"; pass=$((pass+1))
fi
grep -c "unchanged" /tmp/rfl-run2.log

echo "--- 3. learnings preserved across reinstall ---"
echo "- **Marker**: test bullet" >> "${FAKE}/.agents/review-refinements.md"
"${BUNDLE}/install.sh" > /tmp/rfl-run3.log 2>&1
check "marker survives" grep -q "Marker" "${FAKE}/.agents/review-refinements.md"
check "run3 reports kept" grep -q "kept existing" /tmp/rfl-run3.log

echo "--- 4. legacy file untouched, canonical seeded alongside ---"
rm -rf "${FAKE}/.agents/review-refinements.md"
mkdir -p "${FAKE}/.gemini"
echo "### Pillar 1: legacy" > "${FAKE}/.gemini/review-refinements.md"
"${BUNDLE}/install.sh" > /tmp/rfl-run4.log 2>&1
check "legacy untouched" grep -q "legacy" "${FAKE}/.gemini/review-refinements.md"
check "canonical seeded" grep -q "Shared Review Refinements" "${FAKE}/.agents/review-refinements.md"
check "legacy note printed" grep -q "legacy" /tmp/rfl-run4.log

echo "--- 5. selective install ---"
fresh_fake
"${BUNDLE}/install.sh" --claude --no-refinements > /tmp/rfl-run5.log 2>&1
check "claude installed" test -f "${FAKE}/.claude/skills/agent-review-loop/SKILL.md"
check "second skill installed" test -f "${FAKE}/.claude/skills/address-pr-comments/SKILL.md"
check "codex absent" test ! -e "${FAKE}/.codex/skills/agent-review-loop"
check "second skill absent" test ! -e "${FAKE}/.codex/skills/address-pr-comments"
check "refinements skipped" test ! -e "${FAKE}/.agents/review-refinements.md"

echo "--- 6. link mode + converge ---"
fresh_fake
"${BUNDLE}/install.sh" --link > /tmp/rfl-run6.log 2>&1
for s in ${SKILLS}; do
  check "canonical is real dir: $s" test -f "${FAKE}/.agents/skills/$s/SKILL.md"
  check "claude is symlink: $s" test -L "${FAKE}/.claude/skills/$s"
  check "link points at canonical: $s" test "$(readlink "${FAKE}/.claude/skills/$s")" = "${FAKE}/.agents/skills/$s"
done
"${BUNDLE}/install.sh" --link > /tmp/rfl-run6b.log 2>&1
check "link re-run unchanged" grep -q "unchanged" /tmp/rfl-run6b.log
"${BUNDLE}/install.sh" > /tmp/rfl-run6c.log 2>&1
for s in ${SKILLS}; do
  check "copy mode replaces links: $s" test ! -L "${FAKE}/.claude/skills/$s"
  check "copy mode file valid: $s" grep -qxF "name: $s" "${FAKE}/.claude/skills/$s/SKILL.md"
done

echo "--- 7. dry-run changes nothing ---"
fresh_fake
"${BUNDLE}/install.sh" --dry-run > /tmp/rfl-run7.log 2>&1
check "dry-run empty home" test -z "$(ls -A "${FAKE}")"

echo "--- 8. no em dashes in bundle prose ---"
if grep -r "—" "${BUNDLE}" --exclude-dir=tests >/dev/null 2>&1; then echo "FAIL: em dash found"; grep -rn "—" "${BUNDLE}" --exclude-dir=tests; fail=$((fail+1));
else echo "PASS: no em dashes"; pass=$((pass+1)); fi

echo "--- 9. upgrade refreshes skills, keeps learnings, skips missing ---"
fresh_fake
"${BUNDLE}/install.sh" --claude > /tmp/rfl-run9a.log 2>&1
echo "- **Marker**: upgrade bullet" >> "${FAKE}/.agents/review-refinements.md"
cp "${FAKE}/.agents/review-refinements.md" /tmp/rfl-before.md
for s in ${SKILLS}; do
  echo "stale" >> "${FAKE}/.claude/skills/$s/SKILL.md"
done
"${BUNDLE}/install.sh" --upgrade > /tmp/rfl-run9b.log 2>&1
for s in ${SKILLS}; do
  check "upgrade refreshes stale skill: $s" cmp -s "${BUNDLE}/skills/$s/SKILL.md" "${FAKE}/.claude/skills/$s/SKILL.md"
  check "upgrade skips missing target: $s" test ! -e "${FAKE}/.codex/skills/$s"
done
check "upgrade leaves refinements byte-identical" cmp -s /tmp/rfl-before.md "${FAKE}/.agents/review-refinements.md"
check "upgrade reports skip" grep -q "not installed, skipping" /tmp/rfl-run9b.log
for s in ${SKILLS}; do
  check "upgrade never installs missing canonical: $s" test ! -e "${FAKE}/.agents/skills/$s"
done
check "upgrade leaves refinements alone" grep -q "left untouched" /tmp/rfl-run9b.log
rm -rf "${FAKE}/.claude/skills/address-pr-comments"
"${BUNDLE}/install.sh" --upgrade --claude > /tmp/rfl-run9d.log 2>&1
check "upgrade adds no new skill" test ! -e "${FAKE}/.claude/skills/address-pr-comments"
check "upgrade keeps installed skill" test -f "${FAKE}/.claude/skills/agent-review-loop/SKILL.md"
rm "${FAKE}/.agents/review-refinements.md"
"${BUNDLE}/install.sh" --upgrade > /tmp/rfl-run9c.log 2>&1
check "upgrade never seeds refinements" test ! -e "${FAKE}/.agents/review-refinements.md"

echo "--- 10. upgrade respects linked installs ---"
fresh_fake
"${BUNDLE}/install.sh" --link > /tmp/rfl-run10a.log 2>&1
for s in ${SKILLS}; do
  echo "stale" >> "${FAKE}/.agents/skills/$s/SKILL.md"
done
"${BUNDLE}/install.sh" --upgrade > /tmp/rfl-run10b.log 2>&1
for s in ${SKILLS}; do
  check "upgrade refreshes canonical: $s" cmp -s "${BUNDLE}/skills/$s/SKILL.md" "${FAKE}/.agents/skills/$s/SKILL.md"
  check "upgrade leaves symlink: $s" test -L "${FAKE}/.claude/skills/$s"
done
check "upgrade reports link kept" grep -q "leaving in place" /tmp/rfl-run10b.log

echo "--- 11. upgrade ignores link flag ---"
fresh_fake
"${BUNDLE}/install.sh" --claude > /tmp/rfl-run11a.log 2>&1
"${BUNDLE}/install.sh" --upgrade --claude > /tmp/rfl-run11b.log 2>&1
fresh_fake
"${BUNDLE}/install.sh" --claude > /tmp/rfl-run11d.log 2>&1
"${BUNDLE}/install.sh" --upgrade --link --claude > /tmp/rfl-run11c.log 2>&1
check "upgrade ignores link note" grep -q "ignores --link" /tmp/rfl-run11c.log
check "link flag changes nothing under upgrade" cmp -s /tmp/rfl-run11b.log <(grep -v "ignores --link" /tmp/rfl-run11c.log)
check "upgrade covers canonical scope" grep -q ".agents/skills" /tmp/rfl-run11b.log
for s in ${SKILLS}; do
  check "upgrade never installs missing canonical: $s" test ! -e "${FAKE}/.agents/skills/$s"
  check "upgrade adds no new targets: $s" test ! -e "${FAKE}/.codex/skills/$s"
  check "upgrade keeps copy type: $s" test ! -L "${FAKE}/.claude/skills/$s"
done

echo
echo "RESULT: ${pass} passed, ${fail} failed"
test "${fail}" = "0"
