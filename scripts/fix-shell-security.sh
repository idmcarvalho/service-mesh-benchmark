#!/bin/bash
# Script to add security headers and fix common issues in shell scripts
# Part of security hardening initiative

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Hardening Shell Scripts ==="

# Find all shell scripts
find "${REPO_ROOT}/benchmarks/scripts" -name "*.sh" -type f | while IFS= read -r script; do
    echo "Processing: ${script}"

    # Backup original
    cp "${script}" "${script}.backup"

    # Check if script already has 'set -euo pipefail'
    if ! grep -q "set -euo pipefail" "${script}"; then
        # Find the shebang line and add set -euo pipefail after it
        if grep -q "^#!/" "${script}"; then
            sed -i '/^#!/a set -euo pipefail' "${script}"
            echo "  ✓ Added 'set -euo pipefail'"
        fi
    fi

    # Check if script already has shellcheck directive
    if ! grep -q "# shellcheck" "${script}"; then
        sed -i '1a # shellcheck shell=bash' "${script}"
        echo "  ✓ Added shellcheck directive"
    fi

    echo "  ✓ Backed up to ${script}.backup"
done

echo ""
echo "=== Running Shellcheck on All Scripts ==="
echo "Note: Please review shellcheck warnings and fix manually as needed"
echo ""

find "${REPO_ROOT}/benchmarks/scripts" -name "*.sh" -type f ! -name "*.backup" | while IFS= read -r script; do
    echo "Checking: ${script}"
    shellcheck "${script}" || echo "  ⚠ Shellcheck found issues - please review"
    echo ""
done

echo "=== Shell Script Hardening Complete ==="
echo ""
echo "Next steps:"
echo "1. Review shellcheck warnings above"
echo "2. Manually fix any remaining issues (especially unquoted variables)"
echo "3. Test scripts to ensure they still work correctly"
echo "4. Remove .backup files once satisfied: find benchmarks/scripts -name '*.backup' -delete"
