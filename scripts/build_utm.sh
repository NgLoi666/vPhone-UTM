#!/bin/sh
set -e

command -v realpath >/dev/null 2>&1 || realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
BASEDIR="$(dirname "$(realpath $0)")"

usage () {
    echo "Usage: $(basename $0)  [-t teamid] [-k SDK] [-s scheme] [-a architecture] [-o output]"
    echo ""
    echo "  -t teamid        Team Identifier for app groups. Optional for iOS. Required for macOS."
    echo "  -k sdk           Target SDK. Default iphoneos. [iphoneos|iphonesimulator|xros|xrsimulator|macosx]"
    echo "  -s scheme        Target scheme. Default iOS/macOS depending on platform. [iOS|iOS-TCI|iOS-Remote|macOS]"
    echo "  -a architecture  Target architecture. Default arm64. [arm64|x86_64]"
    echo "  -o output        Output archive path. Default is current directory."
    echo ""
    exit 1
}

PRODUCT_BUNDLE_PREFIX="com.utmapp"
TEAM_IDENTIFIER=
ARCH=arm64
OUTPUT=$PWD
SDK=iphoneos
SCHEME=

while [ "x$1" != "x" ]; do
    case $1 in
    -t )
        TEAM_IDENTIFIER=$2
        shift
        ;;
    -a )
        ARCH=$2
        shift
        ;;
    -k )
        SDK=$2
        shift
        ;;
    -s )
        SCHEME=$2
        shift
        ;;
    -o )
        OUTPUT=$2
        shift
        ;;
    * )
        usage
        ;;
    esac
    shift
done

case $SDK in
macos )
    SCHEME="macOS"
    ;;
* )
    if [ -z "$SCHEME" ]; then
        SCHEME="iOS"
    fi
    ;;
esac

ARCH_ARGS=$(echo $ARCH | xargs printf -- "-arch %s ")
if [ ! -z "$TEAM_IDENTIFIER" ]; then
    TEAM_IDENTIFIER_PREFIX="TeamIdentifierPrefix=${TEAM_IDENTIFIER}."
fi

xcodebuild archive -archivePath "$OUTPUT" -scheme "$SCHEME" -sdk "$SDK" $ARCH_ARGS -configuration Release CODE_SIGNING_ALLOWED=NO $TEAM_IDENTIFIER_PREFIX
BUILT_PATH=$(find $OUTPUT.xcarchive -name '*.app' -type d | head -1)
APP_NAME=$(basename "$BUILT_PATH" .app)
MAIN_EXECUTABLE="$BUILT_PATH/Contents/MacOS/$APP_NAME"
# Only retain the target architecture to address < iOS 15 crash & save disk space
if [ "$SDK" == "iphoneos" ]; then
    find "$BUILT_PATH" -type f -path '*/Frameworks/*.dylib' | while read FILE; do
        if [[ $(lipo -info "$FILE") =~ "Architectures in the fat file" ]]; then
            lipo -thin $ARCH "$FILE" -output "$FILE"
        fi
    done
    find "$BUILT_PATH" -type d -path '*/Frameworks/*.framework' | while read FRAMEWORK; do
        FILE="${FRAMEWORK}"/$(basename "${FRAMEWORK%.*}")
        if [[ $(lipo -info "$FILE") =~ "Architectures in the fat file" ]]; then
            lipo -thin $ARCH "$FILE" -output "$FILE"
        fi
    done
