#!/bin/sh
set -eu

revision="ef8e8efe52f3d43df7acefad132c6506239bddee"
destination="${1:-.build/vice-testprogs}"

if [ ! -d "$destination/.git" ]; then
    mkdir -p "$destination"
    git -C "$destination" init -q
    git -C "$destination" remote add origin https://github.com/libsidplayfp/VICE-testprogs.git
    git -C "$destination" sparse-checkout init --cone
fi

git -C "$destination" sparse-checkout set SID/resid-test SID/osc3-wave0 SID/oscinit SID/wf12nsr
git -C "$destination" fetch --depth 1 origin "$revision"
git -C "$destination" checkout -q --detach FETCH_HEAD

printf '%s\n' "$destination"
