#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${THEOS:-$HOME/theos}/toolchain/linux/iphone/bin/clang"
command -v gnustep-config >/dev/null || {
    printf '%s\n' 'Host tests require libgnustep-base-dev (WSL only).' >&2
    exit 1
}
test_dir="$(mktemp -d /tmp/classicalguide-tests.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
cd "$test_dir"
read -r -a objc_flags <<< "$(gnustep-config --objc-flags)"
read -r -a base_libs <<< "$(gnustep-config --base-libs)"
"$compiler" --target=x86_64-linux-gnu "${objc_flags[@]}" \
    -I"$(gcc -print-file-name=include)" -I"$project_dir/Sources" \
    -Wall -Wextra -Werror -Wno-unused-command-line-argument \
    "$project_dir/Sources/CGDTrackReader.m" "$project_dir/Tests/TrackReaderTests.m" \
    -o "$test_dir/track-reader-tests" "${base_libs[@]}"
"$test_dir/track-reader-tests"

# Run real storage code against a narrowly scoped Security double. This checks
# failure behavior and secret handling, not iOS Keychain entitlements/encryption.
"$compiler" --target=x86_64-linux-gnu "${objc_flags[@]}" \
    -I"$(gcc -print-file-name=include)" -I"$project_dir/Tests/Support" -I"$project_dir/Sources" \
    -Wall -Wextra -Werror -Wno-unused-command-line-argument \
    "$project_dir/Sources/CGDSettingsStore.m" "$project_dir/Tests/SettingsStoreTests.m" \
    -o "$test_dir/settings-store-tests" "${base_libs[@]}"
"$test_dir/settings-store-tests"

# Run request/privacy, response/error validation, catalog preservation and the
# bounded persistent cache against synthetic data. No API key or network used.
"$compiler" --target=x86_64-linux-gnu "${objc_flags[@]}" \
    -I"$(gcc -print-file-name=include)" -I"$project_dir/Sources" \
    -Wall -Wextra -Werror -Wno-unused-command-line-argument \
    "$project_dir/Sources/CGDLocalization.m" "$project_dir/Sources/CGDGuideLanguage.m" \
    "$project_dir/Sources/CGDGuideData.m" "$project_dir/Sources/CGDGuideCache.m" "$project_dir/Sources/CGDGuidePrompts.m" \
    "$project_dir/Tests/GuideDataTests.m" -o "$test_dir/guide-data-tests" "${base_libs[@]}"
"$test_dir/guide-data-tests"

"$compiler" --target=x86_64-linux-gnu "${objc_flags[@]}" \
    -I"$(gcc -print-file-name=include)" -I"$project_dir/Sources" \
    -Wall -Wextra -Werror -Wno-unused-command-line-argument \
    "$project_dir/Sources/CGDLocalization.m" "$project_dir/Sources/CGDGuideLanguage.m" \
    "$project_dir/Sources/CGDGuideData.m" "$project_dir/Sources/CGDGuidePrompts.m" \
    "$project_dir/Sources/CGDGuideModuleCache.m" "$project_dir/Sources/CGDGuideLibrary.m" \
    "$project_dir/Tests/ModuleWorkflowTests.m" -o "$test_dir/module-workflow-tests" "${base_libs[@]}"
"$test_dir/module-workflow-tests"

"$compiler" --target=x86_64-linux-gnu "${objc_flags[@]}" \
    -I"$(gcc -print-file-name=include)" -I"$project_dir/Sources" \
    -Wall -Wextra -Werror -Wno-unused-command-line-argument \
    "$project_dir/Sources/CGDGuideLanguage.m" "$project_dir/Sources/CGDModulePreferences.m" \
    "$project_dir/Tests/GuideLanguageTests.m" -o "$test_dir/guide-language-tests" "${base_libs[@]}"
"$test_dir/guide-language-tests"

"$compiler" --target=x86_64-linux-gnu "${objc_flags[@]}" \
    -I"$(gcc -print-file-name=include)" -I"$project_dir/Sources" \
    -Wall -Wextra -Werror -Wno-unused-command-line-argument \
    "$project_dir/Sources/CGDLocalization.m" "$project_dir/Sources/CGDGuideLanguage.m" \
    "$project_dir/Sources/CGDGuideData.m" "$project_dir/Sources/CGDGuidePrompts.m" \
    "$project_dir/Sources/CGDGuideModuleCache.m" "$project_dir/Tests/LocalizationTests.m" \
    -o "$test_dir/localization-tests" "${base_libs[@]}"
"$test_dir/localization-tests"

# Actual shared page-selection code with names observed in the phone report.
"$compiler" --target=x86_64-linux-gnu "${objc_flags[@]}" \
    -I"$(gcc -print-file-name=include)" -I"$project_dir/Sources" \
    -Wall -Wextra -Werror -Wno-unused-command-line-argument \
    "$project_dir/Tests/PageTargetTests.m" -o "$test_dir/page-target-tests" "${base_libs[@]}"
"$test_dir/page-target-tests"

# Run the exact geometry used by the entry against static and video layouts.
"$compiler" --target=x86_64-linux-gnu -I"$project_dir/Sources" -Wall -Wextra -Werror \
    "$project_dir/Tests/EntryPlacementTests.c" -lm -o "$test_dir/entry-placement-tests"
"$test_dir/entry-placement-tests"

# Exercise the actual Spotify hook source with an adapter double. UIKit is not
# emulated; these tests cover hook gating, chaining, arguments and return values.
cp "$project_dir/Tests/Support/CGDAdapter.h" "$test_dir/CGDAdapter.h"
cp "$project_dir/Sources/SpotifyHooks.x" "$test_dir/SpotifyHooks.x"
perl "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal \
    "$test_dir/SpotifyHooks.x" > "$test_dir/SpotifyHooks.m"
# Apple's untyped SEL permits pointer equality; GNU's typed SEL does not.
# Adapt only this runtime comparison in the TEMPORARY host-test generation.
# The iOS build continues to use unmodified Logos output.
python3 - "$test_dir/SpotifyHooks.m" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
source = path.read_text()
old = "method_getName(_methods[_i]) == _cmd"
assert source.count(old) == 1, "Unexpected Logos generator; inspect host adapter"
path.write_text(source.replace(old, "sel_isEqual(method_getName(_methods[_i]), _cmd)"))
PY
"$compiler" --target=x86_64-linux-gnu "${objc_flags[@]}" \
    -I"$(gcc -print-file-name=include)" -I"$test_dir" -I"$project_dir/Sources" \
    -Wall -Wextra -Werror -Wno-unused-command-line-argument \
    "$project_dir/Sources/CGDTrackReader.m" "$test_dir/SpotifyHooks.m" \
    "$project_dir/Tests/HookTests.m" -o "$test_dir/hook-tests" "${base_libs[@]}"
"$test_dir/hook-tests"
