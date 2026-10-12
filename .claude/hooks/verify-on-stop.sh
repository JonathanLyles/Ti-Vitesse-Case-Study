#!/bin/bash
INPUT=$(cat)

# Avoid a loop: if Claude is already continuing because of this hook, let it stop.
# (Claude Code overrides a Stop hook that blocks 8 times in a row anyway.)
# (grep instead of jq: jq is not installed on every machine.)
echo "$INPUT" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

# Only verify when something under force-app changed (tracked or new files)
CHANGED=$( { git diff --name-only main -- force-app; git ls-files --others --exclude-standard -- force-app; } )
[ -z "$CHANGED" ] && exit 0

OUT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/sf-verify/scripts/check.sh" 2>&1) && exit 0

echo "$OUT" | grep '^GATE' >&2
echo "Verification failed. Fix the failing gates before finishing." >&2
exit 2   # block the stop: Claude keeps working on the failures
