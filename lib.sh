#!/usr/bin/env bash

# Support library for tools

## realpath [path]
##
## Poor man's substitute for the real realpath
if ! command -v realpath >/dev/null 2>&1; then
  realpath() {
    python -c "import os; import sys; print(os.path.realpath(sys.argv[1]))" "$1"
  }
fi

## is-var <varname>
##
## Check if a variable is set
is-var() {
  test -n "${!1+z}"
}

## error [message]..
##
## Pretty print error messages
error() {
  echo $'\e[31merror\e[m:' "${BASH_SOURCE[1]}(${BASH_LINENO[1]}) ${FUNCNAME[1]}:" "$@" >&2
}

## os
##
## Print the OS name in lower case.
os() {
  if [[ $OS == Windows_NT ]]; then
    echo windows
  else
    uname | tr '[:upper:]' '[:lower:]'
  fi
}

## arch_from_triple <triple>
##
## Print architecture from a target triplet.
arch_from_triple() {
  local triple=$1
  local arch=${triple%%-*}

  case "$arch" in
    mingw32)
      arch=i386
      ;;
  esac

  echo "$arch"
}

## ncpu
##
## Print number of logical CPUs, 1 is printed if couldn't be found
ncpu() {
  local ncpu=
  case "$(os)" in
    windows)
      ncpu=$NUMBER_OF_PROCESSORS
      ;;
    darwin)
      ncpu=$(sysctl -n hw.ncpu)
      ;;
    linux)
      ncpu=$(nproc)
      ;;
  esac
  if [[ $ncpu -le 0 ]]; then
    ncpu=1
  fi

  echo "$ncpu"
}

## nativepath <path>
##
## Translate the given unix path to a native path.
nativepath() {
  if [[ $# -eq 0 ]]; then
    error "a path must be given"
    return 1
  fi
  if [[ -z "$1" ]]; then
    error "path must not be empty"
    return 1
  fi
  case "$(os)" in
    windows)
      sed -e 's|^/\(.\)|\1:|' -e 's|/|\\\\|g' <<< "$1"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

## pushenv [-n] (<variable name> [<value>])..
##
## Push the specified environment variable to be used with the next step in a
## job pipeline.
##
## If -n is passed, the value will be left as-is and won't be quoted.
pushenv() {
  if [[ $# -eq 0 ]]; then
    error "a variable name must be passed"
    return 1
  fi

  local quote=true
  OPTIND=1
  while getopts 'n' curopt; do
    case "$curopt" in
      'n')
        quote=false
        ;;
      *)
        return 1
        ;;
    esac
  done

  shift $((OPTIND - 1))

  local printNotice=true
  local envfile=$PWD/environment
  local formatStr='export %s=%s\n'
  if $quote; then
    formatStr='export %s=%q\n'
  fi
  while [[ $# -gt 0 ]]; do
    local name=$1
    local value=$2

    if [[ $value == *$'\n'* ]]; then
      error "variable value must not contain newline"
      return 1
    fi

    # The format string changes depending on the options passed.
    # shellcheck disable=SC2059
    if ! printf "$formatStr" "$name" "$value" >> "$envfile"; then
      echo "Could not write environmental settings to $envfile"
      return 1
    fi
    if $printNotice; then
      echo "Environmental settings are appended to $envfile"
      printNotice=false
    fi

    shift 2 || shift $#
  done
}

## pushpath <path>..
##
## prepend the given values to PATH for the next step in a job pipeline.
pushpath() {
  if [[ $# -eq 0 ]]; then
    error "a path must be passed"
    return 1
  fi

  declare -a _pushpath_path
  local snippet=false
  while [[ $# -gt 0 ]]; do
    if [[ -z "$1" ]]; then
      error "path must not be empty"
      return 1
    fi
    local path
    path=$(realpath "$1")
    if [[ $1 == *$'\n'* || $1 == *':'* ]]; then
      error "path must not contain newline or ':' (colon)"
      return 1
    fi
    snippet=true
    _pushpath_path=( "$path" "${_pushpath_path[@]}" )

    shift 1
  done

  if $snippet; then
    # This is intentional, we want the PATH to be expanded at source time.
    # shellcheck disable=SC2016
    pushenv -n PATH "$(IFS=': '; printf '%q${PATH:+:$PATH}' "${_pushpath_path[*]}")"
  fi
}

## fold [desc]..
##
## Start output fold with description `desc`
fold() {
  if is-var GITHUB_ACTIONS; then
    echo "::group::$*"
  fi
}

## endfold
##
## End the last output fold
endfold() {
  if is-var GITHUB_ACTIONS; then
    echo "::endgroup::"
  fi
}

## tolowercase <string>
##
## Convert string to lower case because CI bash
## might not support the built-in case changing
## parameter expansion
tolowercase() {
  echo "$(tr [A-Z] [a-z] <<< "${1?}")"
}
