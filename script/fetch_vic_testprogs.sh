#!/bin/sh
set -eu

# Public test programs only, never emulator implementation or machine ROMs.
revision="ef8e8efe52f3d43df7acefad132c6506239bddee"
destination="${1:-.build/vic-testprogs}"
base="https://raw.githubusercontent.com/libsidplayfp/VICE-testprogs/$revision"

for path in \
    readme.txt \
    VICII/phi1timing/README.txt \
    VICII/phi1timing/core.asm \
    VICII/phi1timing/phi1timing.prg \
    VICII/phi1timing/phi1timing_ntsc.prg \
    VICII/spritecollisions/readme.txt \
    VICII/spritecollisions/sprite-sprite-collision-cycle.tas \
    VICII/spritecollisions/sprite-sprite-collision-cycle.prg \
    VICII/spritecollisions/sprite-gfx-collision-cycle.tas \
    VICII/spritecollisions/sprite-gfx-collision-cycle.prg
do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/$path" --output "$destination/$path"
done

for path in readme.txt fldscroll.s Makefile; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/fldscroll/$path" --output "$destination/VICII/fldscroll/$path"
done
for timing in 20 21 22 29 2A 2B; do
    path="VICII/fldscroll/fldscroll-$timing-60.prg"
    curl --fail --silent --show-error --location --create-dirs \
        "$base/$path" --output "$destination/$path"
    path="VICII/fldscroll/references/fldscroll-$timing-60.prg.png"
    curl --fail --silent --show-error --location --create-dirs \
        "$base/$path" --output "$destination/$path"
done

for path in spritedma/d017.txt spritedma/d017-54.tas spritedma/d017-57.tas \
    spritedma/Makefile border/readme.txt border/Makefile border/vborder.asm \
    border/vborder2.asm border/hvborder.asm; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$path" --output "$destination/VICII/$path"
done
for fixture in spritedma/d017-54 spritedma/d017-57 \
    spritedma/d017-54_ntsc spritedma/d017-57_ntsc \
    border/vborder-32-08 border/vborder-32-09 border/vborder-33-08 border/vborder-33-09 \
    border/vborder2-21 border/vborder2-22 border/vborder2-35 border/vborder2-36 \
    border/vborder2-63 border/vborder2-64 border/hvborder1 border/hvborder2; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$fixture.prg" --output "$destination/VICII/$fixture.prg"
    path="${fixture%/*}/references/${fixture##*/}.prg.png"
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$path" --output "$destination/VICII/$path"
done

printf 'VIC fixtures from %s are in %s\n' "$revision" "$destination"
