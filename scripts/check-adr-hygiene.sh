#!/usr/bin/env bash
# check-adr-hygiene.sh — mechanically enforces ADR-0001's rules across all
# four estate repositories:
#   1. No two ADR files within the same repo's docs/adr/ share a numeric
#      prefix (collisions ACROSS different repos are expected — per-repo
#      numbering is deliberate, ADR-0001).
#   2. Every ADR file name matches the NNNN-kebab-slug.md convention.
#   3. Every ADR declares a Status and a Tier.
#   4. Every ADR claiming the full-madr tier really contains a
#      "## Considered Options" section listing at least two options — the
#      exact failure ADR-0001 exists to prevent, caught mechanically here.
#   5. The committed master index (docs/adr/README.md) is current: it's
#      regenerated to a temporary file and compared byte for byte against
#      the committed copy, so this check never mutates the working tree.
#   6. The index contains a section for each of the four repositories.
#
# Follows the estate's PASS/FAIL convention (see athena-infra/scripts/
# verify.sh): every check runs and reports independently; the script exits
# non-zero if any check failed.
#
# Usage: bash scripts/check-adr-hygiene.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_ROOT="$(dirname "${SCRIPT_DIR}")"           # estate/athena-docs
ESTATE_ROOT="$(dirname "${DOCS_ROOT}")"          # estate/

REPOS=(athena-app athena-infra athena-gitops athena-docs)

FAIL=0
ok()   { printf '\033[32m[hygiene] PASS  %s\033[0m\n' "$1"; }
bad()  { printf '\033[31m[hygiene] FAIL  %s\033[0m\n' "$1"; FAIL=1; }
info() { printf '[hygiene] %s\n' "$1"; }

repo_adr_dir() {
  case "$1" in
    athena-docs) printf '%s' "${DOCS_ROOT}/docs/adr" ;;
    *) printf '%s' "${ESTATE_ROOT}/$1/docs/adr" ;;
  esac
}

info "Checking ADR hygiene across: ${REPOS[*]}"
echo

# --- Check 1: no duplicate numeric prefix within one repo's docs/adr/ ---
for repo in "${REPOS[@]}"; do
  adr_dir="$(repo_adr_dir "${repo}")"
  [ -d "${adr_dir}" ] || { info "${repo}: no docs/adr/ directory, skipping duplicate-prefix check"; continue; }

  dupe_nums="$(LC_ALL=C find "${adr_dir}" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' -printf '%f\n' \
    | cut -c1-4 | sort | uniq -d)"
  if [ -n "${dupe_nums}" ]; then
    pattern="$(printf '%s' "${dupe_nums}" | paste -sd '|' -)"
    names="$(LC_ALL=C find "${adr_dir}" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' -printf '%f\n' \
      | grep -E "^(${pattern})" | paste -sd ', ' -)"
    bad "${repo}: duplicate ADR number prefix(es) [$(printf '%s' "${dupe_nums}" | paste -sd ', ' -)] -- ${names}"
  else
    ok "${repo}: no duplicate ADR number prefixes"
  fi
done
echo

# --- Check 2: filename convention ---
for repo in "${REPOS[@]}"; do
  adr_dir="$(repo_adr_dir "${repo}")"
  [ -d "${adr_dir}" ] || continue

  bad_names=()
  while IFS= read -r f; do
    base="$(basename "${f}")"
    if ! [[ "${base}" =~ ^[0-9]{4}-[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
      bad_names+=("${base}")
    fi
  done < <(LC_ALL=C find "${adr_dir}" -maxdepth 1 -type f -name '*.md' ! -name 'README.md')

  if [ "${#bad_names[@]}" -gt 0 ]; then
    bad "${repo}: filename(s) violate the NNNN-kebab-slug.md convention -- ${bad_names[*]}"
  else
    ok "${repo}: all ADR filenames match the NNNN-kebab-slug.md convention"
  fi
done
echo

# --- Check 3+4: Status/Tier declared; full-tier ADRs really have >=2 considered options ---
for repo in "${REPOS[@]}"; do
  adr_dir="$(repo_adr_dir "${repo}")"
  [ -d "${adr_dir}" ] || continue

  while IFS= read -r f; do
    base="$(basename "${f}")"
    status="$(grep -m1 -E '^\* Status:' "${f}" | sed -E 's/^\* Status:[[:space:]]*//')"
    tier="$(grep -m1 -E '^\* Tier:' "${f}" | sed -E 's/^\* Tier:[[:space:]]*//')"

    if [ -z "${status}" ]; then
      bad "${repo}/${base}: missing 'Status:' field"
    fi
    if [ -z "${tier}" ]; then
      bad "${repo}/${base}: missing 'Tier:' field"
    fi

    if [[ "${tier}" == full* ]]; then
      if grep -q '^## Considered Options' "${f}"; then
        opt_count="$(awk '/^## Considered Options/{flag=1;next} /^## /{flag=0} flag && /^\* /' "${f}" | wc -l)"
        if [ "${opt_count}" -lt 2 ]; then
          bad "${repo}/${base}: claims full-madr tier but 'Considered Options' lists fewer than 2 options"
        fi
      else
        bad "${repo}/${base}: claims full-madr tier but has no 'Considered Options' section"
      fi
    fi
  done < <(LC_ALL=C find "${adr_dir}" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' | LC_ALL=C sort)
done
ok "Status/Tier fields and full-tier Considered-Options conformance checked for every ADR found"
echo

# --- Check 5: index freshness (regenerate to a temp file, never mutate the committed index) ---
TMP_INDEX="$(mktemp)"
trap 'rm -f "${TMP_INDEX}"' EXIT

if [ -f "${SCRIPT_DIR}/gen-adr-index.sh" ]; then
  if bash "${SCRIPT_DIR}/gen-adr-index.sh" "${TMP_INDEX}" >/dev/null; then
    if diff -q "${TMP_INDEX}" "${DOCS_ROOT}/docs/adr/README.md" >/dev/null 2>&1; then
      ok "master index (docs/adr/README.md) is up to date with the generator"
    else
      bad "master index (docs/adr/README.md) is stale -- run scripts/gen-adr-index.sh and commit the result"
    fi
  else
    bad "gen-adr-index.sh failed to run"
  fi
else
  bad "gen-adr-index.sh not found at ${SCRIPT_DIR}/gen-adr-index.sh"
fi
echo

# --- Check 6: index contains a section for each of the four repositories ---
for repo in "${REPOS[@]}"; do
  if grep -q "^## ${repo}\$" "${DOCS_ROOT}/docs/adr/README.md" 2>/dev/null; then
    ok "index contains a section for ${repo}"
  else
    bad "index is missing a section for ${repo}"
  fi
done
echo

if [ "${FAIL}" -eq 0 ]; then
  printf '\033[32m[hygiene] All checks passed.\033[0m\n'
else
  printf '\033[31m[hygiene] One or more checks failed.\033[0m\n'
fi

exit "${FAIL}"
