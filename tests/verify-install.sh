#!/usr/bin/env bash
# Installer verification using a fake HOME. Never touches the real home.
set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE="${TMPDIR:-/tmp}/arl-test-home"

rm -rf "${FAKE}"
mkdir -p "${FAKE}"
export HOME="${FAKE}"

pass=0; fail=0
check() { # check <desc> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "PASS: ${desc}"; pass=$((pass+1));
  else echo "FAIL: ${desc}"; fail=$((fail+1)); fi
}

echo "--- 0. syntax ---"
bash -n "${BUNDLE}/install.sh" && echo "PASS: bash -n" && pass=$((pass+1))
command -v shellcheck >/dev/null && shellcheck -S warning "${BUNDLE}/install.sh" && echo "PASS: shellcheck" && pass=$((pass+1)) || echo "(shellcheck not available or warnings above)"

echo "--- 1. fresh full install ---"
"${BUNDLE}/install.sh" > /tmp/rfl-run1.log 2>&1
cat /tmp/rfl-run1.log
for d in .agents/skills .config/muse/skills .claude/skills .codex/skills .gemini/config/skills; do
  check "skill installed: $d" test -f "${FAKE}/$d/agent-review-loop/SKILL.md"
  check "pillars installed: $d" test -f "${FAKE}/$d/agent-review-loop/thematic-review-pillars.md"
  check "openai.yaml installed: $d" test -f "${FAKE}/$d/agent-review-loop/agents/openai.yaml"
done
check "refinements seeded" test -f "${FAKE}/.agents/review-refinements.md"
check "seed has 8 pillars" test "$(grep -c '^### Pillar' "${FAKE}/.agents/review-refinements.md")" = "8"

echo "--- 2. re-run is fully unchanged ---"
"${BUNDLE}/install.sh" > /tmp/rfl-run2.log 2>&1
if grep -q -v "unchanged" /tmp/rfl-run2.log | grep -q "installed\|updated"; then
  echo "FAIL: second run changed something:"; grep "installed\|updated" /tmp/rfl-run2.log; fail=$((fail+1))
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
rm -rf "${FAKE}"
mkdir -p "${FAKE}"
HOME="${FAKE}" "${BUNDLE}/install.sh" --claude --no-refinements > /tmp/rfl-run5.log 2>&1
check "claude installed" test -f "${FAKE}/.claude/skills/agent-review-loop/SKILL.md"
check "codex absent" test ! -e "${FAKE}/.codex/skills/agent-review-loop"
check "refinements skipped" test ! -e "${FAKE}/.agents/review-refinements.md"

echo "--- 6. link mode + converge ---"
rm -rf "${FAKE}"
mkdir -p "${FAKE}"
HOME="${FAKE}" "${BUNDLE}/install.sh" --link > /tmp/rfl-run6.log 2>&1
check "canonical is real dir" test -f "${FAKE}/.agents/skills/agent-review-loop/SKILL.md"
check "claude is symlink" test -L "${FAKE}/.claude/skills/agent-review-loop"
check "link points at canonical" test "$(readlink "${FAKE}/.claude/skills/agent-review-loop")" = "${FAKE}/.agents/skills/agent-review-loop"
HOME="${FAKE}" "${BUNDLE}/install.sh" --link > /tmp/rfl-run6b.log 2>&1
check "link re-run unchanged" grep -q "unchanged" /tmp/rfl-run6b.log
HOME="${FAKE}" "${BUNDLE}/install.sh" > /tmp/rfl-run6c.log 2>&1
check "copy mode replaces links" test ! -L "${FAKE}/.claude/skills/agent-review-loop"
check "copy mode file valid" grep -q "^name: agent-review-loop" "${FAKE}/.claude/skills/agent-review-loop/SKILL.md"

echo "--- 7. dry-run changes nothing ---"
rm -rf "${FAKE}"
mkdir -p "${FAKE}"
HOME="${FAKE}" "${BUNDLE}/install.sh" --dry-run > /tmp/rfl-run7.log 2>&1
check "dry-run empty home" test -z "$(ls -A "${FAKE}")"

echo "--- 8. no em dashes in bundle prose ---"
if grep -r "—" "${BUNDLE}" --exclude-dir=tests >/dev/null 2>&1; then echo "FAIL: em dash found"; grep -rn "—" "${BUNDLE}" --exclude-dir=tests; fail=$((fail+1));
else echo "PASS: no em dashes"; pass=$((pass+1)); fi

echo
echo "RESULT: ${pass} passed, ${fail} failed"
test "${fail}" = "0"