fi
find "$BUILT_PATH" -type d -path '*/Frameworks/*.framework' -exec codesign --force --sign - --timestamp=none \{\} \;
if [ "$SDK" == "macosx" ]; then
    # always build with vm entitlements, package_mac.sh can strip it later
    # this way we can import into Xcode and re-sign from there
    UTM_ENTITLEMENTS="/tmp/utm.$$.entitlements"
    LAUNCHER_ENTITLEMENTS="/tmp/launcher.$$.entitlements"
    RENDERER_ENTITLEMENTS="/tmp/renderer.$$.entitlements"
    HELPER_ENTITLEMENTS="/tmp/helper.$$.entitlements"
    CLI_ENTITLEMENTS="/tmp/cli.$$.entitlements"
    cp "$BASEDIR/../Platform/macOS/macOS.entitlements" "$UTM_ENTITLEMENTS"
    cp "$BASEDIR/../QEMULauncher/QEMULauncher.entitlements" "$LAUNCHER_ENTITLEMENTS"
    cp "$BASEDIR/../QEMURenderServer/QEMURenderServer.entitlements" "$RENDERER_ENTITLEMENTS"
    cp "$BASEDIR/../QEMUHelper/QEMUHelper.entitlements" "$HELPER_ENTITLEMENTS"
    cp "$BASEDIR/../utmctl/utmctl.entitlements" "$CLI_ENTITLEMENTS"
    if [ ! -z "$TEAM_IDENTIFIER" ]; then
        TEAM_ID_PREFIX="${TEAM_IDENTIFIER}."
    fi

    /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${TEAM_ID_PREFIX}${PRODUCT_BUNDLE_PREFIX}.UTM" "$UTM_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${TEAM_ID_PREFIX}${PRODUCT_BUNDLE_PREFIX}.UTM" "$HELPER_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${TEAM_ID_PREFIX}${PRODUCT_BUNDLE_PREFIX}.UTM" "$CLI_ENTITLEMENTS"
    # nested bundles must be signed before the XPC service that contains them
    codesign --force --sign - --entitlements "$LAUNCHER_ENTITLEMENTS" --timestamp=none --options runtime "$BUILT_PATH/Contents/XPCServices/QEMUHelper.xpc/Contents/MacOS/QEMULauncher.app/Contents/MacOS/QEMULauncher"
    codesign --force --sign - --entitlements "$RENDERER_ENTITLEMENTS" --timestamp=none --options runtime "$BUILT_PATH/Contents/XPCServices/QEMUHelper.xpc/Contents/MacOS/QEMURenderServer.app/Contents/MacOS/QEMURenderServer"
    codesign --force --sign - --entitlements "$HELPER_ENTITLEMENTS" --timestamp=none --options runtime "$BUILT_PATH/Contents/XPCServices/QEMUHelper.xpc/Contents/MacOS/QEMUHelper"
    codesign --force --sign - --entitlements "$CLI_ENTITLEMENTS" --timestamp=none --options runtime "$BUILT_PATH/Contents/MacOS/utmctl"
    codesign --force --sign - --entitlements "$UTM_ENTITLEMENTS" --timestamp=none --options runtime "$MAIN_EXECUTABLE"
    rm "$UTM_ENTITLEMENTS"
    rm "$LAUNCHER_ENTITLEMENTS"
    rm "$RENDERER_ENTITLEMENTS"
    rm "$HELPER_ENTITLEMENTS"
    rm "$CLI_ENTITLEMENTS"

    # Keep a directly openable .app next to the archive. The output base path
    # stays stable across rebuilds, so a Finder alias or Dock item keeps working.
    BUILT_APP_OUTPUT="${OUTPUT}.app"
    rm -rf "$BUILT_APP_OUTPUT"
    ditto "$BUILT_PATH" "$BUILT_APP_OUTPUT"
    echo "Application: $BUILT_APP_OUTPUT"

    LATEST_APP_OUTPUT="$BASEDIR/../.build/vPhone.app"
    rm -rf "$LATEST_APP_OUTPUT"
    ditto "$BUILT_PATH" "$LATEST_APP_OUTPUT"
    # The archive is prepared with sandbox entitlements for Xcode/export.
    # For direct local Finder launching, use an ad-hoc signed, unsandboxed copy.
    codesign --force --deep --sign - --timestamp=none --options runtime "$LATEST_APP_OUTPUT"
    # usbredirhost is an independently signed bundled framework. Disable
    # library validation only for this local, ad-hoc build so Finder can
    # launch it on the user's development Mac.
    codesign --force --sign - --entitlements "$BASEDIR/../Platform/macOS/local-launch.entitlements" --timestamp=none --options runtime "$LATEST_APP_OUTPUT"
    codesign --verify --deep --strict "$LATEST_APP_OUTPUT"
    xattr -dr com.apple.quarantine "$LATEST_APP_OUTPUT" 2>/dev/null || true
    echo "Stable application: $LATEST_APP_OUTPUT"

    # Keep the old technical name as a compatibility copy, but use vPhone.app
    # for Finder/manual launching so the bundle name stays stable.
    LEGACY_APP_OUTPUT="$BASEDIR/../.build/vPhone-latest.app"
    rm -rf "$LEGACY_APP_OUTPUT"
    ditto "$LATEST_APP_OUTPUT" "$LEGACY_APP_OUTPUT"
    echo "Compatibility application: $LEGACY_APP_OUTPUT"
fi
