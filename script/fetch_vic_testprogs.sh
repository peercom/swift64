#!/bin/sh
set -eu

# Public test programs only, never emulator implementation or machine ROMs.
revision="ef8e8efe52f3d43df7acefad132c6506239bddee"
destination="${1:-.build/vic-testprogs}"
base="https://raw.githubusercontent.com/libsidplayfp/VICE-testprogs/$revision"

for path in \
    readme.txt \
    interrupts/irq-ackn-bug/irq-ack-vicii.asm \
    interrupts/irq-ackn-bug/irq-ack-vicii.prg \
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

for file in readme.txt Makefile vic-ef.asm vic.asm \
    8k-vic-ef.crt 16k-vic-ef.crt ultimax-vic-ef.crt \
    references/8k-vic-ef.crt.png references/16k-vic-ef.crt.png references/ultimax-vic-ef.crt.png; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/C64/carts/ultimax/$file" --output "$destination/C64/carts/ultimax/$file"
done

for file in spritesteal/README.txt spritesteal/Makefile spritesteal/core.asm \
    spritesteal/spritesteal.prg spritesteal/spritesteal_ntsc.prg \
    spritex/testsuite.txt spritex/Makefile spritex/testsuite.tas \
    spritex/testsuite.prg spritex/testsuite_ntsc.prg; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$file" --output "$destination/VICII/$file"
done

for path in dentest/howto.txt dentest/Makefile D011Test/readme.txt D011Test/disable-bad.tas \
    D011Test/Makefile rasterirq/Makefile rasterirq/rasterirq_hold.asm \
    rasterirq/rasterirq_hold.prg rasterirq/references/rasterirq_hold.prg.png; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$path" --output "$destination/VICII/$path"
done
for fixture in den01-49-1 den01-49-2 den10-48-1 den10-48-2 denrsel-0 denrsel-1; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/dentest/$fixture.tas" --output "$destination/VICII/dentest/$fixture.tas"
done
for fixture in dentest/den01-49-1 dentest/den01-49-2 dentest/den10-48-1 \
    dentest/den10-48-2 dentest/denrsel-0 dentest/denrsel-1 D011Test/disable-bad; do
    for variant in "$fixture" "${fixture}_ntsc"; do
        for path in "$variant.prg" "${variant%/*}/references/${variant##*/}.prg.png"; do
            curl --fail --silent --show-error --location --create-dirs \
                "$base/VICII/$path" --output "$destination/VICII/$path"
        done
    done
done

for path in README.txt Makefile core1.asm core2.asm core3.asm core4.asm core5.asm; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/spriteenable/$path" --output "$destination/VICII/spriteenable/$path"
done
for number in 1 2 3 4 5; do
    for fixture in "spriteenable$number" "spriteenable${number}_ntsc"; do
        for path in "$fixture.asm" "$fixture.prg" "references/$fixture.prg.png"; do
            curl --fail --silent --show-error --location --create-dirs \
                "$base/VICII/spriteenable/$path" --output "$destination/VICII/spriteenable/$path"
        done
    done
done

for path in readme.txt Makefile spritecrunch.asm spritecrunch2.asm; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/spritecrunch/$path" --output "$destination/VICII/spritecrunch/$path"
done
# The 3b/3c/3d binaries are identical at this pinned revision.
for fixture in spritecrunch-3c-00 \
    spritecrunch2-07 spritecrunch2-08 spritecrunch2-09 \
    spritecrunch2-25 spritecrunch2-26 spritecrunch2-27 spritecrunch2-28 spritecrunch2-29; do
    for path in "$fixture.prg" "references/$fixture.prg.png"; do
        curl --fail --silent --show-error --location --create-dirs \
            "$base/VICII/spritecrunch/$path" --output "$destination/VICII/spritecrunch/$path"
    done
done

for path in readme.txt Makefile main.asm main2.asm main3.asm main4.asm bitmap.asm \
    main.prg main2.prg main3.prg main4.prg bitmap.prg \
    references/main.prg.png references/main2.prg.png references/main3.prg.png \
    references/main4.prg.png references/bitmap.prg.png; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/colorfetchbug/$path" --output "$destination/VICII/colorfetchbug/$path"
done

for path in readme.txt Makefile bug.asm bug.prg references/bug.prg.png; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/sequencer-bug/$path" --output "$destination/VICII/sequencer-bug/$path"
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
    border/vborder2.asm border/hvborder.asm border/border-bm-idle.tas \
    border/border-bm-ysh.tas border/border-bm-ysh2.tas border/border-mcbm.tas; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$path" --output "$destination/VICII/$path"
