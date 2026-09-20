#!/usr/bin/env bash
#
# Install the agent-review-loop skill for Muse, Claude Code, Codex,
# and Antigravity/Gemini, and seed the shared refinements file.
#
# Idempotent: re-running changes nothing when everything is current, and it
# never overwrites the shared refinements file once it exists.
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   --all             install to every target below (default)
#   --agents          install to ~/.agents/skills (canonical cross-agent store)
#   --muse            install to the Muse skills dir
#   --claude          install to ~/.claude/skills
#   --codex           install to ~/.codex/skills
#   --antigravity     install to the Antigravity/Gemini skills dir
#   --gemini          alias for --antigravity
#   --link            symlink agent dirs to the canonical copy instead of
#                     copying files (falls back to copying when linking fails)
#   --no-refinements  skip seeding ~/.agents/review-refinements.md
#   --dry-run         print what would change without changing anything
#   -h, --help        print this help and exit
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="agent-review-loop"
SKILL_SRC="${SCRIPT_DIR}/skills/${SKILL_NAME}"
TEMPLATE_SRC="${SCRIPT_DIR}/templates/review-refinements.template.md"

CANONICAL_SKILLS_DIR="${HOME}/.agents/skills"
CANONICAL_REFINEMENTS="${HOME}/.agents/review-refinements.md"
LEGACY_REFINEMENTS="${HOME}/.gemini/review-refinements.md"

SKILL_FILES="SKILL.md thematic-review-pillars.md agents/openai.yaml"

DRY_RUN=0
LINK_MODE=0
SEED_REFINEMENTS=1
TARGETS=""

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

log() {
  printf '%s\n' "$*"
}

install_file() {
  # install_file <src> <dest>: copy when missing or different; else report.
  local src="$1" dest="$2"
  if [ ! -f "${src}" ]; then
    log "ERROR: missing bundle file: ${src}"
    return 1
  fi
  if [ -L "${dest}" ]; then
    if [ "${DRY_RUN}" -eq 1 ]; then
      printf '[dry-run] replace symlink with file: %s\n' "${dest}"
    else
      log "  replace symlink with file: ${dest}"
      if rm "${dest}" && cp "${src}" "${dest}"; then
        printf '  updated: %s\n' "${dest}"
      else
        printf '  FAILED: %s\n' "${dest}"
        return 1
      fi
    fi
  elif [ ! -f "${dest}" ]; then
    if [ "${DRY_RUN}" -eq 1 ]; then
      printf '[dry-run] install %s\n' "${dest}"
    elif cp "${src}" "${dest}"; then
      printf '  installed: %s\n' "${dest}"
    else
      printf '  FAILED: %s\n' "${dest}"
      return 1
    fi
  elif cmp -s "${src}" "${dest}"; then
    printf '  unchanged: %s\n' "${dest}"
  else
    if [ "${DRY_RUN}" -eq 1 ]; then
      printf '[dry-run] update %s\n' "${dest}"
    elif cp "${src}" "${dest}"; then
      printf '  updated: %s\n' "${dest}"
    else
      printf '  FAILED: %s\n' "${dest}"
      return 1
    fi
  fi
}

install_skill_copy() {
  # install_skill_copy <dest_dir>
  local dest="$1" file
  log "==> Skill (copy): ${dest}"
  if [ -L "${dest}" ]; then
    if [ "${DRY_RUN}" -eq 1 ]; then
      printf '[dry-run] replace symlink with directory: %s\n' "${dest}"
      return 0
    fi
    log "  replace symlink with directory: ${dest}"
    rm "${dest}" || return 1
  fi
  if [ "${DRY_RUN}" -eq 1 ]; then
    printf '[dry-run] mkdir -p %s %s/agents\n' "${dest}" "${dest}"
  elif ! mkdir -p "${dest}" "${dest}/agents"; then
    printf '  FAILED to create directory: %s\n' "${dest}"
    return 1
  fi
  for file in ${SKILL_FILES}; do
    install_file "${SKILL_SRC}/${file}" "${dest}/${file}" || return 1
  done
}

install_skill_link() {
  # install_skill_link <dest_dir>: link dest to the canonical copy.
  local dest="$1" canonical="${CANONICAL_SKILLS_DIR}/${SKILL_NAME}"
  log "==> Skill (link): ${dest} -> ${canonical}"
  if [ "${DRY_RUN}" -eq 1 ]; then
    printf '[dry-run] link %s -> %s\n' "${dest}" "${canonical}"
    return 0
  fi
  if [ -L "${dest}" ] && [ "$(readlink "${dest}")" = "${canonical}" ]; then
    printf '  unchanged: %s\n' "${dest}"
    return 0
  fi
  if [ -e "${dest}" ] || [ -L "${dest}" ]; then
    log "  replacing existing path with symlink: ${dest}"
    rm -rf "${dest}" || return 1
  fi
  if ! mkdir -p "$(dirname "${dest}")"; then
    printf '  FAILED to create directory: %s\n' "$(dirname "${dest}")"
    return 1
  fi
  if ln -s "${canonical}" "${dest}"; then
    printf '  linked: %s\n' "${dest}"
  else
    log "  link failed; falling back to copy for ${dest}"
    install_skill_copy "${dest}"
  fi
}

