#!/bin/sh
# Check the binary products selected by Xcode before compiling Demo sources.
set -eu

products=${1:?Usage: verify-sdk.sh BUILT_PRODUCTS_DIR SDK_VERSION}
expected_version=${2:?SDK version is required}
sdk_build=

for name in HiFace HiFaceNative; do
    info="$products/$name.framework/Info.plist"
    if [ ! -f "$info" ]; then
        echo "error: $name.framework is missing. Build or install the matching binary SDK package before building this Demo." >&2
        exit 1
    fi
    version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info") || exit 1
    build=$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info") || exit 1
    case "$build" in
        ''|0*|*[!0-9]*)
            echo "error: $name SDK has an invalid build number. Replace the incomplete binary SDK package." >&2
            exit 1
            ;;
    esac
    if [ "$version" != "$expected_version" ]; then
        echo "error: $name SDK $version (build $build) does not match Demo SDK $expected_version. Replace the stale binary SDK package; this check does not rebuild it." >&2
        exit 1
    fi
    if [ -n "$sdk_build" ] && [ "$build" != "$sdk_build" ]; then
        echo "error: $name SDK build $build differs from the matching Framework build $sdk_build. Replace the mixed binary SDK package." >&2
        exit 1
    fi
    sdk_build=$build
done

echo "Verified both binary SDK products: $expected_version (build $sdk_build)."
