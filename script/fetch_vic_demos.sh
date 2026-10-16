#!/bin/sh
set -eu

# Original C64 programs and their source only, never emulator code or ROMs.
destination="${1:-.build/vic-demos}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

fetch() {
    name="$1"
    checksum="$2"
    curl --fail --silent --show-error --location \
        "https://cadaver.github.io/rants/$name.zip" --output "$temporary/$name.zip"
    printf '%s  %s\n' "$checksum" "$temporary/$name.zip" | shasum -a 256 --check
    mkdir -p "$destination/cadaver-$name"
    unzip -oq "$temporary/$name.zip" -d "$destination/cadaver-$name"
}

fetch multi c0858608acf350512f4f61d7100ceafbcfd1a9e381d8495320dbe3d5e7287755
fetch multi2 d50109b85ea4015b952dbd1ae38212dc1269ed519541d32ec453072cbbd47a59

# Published standalone test program; source is retained locally for inspection,
# not incorporated into Swift64 or redistributed under its MIT license.
revision=d4bad371e98e200bf0f8dbedbc1c1a6df5edb564
for path in License.txt SpriteMultiplexor/README.md \
    SpriteMultiplexor/TestData/TestMultiplexor9.prg \
    SpriteMultiplexor/TestData/TestBuildOptions9.a \
    SpriteMultiplexor/features/AssemblePre.a SpriteMultiplexor/features/AssemblePost.a \
    SpriteMultiplexor/SpriteMultiplexor.a SpriteMultiplexor/SpriteMultiplexorVars.a \
    SpriteMultiplexor/SpriteMultiplexorDefaultPattern.a \
    SpriteMultiplexor/SpriteMultiplexorDefaultPatternCode.a; do
    curl --fail --silent --show-error --location --create-dirs \
        "https://raw.githubusercontent.com/martinpiper/C64Public/$revision/$path" \
        --output "$destination/piper/${path##*/}"
done
printf '%s  %s\n' 2c390034bf745230012de9162569cf11bb44e4a728cf34ca180a850348d72f28 \
    "$destination/piper/TestMultiplexor9.prg" | shasum -a 256 --check

# Complete game, for local non-commercial validation only. Neither this PRG
# nor its artwork/source may be bundled with Swift64 releases.
curl --fail --silent --show-error --location \
    https://github.com/Fabrizio-Caruso/C64_Multiplexor_C_LIB/releases/download/befana2026/befana.prg \
    --output "$destination/befana2026.prg"
printf '%s  %s\n' 07b03ac803f7d731e305215793b67b94f528fc00daf655f0ff395511bf43f7da \
    "$destination/befana2026.prg" | shasum -a 256 --check
revision=5f1785bcd13c29056397c3190cec02288f764590
for path in games/befana/befana.c games/befana/doc_2026.txt src/generic_multiplexer.s; do
    curl --fail --silent --show-error --location --create-dirs \
        "https://raw.githubusercontent.com/Fabrizio-Caruso/C64_Multiplexor_C_LIB/$revision/$path" \
        --output "$destination/befana-source/${path##*/}"
done
# The release-era README predates the explicit non-commercial license notice.
curl --fail --silent --show-error --location \
    https://raw.githubusercontent.com/Fabrizio-Caruso/C64_Multiplexor_C_LIB/bcae0529d9f91621ab6da348e67bdd131d6b64b6/README.md \
    --output "$destination/befana-source/README.md"
# MIT-licensed original scrolling framework and its example cartridge. Keep
# the complete example (including game artwork) local, out of app releases.
revision=c634f6fa7004cc5bfb14df14dee6f9fa3fe20b1b
for file in exampleef.crt README.md raster.s memory.s defines.s main.s init.s \
    screen.s sprite.s input.s panel.s aligneddata.s script00.s actordata.s level.s; do
    curl --fail --silent --show-error --location --create-dirs \
        "https://raw.githubusercontent.com/cadaver/c64gameframework/$revision/$file" \
        --output "$destination/c64gameframework/$file"
done
printf '%s  %s\n' 3e1d6e2de8e7773cf6073bdf5c2a72073f1564ed38c73d9844ae57c22e87f239 \
    "$destination/c64gameframework/exampleef.crt" | shasum -a 256 --check
printf 'Original sprite-multiplexer demos and games are in %s\n' "$destination"
