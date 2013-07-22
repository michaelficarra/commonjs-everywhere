if [ $# -gt 0 ]; then next_version=$1; else next_version=master; fi
initial_commit=$(git log --pretty=%H | tail -1)

printf "$next_version"
date '+ (%Y-%m-%d)'

tags=($(echo $initial_commit; git tag; echo master))
for ((i = ${#tags[@]}-1; i > 0; i--)); do
  if [ "${tags[i]}" '!=' master ]; then
    printf "${tags[i]}"
    git --no-pager log -1 --date=short --pretty=' (%ad)' "${tags[i]}"
  fi
  git --no-pager log --date=short --pretty='- %h: %s' "${tags[i-1]}..${tags[i]}"
  if [ $i -gt 1 ]; then echo; fi
done
git --no-pager log -1 --date=short --pretty='- %h: %s' $initial_commit
