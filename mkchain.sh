#!/bin/bash

set -x
set -e
set -u

if [ "$#" -ne "1" ]; then
	echo "./mkchain <target>";
	exit 1;
fi;


if [ "$1" = "m68k-elf" ]; then
	TARGET="m68k-elf";
	TARGETOPTS="--with-arch=m68k"
	BINUTILSPOINT="21"
else
	TARGET="$1"
	TARGETOPTS=""
	BINUTILSPOINT="22"
fi

NEWLIBPOINT="20"
GCCVERSION="4.6.3"
GDBVERSION="7.4"

ROOTDIR=`pwd`
SRCDIR="${ROOTDIR}/src"
TARDIR="${ROOTDIR}/tarballs"
BUILDDIR="${ROOTDIR}/build"
INSTDIR="${ROOTDIR}/inst"

#BINUTILSURL="http://ftp.gnu.org/gnu/binutils/binutils-2.${BINUTILSPOINT}.tar.gz"
BINUTILSURL="ftp://aeneas.mit.edu/pub/gnu/binutils/binutils-2.${BINUTILSPOINT}.tar.gz"
GCCURL="http://ftp.gnu.org/gnu/gcc/gcc-${GCCVERSION}/gcc-core-${GCCVERSION}.tar.gz"
NEWLIBURL="ftp://sources.redhat.com/pub/newlib/newlib-1.${NEWLIBPOINT}.0.tar.gz"
GDBURL="http://ftp.gnu.org/gnu/gdb/gdb-${GDBVERSION}.tar.gz"

BINUTILSTAR="${TARDIR}/binutils-2.${BINUTILSPOINT}.tar.gz"
GCCTAR="${TARDIR}/gcc-core-${GCCVERSION}.tar.gz"
NEWLIBTAR="${TARDIR}/newlib-1.${NEWLIBPOINT}.0.tar.gz"
GDBTAR="${TARDIR}/gdb-${GDBVERSION}.tar.gz";

GCCTARHASH="6903be0610808454ef42985c214ad834"
NEWLIBTARHASH="e5488f545c46287d360e68a801d470e8"
GDBTARHASH="7877875c8af7c7ef7d06d329ac961d3f"

BINUTILSSRC="${SRCDIR}/binutils-2.${BINUTILSPOINT}"
GCCSRC="${SRCDIR}/gcc-${GCCVERSION}"
NEWLIBSRC="${SRCDIR}/newlib-1.${NEWLIBPOINT}.0";
GDBSRC="${SRCDIR}/gdb-${GDBVERSION}";


BINUTILSBUILD="${BUILDDIR}/${TARGET}-binutils"
GCCBUILD="${BUILDDIR}/${TARGET}-gcc"
NEWLIBBUILD="${BUILDDIR}/${TARGET}-newlib"
GDBBUILD="${BUILDDIR}/${TARGET}-gdb"

PREFIX="${INSTDIR}/${TARGET}";

NCPUS="2"
if [ -x /usr/bin/distcc ]; then
	DISTCCOUTPUT=`distcc -j 2> /dev/null`
	if [ "${DISTCCOUTPUT}" != "" ]; then
		NCPUS=$DISTCCOUTPUT;
	fi
fi

INSTBIN="${PREFIX}/bin"

mkdir -p ${INSTBIN}

PATH="${INSTBIN}:${PATH}"
OS=`uname -s`
ARCH=`uname -m`
TOOLCHAINTAR="${ROOTDIR}/toolchain-${TARGET}-${OS}_${ARCH}.tar.gz"

if [ -e $TOOLCHAINTAR ]; then
	TOOLCHAINSTAMP=`stat -c %Z ${TOOLCHAINTAR}`
	SCRIPTSTAMP=`stat -c %Z ${ROOTDIR}/mkchain.sh`

	if [ "$TOOLCHAINSTAMP" -gt "$SCRIPTSTAMP" ]; then
		echo "Toolchain tar is up to date";
		exit 0;
	fi 
fi;


