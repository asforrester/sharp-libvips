#!/usr/bin/env bash
set -e

# bash build.sh 8.15.0
# bash build.sh 8.15.0 linux-x64
# tar -xzC "npm/linux-x64" -f libvips-8.15.0-linux-x64.tar.gz
# https://github.com/lovell/sharp-libvips/compare/main...bru02:sharp-libvips:main#diff-15fe4217ccf5f305b4bb5645dadf5970e32ed9d45d0366118a76376f8d0e1eae

if [ $# -lt 1 ]; then
  echo
  echo "Usage: $0 VERSION [PLATFORM]"
  echo "Build shared libraries for libvips and its dependencies via containers"
  echo
  echo "Please specify the libvips VERSION, e.g. 8.9.2"
  echo
  echo "Optionally build for only one PLATFORM, defaults to building for all"
  echo
  echo "Possible values for PLATFORM are:"
  echo "- win32-ia32"
  echo "- win32-x64"
  echo "- win32-arm64v8"
  echo "- linux-x64"
  echo "- linuxmusl-x64"
  echo "- linux-armv6"
  echo "- linux-armv7"
  echo "- linux-arm64v8"
  echo "- linuxmusl-arm64v8"
  echo "- linux-s390x"
  echo "- darwin-x64"
  echo "- darwin-arm64v8"
  echo
  exit 1
fi
VERSION_VIPS="$1"
PLATFORM="${2:-all}"

# macOS
# Note: we intentionally don't build these binaries inside a Docker container
for flavour in darwin-x64 darwin-arm64v8; do
  if [ $PLATFORM = $flavour ] && [ "$(uname)" == "Darwin" ]; then
    echo "Building $flavour..."

    # Use Clang provided by XCode
    export CC="clang"
    export CXX="clang++"

    export VERSION_VIPS
    export PLATFORM

    # Use pkg-config provided by Homebrew
    export PKG_CONFIG="$(brew --prefix)/bin/pkg-config --static"

    # Earliest supported version of macOS
    export MACOSX_DEPLOYMENT_TARGET="10.13"

    # Added -fno-stack-check to workaround a stack misalignment bug on macOS 10.15
    # See:
    # https://forums.developer.apple.com/thread/121887
    # https://trac.ffmpeg.org/ticket/8073#comment:12
    export FLAGS="-fno-stack-check"
    # Prevent use of API newer than the deployment target
    export FLAGS+=" -Werror=unguarded-availability-new"
    export MESON="--cross-file=$PWD/platforms/$PLATFORM/meson.ini"

    if [ $PLATFORM = "darwin-arm64v8" ]; then
      # ARM64 builds work via cross compilation from an x86_64 machine
      export CHOST="aarch64-apple-darwin"
      export FLAGS+=" -target arm64-apple-macos11"
      # macOS 11 Big Sur is the first version to support ARM-based macs
      export MACOSX_DEPLOYMENT_TARGET="11.0"
      # Set SDKROOT to the latest SDK available
      export SDKROOT=$(xcrun -sdk macosx --show-sdk-path)
    fi

    . $PWD/build/mac.sh

    exit 0
  fi
done

# Is docker available?
if ! [ -x "$(command -v docker)" ]; then
  echo "Please install docker"
  exit 1
fi

# WebAssembly
if [ "$PLATFORM" == "wasm32" ]; then
  ./build/wasm.sh "${VERSION_VIPS}"
  exit 0
fi

# Update base images
for baseimage in alpine:3.15 amazonlinux:2 debian:bullseye debian:buster; do
  docker pull $baseimage
done

# --rm Automatically remove the container when it exits
# -e Set environment variables
# -v Bind mount a volume
# set -e option instructs the shell to exit immediately if any command or pipeline returns a non-zero exit status
# -t tag an image

# https://github.com/lovell/sharp-libvips/compare/main...bru02:sharp-libvips:main#diff-15fe4217ccf5f305b4bb5645dadf5970e32ed9d45d0366118a76376f8d0e1eae

# "include-regex": "(sharp-.+\\.node|libvips-.+\\.dll)",

# populate.sh basically just the same as unzipping prebuilt with tar
# tar -xzC "npm/linux-x64" -f libvips-8.15.0-linux-x64.tar.gz

# Windows
for flavour in win32-ia32 win32-x64 win32-arm64v8; do
  if [ $PLATFORM = "all" ] || [ $PLATFORM = $flavour ]; then
    echo "Building $flavour..."
    docker build -t vips-dev-win32 platforms/win32
    # https://stackoverflow.com/a/64981627
    # https://stackoverflow.com/questions/35315996/how-do-i-mount-a-docker-volume-while-using-a-windows-host
    # https://stackoverflow.com/questions/48159422/how-to-actually-bind-mount-a-file-in-docker-for-windows
    # https://docs.docker.com/desktop/troubleshoot/topics/#path-conversion-on-windows
    # https://stackoverflow.com/questions/29045140/env-bash-r-no-such-file-or-directory
    docker run --rm -e "VERSION_VIPS=${VERSION_VIPS}" -e "PLATFORM=${flavour}" -v /$(pwd):/packaging vips-dev-win32 sh -c "//packaging//build//win.sh"
  fi
done



# Linux (x64, ARMv6, ARMv7, ARM64v8)
for flavour in linux-x64 linuxmusl-x64 linux-armv6 linux-armv7 linux-arm64v8 linuxmusl-arm64v8 linux-s390x; do
  if [ $PLATFORM = "all" ] || [ $PLATFORM = $flavour ]; then
    echo "Building $flavour..."
    docker build -t vips-dev-$flavour platforms/$flavour
    docker run --rm -e "VERSION_VIPS=${VERSION_VIPS}" -e VERSION_LATEST_REQUIRED -v /$(pwd):/packaging vips-dev-$flavour bash -c "//packaging//build//lin.sh"
  fi
done
