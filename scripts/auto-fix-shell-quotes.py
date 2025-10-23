#!/usr/bin/env python3
"""
Automated script to add security improvements to shell scripts:
1. Add 'set -euo pipefail'
2. Add shellcheck directive
3. Note unquoted variables for manual review
"""

import os
import re
import sys
from pathlib import Path

def fix_shell_script(filepath):
    """Add basic security improvements to a shell script."""
    print(f"Processing: {filepath}")

    with open(filepath, 'r') as f:
        lines = f.readlines()

    # Backup original
    backup_path = f"{filepath}.backup"
    with open(backup_path, 'w') as f:
        f.writelines(lines)

    modified = False

    # Check for shebang
    if not lines[0].startswith('#!'):
        print(f"  ⚠ No shebang found, skipping")
        return

    # Add shellcheck directive if not present
    has_shellcheck = any('shellcheck' in line for line in lines[:5])
    if not has_shellcheck:
        lines.insert(1, '# shellcheck shell=bash\n')
        modified = True
        print(f"  ✓ Added shellcheck directive")

    # Check for set -euo pipefail
    has_set_euo = any('set -euo pipefail' in line for line in lines[:10])
    if not has_set_euo:
        # Find position after shellcheck directive or after shebang
        insert_pos = 1
        for i, line in enumerate(lines[:10]):
            if 'shellcheck' in line:
                insert_pos = i + 1
                break
        lines.insert(insert_pos, 'set -euo pipefail\n')
        modified = True
        print(f"  ✓ Added 'set -euo pipefail'")

    if modified:
        with open(filepath, 'w') as f:
            f.writelines(lines)
        print(f"  ✓ Modified (backup: {backup_path})")
    else:
        print(f"  ℹ No changes needed")
        os.remove(backup_path)

def main():
    repo_root = Path(__file__).parent.parent
    scripts_dir = repo_root / 'benchmarks' / 'scripts'

    if not scripts_dir.exists():
        print(f"Scripts directory not found: {scripts_dir}")
        sys.exit(1)

    shell_scripts = list(scripts_dir.glob('*.sh'))

    if not shell_scripts:
        print("No shell scripts found")
        sys.exit(1)

    print(f"Found {len(shell_scripts)} shell scripts\n")

    for script in shell_scripts:
        fix_shell_script(script)
        print()

    print("=" * 60)
    print("IMPORTANT: Manual review required!")
    print("=" * 60)
    print("1. Review all scripts for unquoted variables")
    print("2. Run: shellcheck benchmarks/scripts/*.sh")
    print("3. Test scripts to ensure they still work")
    print("4. Remove backups when satisfied: rm benchmarks/scripts/*.backup")

if __name__ == '__main__':
    main()
