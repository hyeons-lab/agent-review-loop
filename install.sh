#!/usr/bin/env bash
#
# Install the agent skills (agent-review-loop, address-pr-comments)
# for Muse, Claude Code, Codex, and Antigravity/Gemini, and seed the
# shared refinements file.
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
#   --upgrade         refresh already-installed skills to the checked-out
#                     version: targets without the skill are skipped (never
#                     newly installed), symlinked installs are left alone
#                     (they follow the canonical copy), and the refinements
#                     file is never seeded or modified; the canonical store
#                     is always in scope so linked installs refresh for real
#   --dry-run         print what would change without changing anything
#   -h, --help        print this help and exit
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS="agent-review-loop address-pr-comments"
TEMPLATE_SRC="${SCRIPT_DIR}/templates/review-refinements.template.md"

CANONICAL_SKILLS_DIR="${HOME}/.agents/skills"
CANONICAL_REFINEMENTS="${HOME}/.agents/review-refinements.md"
LEGACY_REFINEMENTS="${HOME}/.gemini/review-refinements.md"

skill_files() {
  # skill_files <skill>: print the bundled files that make up one skill.
  case "$1" in
    agent-review-loop) printf 'SKILL.md thematic-review-pillars.md agents/openai.yaml\n' ;;
    address-pr-comments) printf 'SKILL.md agents/openai.yaml\n' ;;
    *) printf 'ERROR: unknown skill: %s\n' "$1" >&2; return 1 ;;
  esac
}

dest_for_target() {
  # dest_for_target <skill> <target>: print the install dir for one pair.
  case "$2" in
    agents)      printf '%s/%s\n' "${AGENTS_BASE}" "$1" ;;
    muse)        printf '%s/%s\n' "${MUSE_BASE}" "$1" ;;
    claude)      printf '%s/%s\n' "${CLAUDE_BASE}" "$1" ;;
    codex)       printf '%s/%s\n' "${CODEX_BASE}" "$1" ;;
    antigravity) printf '%s/%s\n' "${ANTIGRAVITY_BASE}" "$1" ;;
  esac
}

is_missing() {
  # is_missing <dest>: true when nothing is installed there (plain or symlink).
  [ ! -e "$1" ] && [ ! -L "$1" ]
}

DRY_RUN=0
LINK_MODE=0
SEED_REFINEMENTS=1
UPGRADE_MODE=0
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
  # install_skill_copy <skill> <dest_dir>
  local skill="$1" dest="$2" file src files
  src="${SCRIPT_DIR}/skills/${skill}"
  log "==> Skill (copy): ${skill} ${dest}"
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
  files="$(skill_files "${skill}")" || return 1
  for file in ${files}; do
    install_file "${src}/${file}" "${dest}/${file}" || return 1
  done
}

install_skill_link() {
  # install_skill_link <skill> <dest_dir>: link dest to the canonical copy.
  local skill="$1" dest="$2"
  local canonical="${CANONICAL_SKILLS_DIR}/${skill}"
  log "==> Skill (link): ${skill} ${dest} -> ${canonical}"
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
    install_skill_copy "${skill}" "${dest}"
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
  # verify_skill <skill> <dest_dir>: confirm the install is loadable.
  local skill="$1" dest="$2" resolved="${2}"
  if [ -L "${dest}" ]; then
    resolved="$(readlink "${dest}")"
  fi
  if [ ! -f "${resolved}/SKILL.md" ]; then
    printf '  MISSING: %s (no SKILL.md; reinstall, or check the link target)\n' "${dest}"
    return 1
  fi
  if grep -q "^name: ${skill}" "${resolved}/SKILL.md"; then
    printf '  ok: %s\n' "${dest}"
  else
    printf '  INVALID: %s (SKILL.md name mismatch; expected %s)\n' "${dest}" "${skill}"
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
    --upgrade) UPGRADE_MODE=1 ;;
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
MUSE_BASE="${XDG_CONFIG_HOME:-${HOME}/.config}/muse/skills"
CLAUDE_BASE="${HOME}/.claude/skills"
CODEX_BASE="${HOME}/.codex/skills"
ANTIGRAVITY_BASE="${HOME}/.gemini/config/skills"
AGENTS_BASE="${CANONICAL_SKILLS_DIR}"

