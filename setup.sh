#!/bin/bash
set -e

ARCH=x86_64
TARGET="${ARCH}-unknown-redox"
RUST_TARGET="${TARGET}"

ROOT="${PWD}"

export XARGO_RUST_SRC="${ROOT}/rust/src"

if [ `uname` = "Darwin" ]; then
    NPROC=`sysctl -n hw.ncpu`
    NO_VERIFY="--no-verify"
    AUTOCONF="autoconf264"
    AUTOMAKE="automake112"
    ACLOCAL="aclocal112"
else
    NPROC=`nproc`
    AUTOCONF="autoconf2.64"
    AUTOMAKE="automake-1.11"
    ACLOCAL="aclocal-1.11"
fi

BUILD="${ROOT}/build"
mkdir -p "${BUILD}"
cd "${BUILD}"

PREFIX="${BUILD}/prefix"
mkdir -p "${PREFIX}"
mkdir -p "${PREFIX}/bin"
export PATH="${PREFIX}/bin:$PATH"

SYSROOT="${BUILD}/sysroot"
mkdir -p "${SYSROOT}"

CROSS="${BUILD}/cross"
mkdir -p "${CROSS}"
cd "${CROSS}"

###################BINUTILS#########################
function binutils {
    BINUTILS="${ROOT}/binutils-gdb"

    rm -rf "binutils"
    mkdir "binutils"
    pushd "binutils"
        "${BINUTILS}/configure" --target="${TARGET}" --prefix="${PREFIX}" --with-sysroot="${SYSROOT}" --disable-gdb --disable-nls --disable-werror
        make -j $NPROC
        make -j $NPROC install
    popd
}

##################GCC FREESTANDING##############################
function gcc_freestanding {
    GCC="${ROOT}/gcc"

    pushd "${GCC}"
        ./contrib/download_prerequisites $NO_VERIFY
    popd

    pushd "${GCC}/libstdc++-v3"
        $AUTOCONF
    popd

    rm -rf "gcc-freestanding"
    mkdir "gcc-freestanding"
    pushd "gcc-freestanding"
        "${GCC}/configure" --target="${TARGET}" --prefix="${PREFIX}" --disable-nls --enable-languages=c,c++ --without-headers
        make -j $NPROC all-gcc
        make -j $NPROC all-target-libgcc
        make -j $NPROC install-gcc
        make -j $NPROC install-target-libgcc
    popd
}

##################NEWLIB###########################
function newlib {
    NEWLIB="${ROOT}/newlib"

    echo "Defaulting to rust nightly"
    rustup override set nightly
    echo "Update rust nightly"
    rustup update nightly
    echo "Downloading rust source"
    rustup component add rust-src
    if [ -z "$(which xargo)" ]
    then
        echo "Installing xargo"
        cargo install -f xargo
    fi

    pushd "${NEWLIB}/newlib/libc/sys"
        $ACLOCAL -I ../..
        autoconf
        $AUTOMAKE --cygnus Makefile
    popd

    pushd "${NEWLIB}/newlib/libc/sys/redox"
        $ACLOCAL -I ../../..
        autoconf
        $AUTOMAKE --cygnus Makefile
    popd

    rm -rf "newlib"
    mkdir "newlib"
    pushd "newlib"
        "${NEWLIB}/configure" --target="${TARGET}" --prefix="${PREFIX}"
        make -j $NPROC all
        make -j $NPROC install
    popd

    mkdir -p "${SYSROOT}/usr"
    cp -r "${PREFIX}/${TARGET}/lib" "${SYSROOT}/usr"
    cp -r "${PREFIX}/${TARGET}/include" "${SYSROOT}/usr"
}

######################GCC############################
function gcc_complete {
    GCC="${ROOT}/gcc"

    rm -rf "gcc"
    mkdir "gcc"
    pushd "gcc"
        "${GCC}/configure" --target="${TARGET}" --prefix="${PREFIX}" --with-sysroot="${SYSROOT}" --disable-nls --enable-languages=c,c++
        make -j $NPROC all-gcc
        make -j $NPROC all-target-libgcc
        make -j $NPROC install-gcc
        make -j $NPROC install-target-libgcc
        make -j $NPROC all-target-libstdc++-v3
        make -j $NPROC install-target-libstdc++-v3
    popd
}

case $1 in
    binutils)
        binutils
        ;;
    gcc_freestanding)
        gcc_freestanding
        ;;
    newlib)
        newlib
        ;;
    gcc_complete)
        gcc_complete
        ;;
    all)
        binutils
        gcc_freestanding
        newlib
        gcc_complete
        ;;
    *)
        echo "$0 [binutils, gcc_freestanding, newlib, gcc_complete, rust, cargo, all]"
        ;;
esac
