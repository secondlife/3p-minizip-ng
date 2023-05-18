#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

MINIZLIB_SOURCE_DIR="minizip-ng"

top="$(pwd)"
stage="$top"/stage

[ -f "$stage"/packages/include/zlib-ng/zlib.h ] || \
{ echo "You haven't yet run 'autobuild install'." 1>&2; exit 1; }

# load autobuild provided shell functions and variables
case "$AUTOBUILD_PLATFORM" in
    windows*)
        autobuild="$(cygpath -u "$AUTOBUILD")"
    ;;
    *)
        autobuild="$AUTOBUILD"
    ;;
esac
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

VERSION_HEADER_FILE="$MINIZLIB_SOURCE_DIR/mz.h"
version=$(sed -n -E 's/#define MZ_VERSION[ ]+[(]"([0-9.]+)"[)]/\1/p' "${VERSION_HEADER_FILE}")
build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

pushd "$MINIZLIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" . \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DMZ_COMPAT=ON \
                  -DMZ_BUILD_TEST=ON \
                  -DMZ_FETCH_LIBS=OFF\
                  -DMZ_BZIP2=OFF \
                  -DMZ_LIBBSD=OFF \
                  -DMZ_LZMA=OFF \
                  -DMZ_OPENSSL=OFF \
                  -DMZ_PKCRYPT=OFF \
                  -DMZ_SIGNING=OFF \
                  -DMZ_WZAES=OFF \
                  -DZLIB_INCLUDE_DIRS="$(cygpath -m $stage)/packages/include/zlib-ng/" \
                  -DZLIB_LIBRARIES="$(cygpath -m $stage)/packages/lib/release/zlib.lib"


            cmake --build . --config Release

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                ctest -C Release
            fi

            mkdir -p "$stage/lib/release"
            cp -a "Release/libminizip.lib" "$stage/lib/release/"

            mkdir -p "$stage/include/minizip-ng"
            cp -a *.h "$stage/include/minizip-ng"
        ;;

        # ------------------------- darwin, darwin64 -------------------------
        darwin*)

            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE}"

            # As of version 3.0.2 (2023-05-18), we get:
            # clang: warning: overriding '-mmacosx-version-min=10.13' option
            # with '-target x86_64-apple-macos11.7' [-Woverriding-t-option]
            # We didn't specify -target explicitly before; try setting it.
            # (_find and _test_re from build-variables/functions script)
            if idx=$(_find _test_re "-mmacosx-version-min=.*" $opts)
            then
                optarray=($opts)
                versw="${optarray[$idx]}"
                minver="${versw#*=}"
                optarray+=(-target "x86_64-apple-macos$minver")
                opts="${optarray[*]}"
            fi

            mkdir -p "$stage/lib/release"
            rm -rf Resources/ ../Resources tests/Resources/

            cmake ../${MINIZLIB_SOURCE_DIR} -GXcode \
                  -DCMAKE_C_FLAGS:STRING="$(remove_cxxstd $opts)" \
                  -DCMAKE_CXX_FLAGS:STRING="$opts" \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DMZ_COMPAT=ON \
                  -DMZ_BUILD_TEST=ON \
                  -DMZ_FETCH_LIBS=OFF \
                  -DMZ_BZIP2=OFF \
                  -DMZ_LIBBSD=OFF \
                  -DMZ_LZMA=OFF \
                  -DMZ_OPENSSL=OFF \
                  -DMZ_PKCRYPT=OFF \
                  -DMZ_SIGNING=OFF \
                  -DMZ_WZAES=OFF \
                  -DMZ_LIBCOMP=OFF \
                  -DCMAKE_INSTALL_PREFIX=$stage \
                  -DZLIB_INCLUDE_DIRS="$stage/packages/include/zlib-ng/" \
                  -DZLIB_LIBRARIES="$stage/packages/lib/release/libz.a"

            cmake --build . --config Release

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                ctest -C Release
            fi

            mkdir -p "$stage/lib/release"
            cp -a Release/libminizip*.a* "${stage}/lib/release/"

            mkdir -p "$stage/include/minizip-ng"
            cp -a *.h "$stage/include/minizip-ng"
        ;;            

        # -------------------------- linux, linux64 --------------------------
        linux*)

            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Prefer gcc-4.6 if available.
            if [[ -x /usr/bin/gcc-4.6 && -x /usr/bin/g++-4.6 ]]; then
                export CC=/usr/bin/gcc-4.6
                export CXX=/usr/bin/g++-4.6
            fi

            # Prefer out of source builds
            rm -rf build
            mkdir -p build
            pushd build
        
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            # Handle any deliberate platform targeting
            if [ ! "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            cmake ${top}/${MINIZLIB_SOURCE_DIR} -G"Unix Makefiles" \
                  -DCMAKE_C_FLAGS:STRING="$(remove_cxxstd $opts)" \
                  -DCMAKE_CXX_FLAGS:STRING="$opts" \
                  -DBUILD_SHARED_LIBS=OFF \
                  -DMZ_COMPAT=ON \
                  -DMZ_BUILD_TEST=ON \
                  -DMZ_FETCH_LIBS=OFF \
                  -DMZ_BZIP2=OFF \
                  -DMZ_LIBBSD=OFF \
                  -DMZ_LZMA=OFF \
                  -DMZ_OPENSSL=OFF \
                  -DMZ_PKCRYPT=OFF \
                  -DMZ_SIGNING=OFF \
                  -DMZ_WZAES=OFF \
                  -DCMAKE_INSTALL_PREFIX=$stage \
                  -DZLIB_INCLUDE_DIRS="$stage/packages/include/zlib-ng/" \
                  -DZLIB_LIBRARIES="$stage/packages/lib/release/libz.a"

            cmake --build . --parallel 8  --config Release

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" -eq 0 ]; then
                ctest -C Release
            fi

            mkdir -p "$stage/lib/release"
            cp -a libminizip*.a* "${stage}/lib/release/"

            mkdir -p "$stage/include/minizip-ng"
            cp -a ${top}/${MINIZLIB_SOURCE_DIR}/*.h "$stage/include/minizip-ng"

        popd
        ;;
    esac

    mkdir -p "$stage/LICENSES"
    cp LICENSE "$stage/LICENSES/minizip-ng.txt"
popd

mkdir -p "$stage"/docs/minizip-ng/
cp -a README.Linden "$stage"/docs/minizip-ng/
