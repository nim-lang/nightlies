#! /bin/bash

export SRCFILE=nim-$VERSION.tar.xz
export BINFILE=nim-$VERSION-${OS}_$ARCH.tar

echo "Building Nim $VERSION for $ARCH on $OS"

set -e

# Setup PCRE
wget https://ftp.pcre.org/pub/pcre/pcre-8.43.tar.gz
tar xvzf pcre-8.43.tar.gz
cd pcre-8.43
./configure --host=`$CC -dumpmachine`
make
cd ..

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

cp config/nim.cfg config/nim.cfg~
cp -f build.sh build.sh~

if [[ $CC == *"gcc" ]]; then
  export COMPILER="gcc"
elif [[ $CC == *"clang" ]]; then
  export COMPILER="clang"
else
  echo "Unknown compiler $CC"
  exit
fi

echo -d:usePcreHeader >> config/nim.cfg
echo --$COMPILER.exe:\"$CC\" >> config/nim.cfg
echo --$COMPILER.linkerexe:\"$CC\" >> config/nim.cfg
echo --$COMPILER.options.always:\"-w -I/work/pcre-8.43\" >> config/nim.cfg

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
  export LDFLAGS="-static /work/glob.o"
else
  export LDFLAGS="-static"
fi
echo --$COMPILER.options.linker:\"/work/pcre-8.43/.libs/libpcre.a $LDFLAGS\" >> config/nim.cfg

./build.sh --cpu $cpu --os $OS
./bin/nim c koch
./koch boot -d:release

cp config/nim.cfg ~/.
if [[ "$OS" == "android" ]]; then
  sed -i 's/-static/-ldl -pie/' config/nim.cfg
else
  sed -i 's/-static/-ldl/' config/nim.cfg
fi

./koch tools -d:release

# Cleanup
mv -f config/nim.cfg~ config/nim.cfg
mv -f build.sh~ build.sh
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
mv -f ~/nim.cfg config/.
./bin/nim c koch.nim
#./koch docs
export NIM_EXE_NOT_IN_PATH=NOT_IN_PATH
./koch tests --nim:./bin/nim cat megatest || echo "Failed megatest"
