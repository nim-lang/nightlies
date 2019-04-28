#! /bin/bash

export SRCFILE=nim-$VERSION.tar.xz
export BINFILE=nim-$VERSION-${OS}_$ARCH.tar

echo "Building Nim $VERSION for $ARCH on $OS"

set -e

# Extract and enter source
tar -xJf /io/$SRCFILE
cd nim-$VERSION

# Compile
case $ARCH in
  arm64) cpu="aarch64";;
  armv6 | armv7) cpu="arm" ;;
  *) cpu="$ARCH" ;;
esac

export LD=$CC

echo --gcc.exe:\"$CC\" > nim.cfg
echo --gcc.linkerexe:\"$CC\" >> nim.cfg
echo --clang.exe:\"$CC\" >> nim.cfg
echo --clang.linkerexe:\"$CC\" >> nim.cfg

cp -f build.sh build.sh~
cp -f compiler/nim.cfg compiler/nim.cfg~

if [[ "$OS" == "android" ]]; then
  cd /work
  wget https://raw.githubusercontent.com/termux/termux-packages/master/packages/libandroid-glob/glob.c
  wget https://raw.githubusercontent.com/termux/termux-packages/master/packages/libandroid-glob/glob.h
  $CC -c -I. glob.c
  cd -
  sed -i 's/ -lrt//' build.sh
  sed -i 's/ -ldl//' build.sh
  sed -i 's/ -landroid-glob//' build.sh
  mkdir -p /system/bin
  ln -sf /bin/sh /system/bin/sh
  echo --clang.options.linker:\"-static /work/glob.o\" >> nim.cfg
  export LDFLAGS="-static /work/glob.o"
fi

cat nim.cfg >> compiler/nim.cfg

./build.sh --cpu $cpu --os $OS
./bin/nim c koch
./koch boot -d:release

if [[ "$OS" == "android" ]]; then
  sed -i 's/-static/-ldl -pie/' nim.cfg
fi

./koch tools -d:release

# Cleanup
mv nim.cfg ~/.
mv compiler/nim.cfg ~/compiler.cfg
mv -f build.sh~ build.sh
mv -f compiler/nim.cfg~ compiler/nim.cfg
find -name *.o | xargs rm -f
find -name nimcache | xargs rm -rf
rm -f compiler/nim0
rm -f compiler/nim1
rm -f compiler/nim
rm -f /io/$BINFILE.xz

# Create XZ
cd ..
tar cf $BINFILE nim-$VERSION
xz -9fc $BINFILE > /io/$BINFILE.xz

# Test binaries
cd nim-$VERSION
mv ~/nim.cfg .
mv ~/compiler.cfg compiler/nim.cfg
./bin/nim c koch.nim
./koch docs
export NIM_EXE_NOT_IN_PATH=NOT_IN_PATH
./koch tests --nim:./bin/nim cat megatest
