#!/usr/bin/env bash
# check-study-notes.sh — mechanically enforces the study-note contract
# (Plan 08, mirroring check-adr-hygiene.sh's PASS/FAIL shape exactly):
#   1. No two note files share a slug, case-insensitively — a case-only
#      difference is caught here even though this filesystem happens to be
#      case-sensitive, because it would otherwise collide the moment this
#      repo is cloned onto (or served from) a case-insensitive filesystem.
#   2. Every note contains all five canonical headings, in the template's
#      order: Mental model, Common interview questions, Gotchas hit in this
#      project, War stories, Command cheat-sheet. A heading present but
#      whose body is just "_Not yet filled._" still passes — the point of
#      the explicit marker is that it's a visible, honest to-do, not a
#      failure.
#   3. Every note's header names at least one related ADR, and every named
#      ADR path resolves to a real file in one of the four estate
#      repositories.
#   4. Every note has a non-empty "Mental model" section — the one section
#      that is never legitimately empty, marker or not.
#   5. The committed index (study-notes/README.md) is current: regenerated
#      to a temporary file and compared byte for byte against the committed
#      copy, so this check never mutates the working tree.
#
# Usage: bash scripts/check-study-notes.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_ROOT="$(dirname "${SCRIPT_DIR}")"                    # estate/athena-docs
ESTATE_ROOT="$(dirname "${DOCS_ROOT}")"                   # estate/
STUDY_DIR="${DOCS_ROOT}/study-notes"

HEADINGS=(
  "## Mental model"
  "## Common interview questions"
  "## Gotchas hit in this project"
  "## War stories"
  "## Command cheat-sheet"
)

FAIL=0
ok()   { printf '\033[32m[study-notes] PASS  %s\033[0m\n' "$1"; }
bad()  { printf '\033[31m[study-notes] FAIL  %s\033[0m\n' "$1"; FAIL=1; }
info() { printf '[study-notes] %s\n' "$1"; }

extract_field_joined() {
  # extract_field_joined <file> <field-name> — collapses a two-space-indented
  # continuation line onto the field's own line, same convention as
  # gen-study-index.sh.
  awk -v field="$2" '
    BEGIN { on=0 }
    $0 ~ "^\\* " field ":" { on=1; sub("^\\* " field ":[[:space:]]*", ""); line=$0; next }
    on && /^  / { sub(/^  */, " "); line=line $0; next }
    on { print line; on=0 }
    END { if (on) print line }
  ' "$1"
}

info "Checking study notes in: ${STUDY_DIR}"
echo

NOTE_FILES=()
if [ -d "${STUDY_DIR}" ]; then
  while IFS= read -r f; do
    NOTE_FILES+=("${f}")
  done < <(LC_ALL=C find "${STUDY_DIR}" -maxdepth 1 -type f -name '*.md' ! -name '_template.md' ! -name 'README.md' | LC_ALL=C sort)
fi

if [ "${#NOTE_FILES[@]}" -eq 0 ]; then
  info "no study notes found (template-only state) — skipping per-note checks"
else
  # --- Check 1: no duplicate slug, case-insensitively ---
  dupe_slugs="$(for f in "${NOTE_FILES[@]}"; do basename "${f}" .md; done \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sort | LC_ALL=C uniq -d)"
  if [ -n "${dupe_slugs}" ]; then
    bad "duplicate slug(s) (case-insensitive) -- $(printf '%s' "${dupe_slugs}" | paste -sd ', ' -)"
  else
    ok "no duplicate study-note slugs (case-insensitive)"
  fi
  echo

  # --- Check 2+4: five canonical headings present, in order; non-empty Mental model ---
  for f in "${NOTE_FILES[@]}"; do
    base="$(basename "${f}")"

    missing=()
    last_line=0
    out_of_order=0
    for h in "${HEADINGS[@]}"; do
      line_no="$(grep -n -F -x "${h}" "${f}" | head -1 | cut -d: -f1)"
      if [ -z "${line_no}" ]; then
        missing+=("${h}")
      else
        if [ "${line_no}" -le "${last_line}" ]; then
          out_of_order=1
        fi
        last_line="${line_no}"
      fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
      bad "${base}: missing heading(s) -- ${missing[*]}"
    elif [ "${out_of_order}" -eq 1 ]; then
      bad "${base}: canonical headings present but out of the template's order"
    else
      ok "${base}: all five canonical headings present, in order"
    fi

    # Mental model body: everything between "## Mental model" and the next "## " heading.
    mm_body="$(awk '
      /^## Mental model$/ { on=1; next }
      on && /^## / { exit }
      on { print }
    ' "${f}" | sed -E '/^[[:space:]]*$/d')"
    if [ -z "${mm_body}" ]; then
      bad "${base}: Mental model section is empty"
    else
      ok "${base}: Mental model section is non-empty"
    fi
  done
  echo

  # --- Check 3: at least one Related ADR, every named path resolves ---
  for f in "${NOTE_FILES[@]}"; do
    base="$(basename "${f}")"
    adrs_raw="$(extract_field_joined "${f}" "Related ADRs")"

    IFS=',' read -ra adr_parts <<< "${adrs_raw}"
    real_parts=()
    for part in "${adr_parts[@]}"; do
      part="$(printf '%s' "${part}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -n "${part}" ] && real_parts+=("${part}")
    done

    if [ "${#real_parts[@]}" -eq 0 ]; then
      bad "${base}: names no Related ADR"
      continue
    fi

    unresolved=()
    for part in "${real_parts[@]}"; do
      if [ ! -f "${ESTATE_ROOT}/${part}" ]; then
        unresolved+=("${part}")
      fi
    done

    if [ "${#unresolved[@]}" -gt 0 ]; then
      bad "${base}: Related ADR path(s) do not resolve to a real file -- ${unresolved[*]}"
    else
      ok "${base}: all ${#real_parts[@]} Related ADR path(s) resolve"
    fi
  done
  echo
fi

# --- Check 5: index freshness (regenerate to a temp file, never mutate the committed index) ---
TMP_INDEX="$(mktemp)"
trap 'rm -f "${TMP_INDEX}"' EXIT

if [ -f "${SCRIPT_DIR}/gen-study-index.sh" ]; then
  if bash "${SCRIPT_DIR}/gen-study-index.sh" "${TMP_INDEX}" >/dev/null; then
    if diff -q "${TMP_INDEX}" "${STUDY_DIR}/README.md" >/dev/null 2>&1; then
      ok "study-notes index (study-notes/README.md) is up to date with the generator"
    else
      bad "study-notes index (study-notes/README.md) is stale -- run scripts/gen-study-index.sh and commit the result"
    fi
  else
    bad "gen-study-index.sh failed to run"
  fi
else
  bad "gen-study-index.sh not found at ${SCRIPT_DIR}/gen-study-index.sh"
fi
echo

if [ "${FAIL}" -eq 0 ]; then
  printf '\033[32m[study-notes] All checks passed.\033[0m\n'
else
  printf '\033[31m[study-notes] One or more checks failed.\033[0m\n'
fi

exit "${FAIL}"
