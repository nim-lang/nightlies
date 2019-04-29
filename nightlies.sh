# Packages on OSX
if [[ "$TRAVIS_OS_NAME" == "osx" ]]
then
  brew update
  brew install boehmgc
  brew install sfml
  brew install gnu-tar
  brew upgrade node
fi

set -e

if [[ "$TRAVIS_OS_NAME" == "osx" ]]
then
  unset -f cd
  shell_session_update() { :; }
fi

# MinGW on Windows
if [[ "$TRAVIS_OS_NAME" == "windows" ]]
then
  if [[ ! -d "${TRAVIS_BUILD_DIR}/mingw/mingw${ARCH}" ]]
  then
    wget -nv "https://nim-lang.org/download/mingw${ARCH}-6.3.0.7z"
    7z x -y "mingw${ARCH}-6.3.0.7z" -o"${TRAVIS_BUILD_DIR}/mingw" > nul
  fi
  export PATH="${TRAVIS_BUILD_DIR}/mingw/mingw${ARCH}/bin:${PATH}"
fi

# Env vars
export BUILD_DATE=$(date +'%Y-%m-%d')
export NIMREPO="https://github.com/nim-lang/Nim"
export NIMVER="$(git ls-remote ${NIMREPO} ${NIMBRANCH} | cut -f 1)"
export NIMDIR="${TRAVIS_BUILD_DIR}/nim/${NIMVER}"
echo "NIMDIR = ${NIMDIR}"

if [[ -z "${OS+x}" ]]
then
  export OS="${TRAVIS_OS_NAME}"
fi
echo "OS = ${OS}"

# Path to nim binary
if [[ "$TRAVIS_OS_NAME" == "windows" ]]
then
  export NIMEXE="${NIMDIR}/bin/nim.exe"
else
  export NIMEXE="${NIMDIR}/bin/nim"
fi

# If not already built
if [[ ! -f ${NIMEXE} ]]
then
  export DO_DEPLOY=yes && echo "DO_DEPLOY = ${DO_DEPLOY}"
  ls -l ${TRAVIS_BUILD_DIR}/nim || echo "No nim directory"
  rm -rf nim
  mkdir -p nim
  git clone --single-branch --branch "${NIMBRANCH}" --depth=1 "${NIMREPO}" "${NIMDIR}"
  cd "${NIMDIR}" || exit

  echo "travis_fold:start:csources"
  [ -d csources ] || git clone --depth 1 https://github.com/nim-lang/csources.git
  cd csources || exit
  if [[ "$TRAVIS_OS_NAME" == "windows" ]]
  then
    cmd "/C build.bat"
    wget -nv https://nim-lang.org/download/windeps.zip
    7z x -y "windeps.zip" -o"../bin" > nul
    rm -rf windeps.zip
  else
    sh build.sh
  fi
  cd ..
  echo "travis_fold:end:csources"

  echo "travis_fold:start:build_koch"
  ./bin/nim c koch
  echo "travis_fold:end:build_koch"

  echo "travis_fold:start:koch_boot"
  ./koch boot -d:release
  echo "travis_fold:end:koch_boot"

  export OLDPATH="${PATH}"
  export PATH="${NIMDIR}/bin:${PATH}"
  export DEPLOY_VERSION="$(nim --version | head -n 1 | perl -pe 's/.*Version ([0-9.]+).*/\1/')"
  if [[ "$TRAVIS_OS_NAME" == "windows" ]]
  then
    export ZIPSUFFIX="_x${ARCH}.zip"
  elif [[ "$TRAVIS_OS_NAME" == "linux" ]]
  then
    if [[ $ARCH == "arm"* ]]
    then
      export ZIPSUFFIX="_${ARCH}.tar.xz"
    else
      export ZIPSUFFIX="_x${ARCH}.tar.xz"
    fi
  else
    export ZIPSUFFIX=".tar.xz"
  fi

  export ASSETFILE="nim-${DEPLOY_VERSION}-${OS}${ZIPSUFFIX}"

  if [[ "$TRAVIS_OS_NAME" == "windows" ]]
  then
    echo "travis_fold:start:winrelease"
    ./bin/nim c tools/winrelease
    mkdir -p web/upload/download
    cp tools/winrelease.exe .
    ./winrelease
    echo "travis_fold:end:winrelease"
  else
    echo "travis_fold:start:koch_tools"
    ./koch tools
    echo "travis_fold:end:koch_tools"

    # Skip koch docs for arm builds
    if [[ $ARCH != "arm"* ]]
    then
      echo "travis_fold:start:koch_doc"
      ./koch doc
      echo "travis_fold:end:koch_doc"
    fi

    if [[ "$TRAVIS_OS_NAME" == "linux" ]]
    then
      # Don't use testinstall for Linux
      echo "travis_fold:start:koch_csource"
      ./koch csource -d:release
      echo "travis_fold:end:koch_csource"

      echo "travis_fold:start:koch_xz"
      ./koch xz -d:release
      echo "travis_fold:end:koch_xz"

      if [[ $ARCH == "arm"* ]]
      then
        # Register binfmt_misc to run arm binaries
        docker run --rm --privileged multiarch/qemu-user-static:register

        # Use DockCross to build and test ARM binaries
        cp $TRAVIS_BUILD_DIR/dx.sh build/.
        docker run -t -i -e VERSION=$DEPLOY_VERSION -e ARCH=$ARCH -e OS=$OS --rm -v `pwd`/build:/io dockcross/$OS-$ARCH bash /io/dx.sh
      else
        # Use HBB to build and test generic Linux binaries
        cp $TRAVIS_BUILD_DIR/hbb.sh build/.
        docker run -t -i -e VERSION=$DEPLOY_VERSION -e ARCH=$ARCH --rm -v `pwd`/build:/io phusion/holy-build-box-$ARCH:latest bash /io/hbb.sh
      fi
    else
      # testinstall does csource and xz today
      echo "travis_fold:start:koch_testinstall"
      ./koch testinstall
      echo "travis_fold:start:koch_testinstall"
    fi
  fi
  # After building nim, wipe csources to save on cache space.
  rm -rf csources
fi

# Ensure that NIMVERSHORT and PATH env vars are set whether or not
# cached nim build is used.
cd "${NIMDIR}" && export NIMVERSHORT="$(git log --format=%h -1)"
export PATH="${NIMDIR}/bin:${PATH}"
cd "${TRAVIS_BUILD_DIR}"
if [[ ! -z "${DO_DEPLOY+x}" ]]
then
  echo "[cache check] New Nim commit found"

  if [[ "$TRAVIS_OS_NAME" == "windows" ]]
  then
    cp -f "${NIMDIR}/web/upload/download/nim-${DEPLOY_VERSION}${ZIPSUFFIX}" "${ASSETFILE}"
  elif [[ "$TRAVIS_OS_NAME" == "linux" ]]
  then
    cp -f "${NIMDIR}/build/$ASSETFILE" "${ASSETFILE}"
  else
    cp -f "${NIMDIR}/build/nim-${DEPLOY_VERSION}${ZIPSUFFIX}" "${ASSETFILE}"
  fi
else
  echo "[cache check] No new Nim commit"
fi

nim --version
