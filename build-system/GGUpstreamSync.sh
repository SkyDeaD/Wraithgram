#!/bin/bash
# Apply a Telegram-iOS release to Ghostgram as a patch.
#
#   build-system/GGUpstreamSync.sh COMMIT
#
# Ghostgram's history does not contain Telegram's commits, so releases are not merged: the difference
# between the Telegram commit Ghostgram is based on (build-system/upstream-base) and COMMIT is applied
# with a three-way fallback. Where Telegram and Ghostgram changed the same lines, the file is left with
# conflict markers to resolve by hand. Changes to Telegram files that Ghostgram deletes are skipped.
# On success build-system/upstream-base holds COMMIT, staged with the rest; nothing is committed.
#
# Needs the Telegram-iOS remote fetched: git fetch upstream master. Guide: docs/ios/upstream-sync.md

set -uo pipefail
cd "$(dirname "$0")/.."

[ $# -eq 1 ] || { echo "usage: build-system/GGUpstreamSync.sh COMMIT" >&2; exit 2; }
BASE_FILE="build-system/upstream-base"
BASE="$(tr -d '[:space:]' < "$BASE_FILE")"

git cat-file -e "$BASE^{commit}" 2>/dev/null \
    || { echo "ERROR: base commit $BASE is not here — run: git fetch upstream master" >&2; exit 1; }
NEW="$(git rev-parse --verify --quiet "$1^{commit}")" \
    || { echo "ERROR: $1 is not a commit here — run: git fetch upstream master" >&2; exit 1; }
[ "$NEW" != "$BASE" ] || { echo "Already based on $BASE."; exit 0; }
# Submodules patched by GGBuild.sh are dirty on purpose; everything else must be committed.
[ -z "$(git status --porcelain --ignore-submodules=dirty)" ] \
    || { echo "ERROR: commit or stash your changes first." >&2; exit 1; }

excludes=()
while IFS= read -r path; do
    excludes+=(":(exclude)$path")
done < <(git diff --name-only --diff-filter=D "$BASE" HEAD)

echo "base    : $BASE"
echo "release : $NEW"
[ ${#excludes[@]} -eq 0 ] || echo "skipped : $(git diff --name-only --diff-filter=D "$BASE" HEAD | tr '\n' ' ')"
echo

git diff --binary "$BASE" "$NEW" -- . "${excludes[@]}" | git apply -3 --index --whitespace=nowarn
status=$?
conflicts="$(git diff --name-only --diff-filter=U)"

if [ "$status" != "0" ] && [ -z "$conflicts" ]; then
    echo
    echo "ERROR: the patch did not apply (see above); nothing was changed." >&2
    exit 1
fi

echo "$NEW" > "$BASE_FILE"
git add "$BASE_FILE"
echo
if [ -n "$conflicts" ]; then
    echo "Applied with conflicts. Resolve these files, then git add them:"
    echo "$conflicts" | sed 's/^/  /'
    exit 3
fi
echo "Applied cleanly. Review with git diff --cached, then commit."
