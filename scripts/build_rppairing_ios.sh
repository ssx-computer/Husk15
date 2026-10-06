#!/bin/bash
# Build libhusk_rppairing.a (on-device remote pairing for Built-in StikJIT,
# src/app/Husk/JITPairing.swift) for iOS arm64 into build/ios-arm64/lib, where
# the app target already searches for libraries. The C interface is
# src/app/Husk/HuskRPPairing.h. See docs/06-built-in-jit.md.
#
# Dependencies come from crates.io at the versions in Cargo.lock (idevice is
# MIT, jkcoxson/idevice). Their licence notices are regenerated into
# src/app/Husk/Resources/legal/LICENSES-rppairing-crates.txt, which the app
# bundles. Needs rustup (the iOS target below is added here if missing)
# and python3.
set -euo pipefail

HUSK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$HUSK_ROOT/src/rppairing-ios"
OUT="$HUSK_ROOT/build/ios-arm64/lib"
TARGET=aarch64-apple-ios
# Match the app's deployment target (15.0), or the linker warns on every object.
export IPHONEOS_DEPLOYMENT_TARGET=15.0

# A fresh rustup has only the host's target, and the crate cannot build
# without the iOS one -- "can't find crate for `core`". Idempotent: already
# installed, this is a no-op.
if ! rustup target list --installed 2>/dev/null | grep -qx "$TARGET"; then
    echo "-> installing rust target $TARGET"
    rustup target add "$TARGET"
fi

cd "$CRATE"
cargo build --release --locked --target "$TARGET"
mkdir -p "$OUT"
cp "target/$TARGET/release/libhusk_rppairing.a" "$OUT/libhusk_rppairing.a"
echo "-> build/ios-arm64/lib/libhusk_rppairing.a"
python3 "$CRATE/notices.py" "$HUSK_ROOT/src/app/Husk/Resources/legal/LICENSES-rppairing-crates.txt"
