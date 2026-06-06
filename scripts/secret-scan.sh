#!/bin/bash
# Pre-push safety net: scans tracked files for likely tokens, keys, private
# paths, or internal hostnames, and blocks the push if it finds any.
# False positive? Bypass once with:  git push --no-verify
#
# Reuse in another project: copy this file to scripts/, then run
#   ln -sf ../../scripts/secret-scan.sh .git/hooks/pre-push
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 0

PATTERNS="gho_[A-Za-z0-9]{20}|ghp_[A-Za-z0-9]{20}|github_pat_[A-Za-z0-9_]{20}|sk-[A-Za-z0-9]{20}|xox[baprs]-[A-Za-z0-9-]+|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|[Bb]earer [A-Za-z0-9._-]{20}|[Ss]ecret[_-]?[Kk]ey[[:space:]]*[:=]|[Pp]assword[[:space:]]*[:=]|/Users/[a-z]|leap\.local"

if git grep -nIiE "$PATTERNS" -- . ":(exclude)scripts/secret-scan.sh" > /tmp/secret-scan-hits 2>/dev/null; then
  echo "⛔  Push blocked. Possible sensitive content in tracked files:"
  echo ""
  cat /tmp/secret-scan-hits
  echo ""
  echo "False positive? Bypass once with:  git push --no-verify"
  exit 1
fi
echo "✅  secret-scan: clean."
exit 0
