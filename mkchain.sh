#!/bin/bash

set -x
set -e
set -u

# check args
if [ "$#" -ne "1" ]; then
	echo "./mkchain <target>";
	exit 1;
fi;

# setup the versions of the tools we want
if [ "$1" = "m68k-elf" ]; then
	TARGETOPTS="--with-arch=m68k"
else
	TARGETOPTS=""
fi

TARGET="$1"
BINUTILSVERSION="2.23.51.0.3"
NEWLIBVERSION="2.0.0"
GCCVERSION="4.8.0"
GDBVERSION="7.5.1"
#

ROOTDIR=`pwd`
SRCDIR="${ROOTDIR}/src"
TARDIR="${ROOTDIR}/tarballs"
BUILDDIR="${ROOTDIR}/build"
INSTDIR="${ROOTDIR}/inst"

# download urls
BINUTILSURL="http://www.kernel.org/pub/linux/devel/binutils/binutils-${BINUTILSVERSION}.tar.gz"
GCCURL="http://ftp.gnu.org/gnu/gcc/gcc-${GCCVERSION}/gcc-${GCCVERSION}.tar.gz"
NEWLIBURL="ftp://sources.redhat.com/pub/newlib/newlib-${NEWLIBVERSION}.tar.gz"
GDBURL="http://ftp.gnu.org/gnu/gdb/gdb-${GDBVERSION}.tar.gz"

BINUTILSTAR="${TARDIR}/binutils-${BINUTILSVERSION}.tar.gz"
GCCTAR="${TARDIR}/gcc-${GCCVERSION}.tar.gz"
NEWLIBTAR="${TARDIR}/newlib-${NEWLIBVERSION}.tar.gz"
GDBTAR="${TARDIR}/gdb-${GDBVERSION}.tar.gz";

# hashes for stuff
BINUTILSHASH="582b8b5b1ddde8f336b622877b751c64"
GCCTARHASH="f1011d59961a43d3d7c22913815812b3"
NEWLIBTARHASH="e3e936235e56d6a28afb2a7f98b1a635"
GDBTARHASH="b1519bf899890d21d4774845a6e602fe"

# src directories
BINUTILSSRC="${SRCDIR}/binutils-${BINUTILSVERSION}"
GCCSRC="${SRCDIR}/gcc-${GCCVERSION}"
NEWLIBSRC="${SRCDIR}/newlib-${NEWLIBVERSION}";
GDBSRC="${SRCDIR}/gdb-${GDBVERSION}";

# build directories
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

	if [ -e ${TAR} ]; then
		CURRENTHASH=`md5sum ${TAR} | cut -d " " -f 1`
		if [ "${CURRENTHASH}" != "${HASH}" ]; then
			echo "Hash of current tar.gz doesn't match what is expected, deleting";
			rm ${TAR};
		fi;
	fi

	# if the tar doesn't exist download it
	if [ ! -e ${TAR} ]; then 
       		wget -O ${TAR} ${URL};
		DOWNLOADEDHASH=`md5sum ${TAR} | cut -d " " -f 1`
                if [ "${DOWNLOADEDHASH}" != "${HASH}" ]; then
                        echo "Hash of downloaded tar.gz doesn't match what is expected, exiting";
                        exit 1;
                fi;
		# get rid of any extracted version
		if [ -d ${SRC} ]; then 
        		rm -rf ${SRC}
		fi
	fi
	
	# if the src dir doesn't exist anymore extract the source.
	if [ ! -d ${SRC} ]; then
		cd ${SRCDIR} && tar xzf ${TAR};
	fi;

	if [ -d ${BUILD} ]; then
        	rm -rf ${BUILD};
	fi

	mkdir ${BUILD}
}

if [ -d $PREFIX ]; then
	rm -r $PREFIX;
fi


# debian package detection
REQUIREDPKGS="build-essential libgmp-dev libmpc-dev libmpfr-dev flex bison libncurses5-dev"

for PKG in $REQUIREDPKGS; do
	dpkg -s  $PKG 2>/dev/null | grep Status > /dev/null
	if [ "$?" -ne "0" ]; then
		echo "Build dep $PKG is missing, install it!";
		exit 1;
	fi
done
#

GCCCONFOPTS="--target=${TARGET} --enable-languages=c --with-gnu-as --with-gnu-ld --enable-languages=c --disable-libssp --prefix=${PREFIX} --disable-shared --with-newlib=yes ${TARGETOPTS}"
NEWLIBOPTS="--target=${TARGET} --prefix=${PREFIX} --disable-newlib-supplied-syscalls --enable-newlib-reent-small"
BINUTILSOPTS="--target=${TARGET} --prefix=${PREFIX} --enable-gold"

CFLAGSFORTARGET="-flto"

echo "*** BUILDING BINUTILS ***";
stageprep ${BINUTILSTAR} ${BINUTILSURL} ${BINUTILSSRC} ${BINUTILSBUILD} ${BINUTILSHASH}
cd ${BINUTILSBUILD}
${BINUTILSSRC}/configure $BINUTILSOPTS
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
${NEWLIBSRC}/configure ${NEWLIBOPTS}
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
${NEWLIBSRC}/configure ${NEWLIBOPTS} CFLAGS_FOR_TARGET="${CFLAGSFORTARGET}"
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
