#!/usr/bin/env bash

# Simple JuliaBinaryWrappers downloader for use with nightlies CI
#
# Copyright (c) 2020 Leorize <leorize+oss@disroot.org>
#
# This script is licensed under the MIT license.

usage() {
  cat << EOF
Usage: $0 [-o folder] [-t triple] <pkg>...
Downloads and installs packages from JuliaBinaryWrappers.

    <pkg>      The package specification, can be just the package name (ie.
               SQLite, OpenSSL) to get the latest version, or a tag name for an
               exact version (ie. SQLite-v3.31.1+0, OpenSSL-v1.1.1+2).

Options:
    -o folder  Where to install the specified packages to. If not specified the
               current folder will be used.
    -t triple  Specify the target triple for package downloads, if unspecified
               will be automatically detected.
    -h         This help message.
EOF
}

detectTriple() {
  case "$(uname -s)" in
    Darwin)
      if [[ $(uname -m) == x86_64 ]]; then
        # Hardcode this triple due to later OSX uses never version sufficies
        echo x86_64-apple-darwin14
      else
        echo Unsupported macOS version >&2
        return 1
      fi
      ;;
    *)
      result=$(gcc -dumpmachine)
      case "$result" in
        *-linux-*)
          result=${result/-pc/}
          result=${result/-unknown/}
          ;;
      esac
      echo "$result"
      ;;
  esac
}

getAsset() {
  pkg=${1%%-*}_jll.jl
  version=${1##*-}

  queryLatest='
query($repo: String!, $owner: String = "JuliaBinaryWrappers", $endCursor: String) {
  repository(name: $repo, owner: $owner) {
    releases(last: 1) {
      nodes {
        releaseAssets(first: 15, after: $endCursor) {
          nodes {
            ...assetFields
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
  }
}
'
  getAssetsLatest='.data | .repository | .releases | .nodes[0] | .releaseAssets | .nodes[]'

  queryExact='
query($tag: String!, $repo: String!, $owner: String = "JuliaBinaryWrappers", $endCursor: String) {
  repository(name: $repo, owner: $owner) {
    release(tagName: $tag) {
      releaseAssets(first: 15, after: $endCursor) {
        nodes {
          ...assetFields
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
'

  getAssetsExact='.data | .repository | .release | .releaseAssets | .nodes[]'

  assetFields='
fragment assetFields on ReleaseAsset {
  downloadUrl
  name
}
'

  declare -a hubParams

  if [[ $1 == $version ]]; then
    hubParams+=(-F "query=$queryLatest$assetFields" -F "repo=$pkg")
    getAssets=$getAssetsLatest
  else
    hubParams+=(-F "query=$queryExact$assetFields" -F "repo=$pkg" -F "tag=$1")
    getAssets=$getAssetsExact
  fi

  resp=$(gh api graphql --paginate "${hubParams[@]}") || exit 1

  if [[ $(jq 'has("errors")' <<< "$resp") == true ]]; then
    jq -r '.errors[] | .message' <<< "$resp" >&2
    return 1
  fi

  if [[ -z "$triple" ]]; then
    triple=$(detectTriple) || return 1
  fi

  jq -sr --arg triple "$triple" \
    '[ .[] | '"$getAssets"' | select(.name | contains($triple)) ]' <<< "$resp"
}

output=$PWD
triple=

while getopts "o:t:h" curopt; do
  case "$curopt" in
    'o')
      output=$OPTARG
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

if [[ $# -lt 1 ]]; then
  echo "$0: missing required argument -- <pkg>"
  usage
  exit 1
fi

mkdir -p "$output" || exit 1
cd "$output" || exit 1

if [[ $triple == "arm64-apple" ]]; then
  exit 0
fi

for pkg in "$@"; do
  asset=$(getAsset "$pkg") || exit 1
  case "$(jq 'length' <<< "$asset")" in
    1)
      ;;
    0)
      echo "Package $pkg not found for triple: $triple"
      exit 1
      
      ;;
    *)
      echo "Ambiguous triple '$triple'" >&2
      exit 1
      ;;
  esac
  asset=$(jq -r '.[0]' <<< "$asset")

  url=$(jq -r '.downloadUrl' <<< "$asset") || exit 1
  name=$(jq -r '.name' <<< "$asset") || exit 1
  echo "Downloading $name ($url)"
  curl -L "$url" -o "$name" || exit 1

  echo "Installing $pkg"
  tar xf "$name" || exit 1

  echo "Cleaning artifact $name"
  rm -f "$name" || exit 1
done
