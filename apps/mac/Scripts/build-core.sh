#!/bin/sh
# Builds core/ for the Mac and regenerates the Swift bindings. Needs rustup, protoc and cmake.
set -eu
cd "$(dirname "$0")/../../../core"
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
target=aarch64-apple-darwin
cargo build -p ivy-core --release --target "$target"
out=../apps/mac/Generated
cargo run -q -p uniffi-bindgen -- generate --library "target/$target/release/libivy_core.a" --language swift --out-dir "$out"
# Swift finds a C module only under this name.
mv "$out/ivy_coreFFI.modulemap" "$out/module.modulemap"
