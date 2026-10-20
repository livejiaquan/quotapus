#!/usr/bin/env bash
set -euo pipefail

# Publishes this checkout's current commit to the public repository (livejiaquan/quotapus) as ONE new
# commit on top of its branch. The public history is one commit per publish, while this local repository
# keeps the full development and upstream-merge history that merging future OpenUsage changes needs.
#
# usage:
#   script/publish_public.sh "Quotapus 1.0.1"                   # publish HEAD to public main
#   TAG=v1.0.1 script/publish_public.sh "Quotapus 1.0.1"        # ...and tag it, which starts the Release workflow
#   BRANCH=feat/ssh-try script/publish_public.sh "CI check"     # publish to another branch (CI runs on feat/ssh-*)
#
# Commit first: only committed files are published, exactly as they are at HEAD.

REMOTE="${REMOTE:-public}"
BRANCH="${BRANCH:-main}"
MESSAGE="${1:?usage: script/publish_public.sh \"commit message\"}"

[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }
git fetch -q "$REMOTE"

TREE="$(git rev-parse 'HEAD^{tree}')"
if PARENT="$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH")"; then
  if [ "$(git rev-parse "$PARENT^{tree}")" = "$TREE" ]; then
    echo "$REMOTE/$BRANCH already matches HEAD; nothing to publish."
    COMMIT="$PARENT"
  else
    COMMIT="$(git commit-tree "$TREE" -p "$PARENT" -m "$MESSAGE")"
    git push "$REMOTE" "$COMMIT:refs/heads/$BRANCH"
  fi
else
  COMMIT="$(git commit-tree "$TREE" -m "$MESSAGE")"
  git push "$REMOTE" "$COMMIT:refs/heads/$BRANCH"
fi
echo "Published $(git rev-parse --short HEAD) as $REMOTE/$BRANCH $(git rev-parse --short "$COMMIT")"

if [ -n "${TAG:-}" ]; then
  git tag -a "$TAG" "$COMMIT" -m "$TAG"
  git push "$REMOTE" "refs/tags/$TAG"
  echo "Tagged $TAG; the Release workflow is building it."
fi
