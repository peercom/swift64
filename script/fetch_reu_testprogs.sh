#!/bin/sh
set -eu

# Public REU test programs only, never emulator implementation or machine ROMs.
# Uses the same pinned VICE-testprogs revision as the VIC and SID fetch scripts.
revision="ef8e8efe52f3d43df7acefad132c6506239bddee"
destination="${1:-.build/reu-testprogs}"

if [ ! -d "$destination/.git" ]; then
    mkdir -p "$destination"
    git -C "$destination" init -q
    git -C "$destination" remote add origin https://github.com/libsidplayfp/VICE-testprogs.git
    git -C "$destination" sparse-checkout init --cone
fi

# A blobless partial clone only downloads the REU directory's files.
git -C "$destination" sparse-checkout set REU
git -C "$destination" fetch --depth 1 --filter=blob:none origin "$revision"
git -C "$destination" checkout -q --detach FETCH_HEAD

printf 'REU fixtures from %s are in %s\n' "$revision" "$destination"
