#!/usr/bin/env bash

# Install build dependencies for nightlies CI
#
# Copyright (c) 2020 Leorize <leorize+oss@disroot.org>
#
# This script is licensed under the MIT license.

# NOTE: Editing this script will cause dependencies to be redownloaded

# shellcheck disable=SC2034
_rev=3 # Bump this variable if dependencies should be redownloaded.
       # This variable does not change the script behavior in anyway, but
       # will trigger a cache mismatch for CI services configured to hash
       # the script as part of the cache key.

usage() {
  cat << EOF
Usage: $0 [-o folder] [-t triple]
Download build dependencies and configure environment for building nightlies.
This script is designed for use with CI services. Tread carefully for local
usage.

Options:
    -o folder  Where to download and install dependencies to. Defaults to
               $PWD/external. If the folder already exists, it's assumed to
               have been restored from a cache and configuration will take
               place immediately.
    -t triple  Specify the target triple for package downloads, if unspecified
               will be automatically detected. On Linux/Windows this is used to
               determine which toolchain should be downloaded.
    -h         This help message.
EOF
}

set -e
set -o pipefail

basedir=$(cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)
# shellcheck source=lib.sh
source "$basedir/lib.sh"

output=$PWD/external
triple=$(gcc -dumpmachine)
while getopts "o:t:a:h" curopt; do
  case "$curopt" in
    'o')
      output=$(realpath "$OPTARG")
      ;;
    't')
      triple=$OPTARG
      ;;
    'h')
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ ! -d $output ]]; then
  mkdir -p "$output"
  cd "$output"

  case "$(os)" in
    windows)
      arch=$(arch_from_triple "$triple")
      case "$arch" in
        i?86)
          arch=32
          ;;
        x86_64)
          arch=64
          ;;
        *)
          error "unsupported target: $triple"
          exit 1
          ;;
      esac
      curl -L "https://nim-lang.org/download/mingw$arch.7z" -o "mingw$arch.7z"
      curl -L "https://nim-lang.org/download/windeps.zip" -o "windeps.zip"

      7z x "mingw$arch.7z"
      7z x -owindeps windeps.zip

      rm -f "mingw$arch.7z" windeps.zip
      ;;
    linux)
      # NOTE: This key is expired and it appears from the authors page that this
      #       is intentional.
      # curl -L https://zv.io/BE4BF7E6811C5BA41345C11EB1D0B4566FBBDB40.asc | gpg --import

      toolchain=$triple-native
      toolchain_ver=10.2.1
      curl -LO "https://more.musl.cc/$toolchain_ver/i686-linux-musl/$toolchain.tgz"
      # curl -LO "https://more.musl.cc/$toolchain_ver/i686-linux-musl/$toolchain.tgz.sig"

      # gpg --quiet --verify -- "$toolchain.tgz.sig"
      tar xf "$toolchain.tgz"

      xargs < "$basedir/buildreq.txt" "$basedir/bw-install.sh" -o "$toolchain" -t "$triple"
      ;;
    darwin)
      xargs < "$basedir/buildreq.txt" "$basedir/bw-install.sh" -t "$triple"
      ;;
  esac
else
  cd "$output"
  echo "Using cached dependencies"
fi

unset libdir
rm -f nim.cfg
rm -f environment
cflags=()
libs=()
ldflags=()
case "$(os)" in
  windows)
    pushpath mingw*/bin windeps
    ;;
  linux | darwin)
    if [[ $(os) == linux ]]; then
      pushpath "$triple-native/bin"
      libdir=$(realpath "$triple-native/lib")
      ldflags+=(-static)
      case "$(arch_from_triple "$triple")" in
        i?86 | amd64)
          ;; # Native
        *)
          docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
          ;;
      esac

      # Starting from musl 1.2.0, time_t is 64 bit on all arches
      echo "-d:nimUse64BitCTime" >> nim.cfg
    else
      if [[ $triple == "arm64-apple" ]]; then
        libdir="/opt/homebrew/lib"
      else
        libdir=$(realpath lib)
      fi
      cflags+=(-target "$triple")
    fi
    libs+=(libssl.a libcrypto.a libpcre.a libsqlite3.a)
    ldflags+=("${libs[@]/#/$libdir/}")

    cat <<EOF >> nim.cfg
dynlibOverride="ssl"
dynlibOverrideAll="on"
EOF

    pushenv LDFLAGS "${ldflags[*]}" CFLAGS "${cflags[*]}"
    ;;
esac
