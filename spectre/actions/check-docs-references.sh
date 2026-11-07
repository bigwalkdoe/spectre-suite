#!/bin/bash
# Fails when the documentation tells a reader to run a script that is not in the
# repository.
#
# The README's quick start and security sections referenced 20-odd scripts under
# scripts/security, scripts/performance, scripts/network and scripts/maintenance
# that do not exist here. Anyone following the documented setup got "No such file
# or directory" on the first command. The drift was invisible because nothing
# checked it.
#
# Every scripts/ or cloud-deployment/ path mentioned in the docs must exist. To
# describe a capability that is genuinely not implemented here, describe it in
# prose without a path rather than documenting a command that cannot run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${SPECTRE_REPO_ROOT:-}" ]; then
  PROJECT_ROOT="$SPECTRE_REPO_ROOT"
elif [ -f "$SCRIPT_DIR/../../docker-compose.monitoring.yml" ]; then
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
cd "$PROJECT_ROOT"

docs=$(ls README.md docs/*.md 2>/dev/null)
if [ -z "$docs" ]; then
    echo "ERROR: no documentation files found to check" >&2
    exit 1
fi

# Match the paths a reader could paste into a shell. The final character class
# excludes "." so a path at the end of a sentence ("...audit-trail.sh.") is not
# captured with its full stop, which would look like a missing file.
pattern='(scripts|cloud-deployment)/[A-Za-z0-9._/-]*[A-Za-z0-9_/-]'

# shellcheck disable=SC2086  # word splitting into the file list is intended
missing=$(
    grep -rhoE "$pattern" $docs 2>/dev/null | sort -u | while read -r p; do
        [ -e "$p" ] || printf '%s\n' "$p"
    done
)

if [ -n "$missing" ]; then
    # shellcheck disable=SC2086  # as above
    while read -r p; do
        [ -n "$p" ] || continue
        # shellcheck disable=SC2086  # as above
        refs=$(grep -rlE "$p" $docs 2>/dev/null | tr '\n' ' ')
        echo "ERROR: documented path does not exist: $p" >&2
        echo "       referenced in: $refs" >&2
    done <<< "$missing"
    echo >&2
    echo "Describe unimplemented capabilities in prose, without a path." >&2
    exit 1
fi

# P5b / spec §9: README must not regress into advertising unimplemented
# capabilities as present (the Loki/Wazuh/ZAP/… class). Full capability↔actions
# mapping is semantic; this enforces the motivating guardrails: explicit
# "Not implemented" disclaimer, known unimplemented stacks named, and deferral
# to `spectre actions list` / `spectre actions verify` as source of truth.
if [ -f README.md ]; then
    if ! grep -Fq 'Not implemented in this repository' README.md; then
        echo "ERROR: README.md missing explicit \"Not implemented in this repository\" disclaimer (spec §9/P5b)." >&2
        exit 1
    fi
    missing_caps=""
    require_readme_token() {
        local label="$1" pattern="$2"
        if ! grep -Eqi "$pattern" README.md; then
            missing_caps="${missing_caps}  - ${label}"$'\n'
        fi
    }
    require_readme_token "Loki" '\bLoki\b'
    require_readme_token "Promtail" '\bPromtail\b'
    require_readme_token "Wazuh" '\bWazuh\b'
    require_readme_token "OWASP ZAP / ZAP" 'OWASP ZAP|\bZAP\b'
    require_readme_token "SonarQube" '\bSonarQube\b'
    require_readme_token "PgBouncer" '\bPgBouncer\b'
    require_readme_token "read-replica/read replica" 'read-replica|read replica'
    require_readme_token "Vault/HashiCorp Vault" '\bVault\b'
    require_readme_token "k6" '\bk6\b'
    require_readme_token "Locust" '\bLocust\b'
    if [ -n "$missing_caps" ]; then
        echo "ERROR: README.md no longer names known-unimplemented capabilities (spec §9/P5b regression guard):" >&2
        printf '%s' "$missing_caps" >&2
        exit 1
    fi
    if ! grep -Fq 'spectre actions list' README.md || ! grep -Fq 'spectre actions verify' README.md; then
        echo "ERROR: README.md must direct operators to \`spectre actions list\` / \`spectre actions verify\` as source of truth (spec §9/P5b)." >&2
        exit 1
    fi
fi

echo "documentation references OK: every scripts/ and cloud-deployment/ path mentioned resolves; README capability-disclaimer guardrails present"
