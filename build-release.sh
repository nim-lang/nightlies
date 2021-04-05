#!/usr/bin/env bash

# Build release tarball/zip from a source package
#
# Copyright (c) 2020 Leorize <leorize+oss@disroot.org>
#
# This script is licensed under the MIT license.

usage() {
  cat << EOF
Usage: $0 [-o folder] [-v version] <source>
Build a binary Nim release from the specified source folder. This folder is
assumed to be created from a standard Nim source archive.

Options:
    -o folder   Where to output the resulting artifacts. Defaults to $PWD/output.
    -d folder   Where dependencies are downloaded into. Defaults to $PWD/external.
    -r revision Add "-revision" to the binary archive name.
    -h          This help message.

Environment Variables:
    CC          The compiler used to build csources.
    CFLAGS      Flags to pass to C compilers when building C code.
    LDFLAGS     Flags to pass to C compilers when linking C code.
EOF
}

set -e
set -o pipefail

basedir=$(cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)
# shellcheck source=lib.sh
source "$basedir/lib.sh"

output=$PWD/output
outrel=$PWD
deps=$PWD/external
revision=
while getopts "o:d:r:h" curopt; do
  case "$curopt" in
    'o')
      output=$(realpath "$OPTARG")
      ;;
    'd')
      deps=$(realpath "$OPTARG")
      ;;
    'r')
      revision=$OPTARG
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

if [[ $# -lt 1 ]]; then
  echo "$0: missing required argument -- <source>"
  usage
  exit 1
fi

if [[ -e $deps/environment ]]; then
  echo "Sourcing dependencies environment"
  # shellcheck source=/dev/null
  source "$deps/environment"
fi

mkdir -p "$output"

cd "$1"

if [[ $(os) == darwin ]]; then
  : "${CC:=clang}"
else
  : "${CC:=gcc}"
fi

export PATH=$PWD/bin${PATH:+:$PATH}

TIMEFORMAT="Took %lR"

cpu=$(arch_from_triple "$($CC -dumpmachine)")

cat <<EOF
====== Environment Information ======
CPU: $cpu

C compiler:
$($CC -v 2>&1)
EOF

time {
  fold "Build 1-stage csources compiler"
  make "-j$(ncpu)" ucpu="$cpu" CC="$CC"
  endfold
}

buildtmp=$PWD/build

mkdir -p -- "$buildtmp/nim"

export XDG_CONFIG_HOME=$buildtmp
export XDG_CACHE_HOME=$buildtmp/nimcache

rm -f "$buildtmp/nim/nim.cfg"

if [[ -n "$CFLAGS" ]]; then
  echo "passC%=\"\$CFLAGS\"" >> "$buildtmp/nim/nim.cfg"
fi

if [[ -n "$LDFLAGS" ]]; then
  echo "passL%=\"\$LDFLAGS\"" >> "$buildtmp/nim/nim.cfg"
fi

if [[ -e $deps/nim.cfg ]]; then
  echo "Importing configuration from $deps/nim.cfg"
  cat "$deps/nim.cfg" >> "$buildtmp/nim/nim.cfg"
fi

time {
  fold "Build koch"
  nim c koch
  endfold
}

time {
  fold "Build compiler"
  ./koch boot -d:release --skipUserCfg:off
  endfold
}

versionRegex='^Nim Compiler Version ([0-9]+\.[0-9]+\.[0-9]+) \[([a-zA-Z0-9]+): [a-zA-Z0-9]+\]'
if [[ $(nim --version 2>&1) =~ $versionRegex ]]; then
  version=${BASH_REMATCH[1]}
  os=$(tolowercase "${BASH_REMATCH[2]}")
fi

# Fail if the variables are not declared (ie. nim couldn't run)
: "${version:?}" "${os:?}"

cpusuffix=
case "$cpu" in
  i?86)
    cpusuffix=_x32
    ;;
  x86_64)
    cpusuffix=_x64
    ;;
  aarch64)
    cpusuffix=_arm64
    ;;
  *)
    cpusuffix=_$cpu
    ;;
esac

suffix=-${os}$cpusuffix

case "$os" in
  windows)
    time {
      fold "Generate release"

      mkdir -p web/upload/download

      # Package DLLs
      cp -t bin "$deps/windeps/"*

      nim c --outdir:. tools/winrelease
      ./winrelease

      artifact=$output/nim-$version${revision:+-$revision}$suffix.zip
      cp "web/upload/download/nim-$version$cpusuffix.zip" "$artifact"

      echo "Generated release artifact at $artifact"
      echo "$artifact" > "$output/nim.txt"
      endfold
    }
    ;;
  *)
    time {
      fold "Build tools"
      ./koch tools -d:release
      endfold
    }

    major=${version%%.*}
    minor=${version#*.}
    minor=${minor%.*}
    patch=${version##*.}
    doc=(docs -d:release)
    if [[ $major -ge 1 && $minor -ge 3 && $patch -ge 5 ]]; then
      # Skip runnable examples and web docs build when supported. This speeds
      # up the build by a huge margin, esp. on non-native archs.
      doc=(--localdocs "${doc[@]}" --doccmd:skip)
    fi
    time {
      fold "Build docs"
      # Build release docs
      ./koch "${doc[@]}"
      endfold
    }

    time {
      fold "Generate release"
      # Cleanup build artifacts
      # TODO: Rework niminst to be able to build binary archives for non-Windows
      rm -rf "$buildtmp"
      find . \
        -mindepth 1 \
        \( \
          -name .git -prune -o \
          -name c_code -prune -o \
          -name nimcache -prune -o \
          -name web -prune -o \
          -name build.sh -o \
          -name 'build*.bat' -o \
          -name makefile -o \
          -name '*.o' -o \
          -path '*/compiler/nim' -o \
          -path '*/compiler/nim?' \
        \) \
        -exec rm -rf '{}' +

      cd ..

      srcDir=$(basename "$1")
      if [[ $srcDir != "nim-$version" ]]; then
        # This is for people who build this locally...
        ln -sf "$srcDir" "nim-$version"
      fi

      artifact=$output/nim-$version${revision:+-$revision}$suffix.tar
      tar chf "$artifact" "nim-$version"
      xz -9e "$artifact"
      artifact=$artifact.xz

      echo "Generated release artifact at $artifact"
      echo "$artifact" > "$output/nim.txt"
      endfold
    }
    ;;
esac
