#!/bin/sh
set -e

REF="$1/data/cache/$2"
if test -d "$REF"; then
  cd "$1/data/cache/$2" && git fetch --all --quiet
else
  git clone --mirror --quiet "$3" "$REF"
fi

ROOT="$1/data/builds/$4"
git clone --quiet --reference "$1/data/cache/$2" "$3" "$ROOT"

cd "$ROOT"
git checkout -q "$5"