seed_refinements() {
  log "==> Shared refinements: ${CANONICAL_REFINEMENTS}"
  if [ -e "${CANONICAL_REFINEMENTS}" ] || [ -L "${CANONICAL_REFINEMENTS}" ]; then
    log "  kept existing file (never overwritten)"
    return 0
  fi
  if [ ! -f "${TEMPLATE_SRC}" ]; then
    log "ERROR: missing template: ${TEMPLATE_SRC}"
    return 1
  fi
  if [ "${DRY_RUN}" -eq 1 ]; then
    printf '[dry-run] seed %s from template\n' "${CANONICAL_REFINEMENTS}"
  else
    if ! mkdir -p "$(dirname "${CANONICAL_REFINEMENTS}")"; then
      printf '  FAILED to create directory: %s\n' "$(dirname "${CANONICAL_REFINEMENTS}")"
      return 1
    fi
    if ! cp "${TEMPLATE_SRC}" "${CANONICAL_REFINEMENTS}"; then
      printf '  FAILED: %s\n' "${CANONICAL_REFINEMENTS}"
      return 1
    fi
    log "  seeded from template (edit freely; future runs keep it)"
  fi
  if [ -f "${LEGACY_REFINEMENTS}" ]; then
    log "  note: legacy ${LEGACY_REFINEMENTS} exists and stays in place;"
    log "  the skill reads it as a fallback and writes new bullets here."
  fi
}

verify_skill() {
  # verify_skill <dest_dir>: confirm the install is loadable.
  local dest="$1" resolved="${1}"
  if [ -L "${dest}" ]; then
    resolved="$(readlink "${dest}")"
  fi
  if [ -f "${resolved}/SKILL.md" ] && grep -q "^name: ${SKILL_NAME}" "${resolved}/SKILL.md"; then
    printf '  ok: %s\n' "${dest}"
  else
    printf '  MISSING OR INVALID: %s\n' "${dest}"
    return 1
  fi
}

# Parse flags.
while [ $# -gt 0 ]; do
  case "$1" in
    --all)          TARGETS="agents muse claude codex antigravity" ;;
    --agents)       TARGETS="${TARGETS} agents" ;;
    --muse)         TARGETS="${TARGETS} muse" ;;
    --claude)       TARGETS="${TARGETS} claude" ;;
    --codex)        TARGETS="${TARGETS} codex" ;;
    --antigravity|--gemini) TARGETS="${TARGETS} antigravity" ;;
    --link)         LINK_MODE=1 ;;
    --no-refinements) SEED_REFINEMENTS=0 ;;
    --dry-run)      DRY_RUN=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              log "ERROR: unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

if [ -z "${TARGETS}" ]; then
  TARGETS="agents muse claude codex antigravity"
fi
# Deduplicate while keeping order.
TARGETS="$(printf '%s\n' ${TARGETS} | awk '!seen[$0]++' | tr '\n' ' ')"

# Resolve target dirs (Muse honors XDG_CONFIG_HOME).
MUSE_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/muse/skills/${SKILL_NAME}"
CLAUDE_DIR="${HOME}/.claude/skills/${SKILL_NAME}"
CODEX_DIR="${HOME}/.codex/skills/${SKILL_NAME}"
ANTIGRAVITY_DIR="${HOME}/.gemini/config/skills/${SKILL_NAME}"
AGENTS_DIR="${CANONICAL_SKILLS_DIR}/${SKILL_NAME}"

if [ ! -f "${SKILL_SRC}/SKILL.md" ]; then
  log "ERROR: skill source not found: ${SKILL_SRC}/SKILL.md"
  exit 1
fi

# In link mode the canonical copy must exist first.
if [ "${LINK_MODE}" -eq 1 ]; then
  case " ${TARGETS} " in
    *" agents "*) ;;
    *) TARGETS="agents ${TARGETS}" ;;
  esac
fi

failures=0
for target in ${TARGETS}; do
  case "${target}" in
    agents)      dest="${AGENTS_DIR}" ;;
    muse)        dest="${MUSE_DIR}" ;;
    claude)      dest="${CLAUDE_DIR}" ;;
    codex)       dest="${CODEX_DIR}" ;;
    antigravity) dest="${ANTIGRAVITY_DIR}" ;;
  esac
  if [ "${LINK_MODE}" -eq 1 ] && [ "${target}" != "agents" ]; then
    install_skill_link "${dest}" || failures=$((failures + 1))
  else
    install_skill_copy "${dest}" || failures=$((failures + 1))
  fi
done

if [ "${SEED_REFINEMENTS}" -eq 1 ]; then
  seed_refinements || failures=$((failures + 1))
else
  log "==> Shared refinements: skipped (--no-refinements)"
fi

if [ "${DRY_RUN}" -eq 0 ]; then
  log "==> Verify"
  for target in ${TARGETS}; do
    case "${target}" in
      agents)      dest="${AGENTS_DIR}" ;;
      muse)        dest="${MUSE_DIR}" ;;
      claude)      dest="${CLAUDE_DIR}" ;;
      codex)       dest="${CODEX_DIR}" ;;
      antigravity) dest="${ANTIGRAVITY_DIR}" ;;
    esac
    verify_skill "${dest}" || failures=$((failures + 1))
  done
fi

if [ "${failures}" -gt 0 ]; then
  log "Completed with ${failures} problem(s)."
  exit 1
fi
log "Done. Invoke with /${SKILL_NAME} [low|medium|high|max] in any supported agent."
