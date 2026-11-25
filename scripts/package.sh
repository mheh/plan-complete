#!/bin/sh
# scripts/package.sh BIN_DIR OUT_DIR
#
# BIN_DIR holds one folder for each platform that was built: darwin, linux-x64, linux-arm64, windows-x64.
# OUT_DIR gets one .vsix for each VS Code target with the server inside, plan-complete.vsix with no
# server, and one archive of each bare binary.
set -eu

bins=$(cd "$1" && pwd)
mkdir -p "$2"
out=$(cd "$2" && pwd)
cd "$(dirname "$0")/../editors/vscode"

npm run build
vsix() {
    npx vsce package --no-dependencies --allow-missing-repository "$@"
}

mkdir -p bin
rm -f bin/*
vsix --out "$out/plan-complete.vsix"

for pair in darwin:darwin-arm64 darwin:darwin-x64 linux-x64:linux-x64 linux-x64:alpine-x64 \
            linux-arm64:linux-arm64 linux-arm64:alpine-arm64 windows-x64:win32-x64; do
    platform=${pair%%:*}
    target=${pair##*:}
    [ -d "$bins/$platform" ] || continue
    rm -f bin/*
    cp "$bins/$platform"/* bin/
    chmod 755 bin/*
    vsix --target "$target" --out "$out/plan-complete-$target.vsix"
done
rm -f bin/*

for platform in darwin linux-x64 linux-arm64 windows-x64; do
    [ -d "$bins/$platform" ] || continue
    chmod 755 "$bins/$platform"/*
    if [ "$platform" = windows-x64 ]; then
        (cd "$bins/$platform" && zip -q -r "$out/plan-complete-$platform.zip" .)
    else
        tar -czf "$out/plan-complete-$platform.tar.gz" -C "$bins/$platform" .
    fi
done

ls -l "$out"