done
for fixture in spritedma/d017-54 spritedma/d017-57 \
    spritedma/d017-54_ntsc spritedma/d017-57_ntsc \
    border/vborder-32-08 border/vborder-32-09 border/vborder-33-08 border/vborder-33-09 \
    border/vborder2-21 border/vborder2-22 border/vborder2-35 border/vborder2-36 \
    border/vborder2-63 border/vborder2-64 border/hvborder1 border/hvborder2 \
    border/border-bm-idle border/border-bm-ysh border/border-bm-ysh2 border/border-mcbm; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$fixture.prg" --output "$destination/VICII/$fixture.prg"
    path="${fixture%/*}/references/${fixture##*/}.prg.png"
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$path" --output "$destination/VICII/$path"
done

for path in spritesplit.asm 8565.txt Makefile; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/spritesplit/$path" --output "$destination/VICII/spritesplit/$path"
done
for fixture in ss-hires-mc ss-hires-mc-exp ss-mc-hires ss-mc-hires-exp \
    ss-hires-color ss-mc-color0 ss-mc-color1 ss-mc-color2 ss-xpos \
    ss-unexp-exp-hires ss-exp-unexp-hires ss-unexp-exp-mc ss-exp-unexp-mc \
    ss-pri ss-pri-exp ss-pri-mc ss-pri-mc-exp; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/spritesplit/$fixture.prg" --output "$destination/VICII/spritesplit/$fixture.prg"
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/spritesplit/references/$fixture.prg.png" \
        --output "$destination/VICII/spritesplit/references/$fixture.prg.png"
done

for path in flibug/readme.txt flibug/blackmail.asm flibug/Makefile \
    gfxfetch/core.asm gfxfetch/gfxfetch.asm gfxfetch/gfxfetch_ntsc.asm gfxfetch/Makefile; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$path" --output "$destination/VICII/$path"
done
for fixture in flibug/blackmail-fixed gfxfetch/gfxfetch gfxfetch/gfxfetch_ntsc; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$fixture.prg" --output "$destination/VICII/$fixture.prg"
    path="${fixture%/*}/references/${fixture##*/}.prg.png"
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/$path" --output "$destination/VICII/$path"
done

for path in readme.txt Makefile sbsprf24.asm sbsprf24-163.prg sbsprf24-164.prg \
    references/sbsprf24-163.prg.png references/sbsprf24-164.prg.png; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/sb_sprite_fetch/$path" --output "$destination/VICII/sb_sprite_fetch/$path"
done

for path in readme.txt Makefile dmadelay.s test1.s test2.s test3.s; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/dmadelay/$path" --output "$destination/VICII/dmadelay/$path"
done
for method in 1 2 3; do
    case "$method" in
        1) pal_start=2a; ntsc_start=2e; delays='03 04 10 11 16 17 18' ;;
        2) pal_start=28; ntsc_start=2c; delays='05 06 11 12 16 17 18' ;;
        3) pal_start=28; ntsc_start=2c; delays='07 08 13 14 18 19 1a' ;;
    esac
    for delay in $delays; do
        for fixture in "test$method-$pal_start-$delay" "test$method-$ntsc_start-$delay-ntsc"; do
            curl --fail --silent --show-error --location --create-dirs \
                "$base/VICII/dmadelay/$fixture.prg" --output "$destination/VICII/dmadelay/$fixture.prg"
            curl --fail --silent --show-error --location --create-dirs \
                "$base/VICII/dmadelay/references/$fixture.prg.png" --output "$destination/VICII/dmadelay/references/$fixture.prg.png"
        done
    done
done

for path in readme.txt Makefile videomode1.tas videomode2.tas; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/videomode/$path" --output "$destination/VICII/videomode/$path"
done
# The older NTSC images do not match the current videomode binaries.
# Version-matched NTSC mode coverage comes from modesplit below.
for fixture in videomode1 videomode2; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/videomode/$fixture.prg" --output "$destination/VICII/videomode/$fixture.prg"
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/videomode/references/$fixture.prg.png" --output "$destination/VICII/videomode/references/$fixture.prg.png"
done

for path in modesplit/README.txt modesplit/Makefile modesplit/modesplit.asm \
    modesplit/modesplit.prg modesplit/references/modesplit.prg.png \
    modesplit/references/modesplit.prg-ntsc.png common/startup.asm common/onescreen.asm; do
    curl --fail --silent --show-error --location --create-dirs \
        "$base/VICII/split-tests/$path" --output "$destination/VICII/split-tests/$path"
done

printf 'VIC fixtures from %s are in %s\n' "$revision" "$destination"