function stageprep {

	TAR=$1;
	URL=$2;
	SRC=$3;
	BUILD=$4;
	HASH=$5;

	if [ -e ${TAR} -a "$HASH" != "" ]; then
		CURRENTHASH=`md5sum ${TAR} | cut -d " " -f 1`
		if [ "${CURRENTHASH}" != "${HASH}" ]; then
			echo "Hash of current tar.gz doesn't match what is expected, deleting";
			rm ${TAR};
		fi;
	fi

	if [ ! -e ${TAR} ]; then 
       		wget -O ${TAR} ${URL};
	fi

	if [ ! -d ${SRC} ]; then 
        	cd ${SRCDIR} && tar xzf ${TAR};
	fi 

	if [ -d ${BUILD} ]; then
        	rm -rf ${BUILD};
	fi

	mkdir ${BUILD}
}

if [ -d $PREFIX ]; then
	rm -r $PREFIX;
fi


REQUIREDPKGS="build-essential libgmp-dev libmpc-dev libmpfr-dev"


for PKG in $REQUIREDPKGS; do
	dpkg -s  $PKG 2>/dev/null | grep Status > /dev/null
	if [ "$?" -ne "0" ]; then
		echo "Build dep $PKG is missing, install it!";
		exit 1;
	fi
done


GCCCONFOPTS="--target=${TARGET} --enable-languages=c --with-gnu-as --with-gnu-ld --enable-languages=c --disable-libssp --prefix=${PREFIX} --disable-shared --with-newlib=yes ${TARGETOPTS}"

echo "*** BUILDING BINUTILS ***";
stageprep ${BINUTILSTAR} ${BINUTILSURL} ${BINUTILSSRC} ${BINUTILSBUILD} ""
cd ${BINUTILSBUILD}
${BINUTILSSRC}/configure --target="${TARGET}" --prefix="${PREFIX}"
make -j "${NCPUS}"
make install


echo "*** BUILDING INITIAL GCC***"
stageprep ${GCCTAR} ${GCCURL} ${GCCSRC} ${GCCBUILD} ${GCCTARHASH}
cd ${GCCBUILD}
# This might fail.. we shouldn't care.. it should give us enough of a compiler to compile newlib
${GCCSRC}/configure ${GCCCONFOPTS}
set +e;
make -k -j "${NCPUS}";
make -k install
set -e;

echo "*** BUILDING INITIAL NEWLIB ***";
stageprep $NEWLIBTAR $NEWLIBURL $NEWLIBSRC $NEWLIBBUILD ${NEWLIBTARHASH}
cd ${NEWLIBBUILD}
# This might fail.. we shouldn't care.. 
${NEWLIBSRC}/configure --target="${TARGET}" --prefix="${PREFIX}" --disable-newlib-supplied-syscalls
set +e;
make -k
make -k install
set -e;


echo "*** BUILDING FINAL GCC***"
stageprep ${GCCTAR} ${GCCURL} ${GCCSRC} ${GCCBUILD} ${GCCTARHASH}
cd ${GCCBUILD}
${GCCSRC}/configure ${GCCCONFOPTS}
make -j "${NCPUS}"
make install

echo "*** BUILDING FINAL NEWLIB ***"
stageprep $NEWLIBTAR $NEWLIBURL $NEWLIBSRC $NEWLIBBUILD ${NEWLIBTARHASH}
cd ${NEWLIBBUILD}
${NEWLIBSRC}/configure --target="${TARGET}" --prefix="${PREFIX}" --disable-newlib-supplied-syscalls
make
make install

echo "*** BUILDING GDB***"
stageprep $GDBTAR $GDBURL $GDBSRC $GDBBUILD ${GDBTARHASH}
cd ${GDBBUILD}
${GDBSRC}/configure --target="${TARGET}" --prefix="${PREFIX}"
make -j "${NCPUS}"
make install

cd $ROOTDIR
tar cpzvf $TOOLCHAINTAR inst/${TARGET}
echo "*** ALL DONE! ***";
