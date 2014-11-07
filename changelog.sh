#!/usr/bin/env bash
set -e

log() {
  git --no-pager log --abbrev=8 --date=short "$@"
}

logcommits() {
  log --pretty='- %h: %s' "$@"
}

initial_commit=$(git rev-list --max-parents=0 HEAD)

>CHANGELOG
tags=($(echo $initial_commit; git tag; echo master))
for ((i = ${#tags[@]}-1; i > 0; i--)); do
  v=\\n${tags[i]}
  v=${v/\\nmaster/v$VERSION}
  printf "$v ($(log -1 --pretty=%ad ${tags[i]}))\n" >>CHANGELOG
  logcommits ${tags[i-1]}..${tags[i]} >>CHANGELOG
done
logcommits $initial_commit >>CHANGELOG

git add CHANGELOG