for skill in ${SKILLS}; do
  if [ ! -f "${SCRIPT_DIR}/skills/${skill}/SKILL.md" ]; then
    log "ERROR: skill source not found: ${SCRIPT_DIR}/skills/${skill}/SKILL.md"
    exit 1
  fi
done

# In link mode the canonical copy must exist first (never under --upgrade,
# which ignores --link and pulls the canonical store in itself).
if [ "${LINK_MODE}" -eq 1 ] && [ "${UPGRADE_MODE}" -eq 0 ]; then
  case " ${TARGETS} " in
    *" agents "*) ;;
    *) TARGETS="agents ${TARGETS}" ;;
  esac
fi

# Upgrade never changes install type or touches learnings, but it always
# covers the canonical store so linked installs refresh for real (a missing
# canonical copy is still skipped, never newly installed).
if [ "${UPGRADE_MODE}" -eq 1 ]; then
  SEED_REFINEMENTS=0
  if [ "${LINK_MODE}" -eq 1 ]; then
    log "note: --upgrade ignores --link (installed types are never changed)"
    LINK_MODE=0
  fi
  case " ${TARGETS} " in
    *" agents "*) ;;
    *) TARGETS="agents ${TARGETS}" ;;
  esac
fi

failures=0
for skill in ${SKILLS}; do
  for target in ${TARGETS}; do
    dest="$(dest_for_target "${skill}" "${target}")"
    if [ "${UPGRADE_MODE}" -eq 1 ]; then
      if is_missing "${dest}"; then
        reason="not installed, skipping (upgrade never installs to new targets)"
      elif [ -L "${dest}" ]; then
        link_target="$(readlink "${dest}")"
        if [ "${link_target}" != "${AGENTS_BASE}/${skill}" ]; then
          reason="WARNING: link points at ${link_target}, not the canonical copy; leaving in place"
        elif [ ! -e "${dest}" ]; then
          reason="WARNING: linked install dangles (canonical copy missing); leaving in place, verify will flag it"
        else
          reason="linked install, follows the canonical copy; leaving in place"
        fi
      else
        install_skill_copy "${skill}" "${dest}" || failures=$((failures + 1))
        continue
      fi
      log "==> Skill (upgrade): ${skill} ${dest}"
      log "  ${reason}"
    elif [ "${LINK_MODE}" -eq 1 ] && [ "${target}" != "agents" ]; then
      install_skill_link "${skill}" "${dest}" || failures=$((failures + 1))
    else
      install_skill_copy "${skill}" "${dest}" || failures=$((failures + 1))
    fi
  done
done

if [ "${SEED_REFINEMENTS}" -eq 1 ]; then
  seed_refinements || failures=$((failures + 1))
elif [ "${UPGRADE_MODE}" -eq 1 ]; then
  log "==> Shared refinements: left untouched (--upgrade never modifies learnings)"
else
  log "==> Shared refinements: skipped (--no-refinements)"
fi

if [ "${DRY_RUN}" -eq 0 ]; then
  log "==> Verify"
  for skill in ${SKILLS}; do
    for target in ${TARGETS}; do
      dest="$(dest_for_target "${skill}" "${target}")"
      if [ "${UPGRADE_MODE}" -eq 1 ] && is_missing "${dest}"; then
        printf '  not installed, skipped: %s\n' "${dest}"
        continue
      fi
      verify_skill "${skill}" "${dest}" || failures=$((failures + 1))
    done
  done
fi

if [ "${failures}" -gt 0 ]; then
  log "Completed with ${failures} problem(s)."
  exit 1
fi
log "Done. Invoke with /agent-review-loop [low|medium|high|max] or /address-pr-comments <pr> in any supported agent."
