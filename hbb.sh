#! /bin/bash

export SRCFILE=nim-$VERSION.tar.xz
export BINFILE=nim-$VERSION-linux_x$ARCH.tar

echo "Building Nim $VERSION for $ARCH"

set -e

# Activate Holy Build Box environment.
source /hbb_exe/activate

set -x

# Install xz
yum -y install wget xz || yum clean all

# PCRE
export OLDLDFLAGS=$LDFLAGS
unset LDFLAGS
wget https://ftp.pcre.org/pub/pcre/pcre-8.43.tar.gz
tar xvzf pcre-8.43.tar.gz
cd pcre-8.43
./configure --prefix=/hbb --disable-static
make && make install
cd ..
export LDFLAGS=$OLDLDFLAGS

# Extract and enter source
tar -xJf /io/$SRCFILE
cd nim-$VERSION

# Compile
case $ARCH in
  32) cpu="i386" ;;
  64) cpu="amd64" ;;
esac

./build.sh --cpu $cpu
./bin/nim c koch
./koch boot -d:release
./koch tools -d:release

# Cleanup
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
./bin/nim c koch.nim
./koch docs
export NIM_EXE_NOT_IN_PATH=NOT_IN_PATH
./koch tests --nim:./bin/nim cat megatest
