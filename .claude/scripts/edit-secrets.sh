#!/usr/bin/env bash
# edit-secrets.sh KEY=VALUE [KEY=VALUE ...]
#
# Writes the given key=value pairs to a temp file, opens it in an editor,
# then prints the edited contents to stdout (captured by Claude's Bash tool).
#
# Used by the /secrets command to allow interactive editing without a
# chat round-trip.

set -euo pipefail

TMPFILE=$(mktemp) || exit 1
trap "rm -f '$TMPFILE'" EXIT

# Write secrets sorted alphabetically, one per line
printf '%s\n' "$@" | sort > "$TMPFILE"

if command -v code &>/dev/null; then
    code --wait "$TMPFILE"
else
    vim "$TMPFILE" </dev/tty >/dev/tty
fi

cat "$TMPFILE"
