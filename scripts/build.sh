#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export THEOS="${THEOS:-$HOME/theos}"
tweak_name="$(sed -n 's/^TWEAK_NAME := //p' "$project_dir/Makefile")"
if [[ ! "$tweak_name" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    printf '%s\n' 'Invalid or missing TWEAK_NAME in Makefile.' >&2
    exit 1
fi
if [[ ! -f "$THEOS/makefiles/common.mk" ||
      ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ||
      ! -d "$THEOS/sdks/iPhoneOS16.5.sdk" ]]; then
    printf '%s\n' 'Missing Theos, iOS toolchain, or iPhoneOS16.5 SDK. See README.md.' >&2
    exit 1
fi

# Keep the build on Linux's native filesystem, not the Windows-mounted source.
cache_base="${XDG_CACHE_HOME:-$HOME/.cache}/classicalguide-builds"
mkdir -p -- "$cache_base"
build_dir="$(mktemp -d "$cache_base/build.XXXXXX")"
cleanup() {
    case "$build_dir" in
        "$cache_base"/build.*) rm -rf -- "$build_dir" ;;
        *) printf '%s\n' 'Unexpected build directory; refusing cleanup.' >&2 ;;
    esac
}
trap cleanup EXIT

mkdir -p "$build_dir/Sources"
cp -- "$project_dir/Makefile" "$project_dir/$tweak_name.plist" "$build_dir/"
cp -- "$project_dir"/Sources/*.[hmx] "$build_dir/Sources/"
make -C "$build_dir" -j2 all

binary="$build_dir/.theos/obj/$tweak_name.dylib"
python3 "$project_dir/scripts/verify_binary.py" "$binary"
mkdir -p -- "$project_dir/dist"
install -m 644 -- "$binary" "$project_dir/dist/$tweak_name.dylib"
printf 'Built: %s/dist/%s.dylib\n' "$project_dir" "$tweak_name"
sha256sum "$project_dir/dist/$tweak_name.dylib"
