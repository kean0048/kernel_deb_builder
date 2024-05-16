#!/usr/bin/env bash

VERSION=$(grep 'Kernel Configuration' < config | awk '{print $3}')
MAX_TRIES=3     # try download times
idx=0

# add deb-src to sources.list
sed -i "/deb-src/s/# //g" /etc/apt/sources.list

# install dep
apt update
apt install -y wget xz-utils build-essential libelf-dev flex bison dpkg-dev bc rsync kmod cpio libssl-dev
apt build-dep -y linux

# change dir to workplace
cd "${GITHUB_WORKSPACE}" || exit

rm -rf artifact 2>/dev/null # clean old packages

# verify if kernel is there
if [ -f "linux-$VERSION.tar.xz" ] && [ -f "sha256sums.asc" ]; then
    echo "Kernel is exist, verify it..."
    sha256sum -c sha256sums.asc 2>/dev/null | grep OK
    if [ $? -eq 0 ]; then
        echo -e "SHA256 OK. --> [PASS]\n"
        echo "------------------------------------------------------------------"
    fi
else
	rm -f linux-$VERSION.tar.xz sha256sums.asc 2>/dev/null
	# download kernel source
	for ((idx=1; i<=$MAX_TRIES; i++)); do
	    wget http://www.kernel.org/pub/linux/kernel/v6.x/linux-"$VERSION".tar.xz
	    wget http://www.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc
	    
	    # verify
	    sha256sum -c sha256sums.asc 2>/dev/null | grep OK
	    if [ $? -eq 0 ]; then
			echo -e "SHA256 OK.--> [PASS]\n"
			echo "------------------------------------------------------------------"
			break
	    else
			echo "SHA256SUM check failed. -->[FAILED] try download agian ..."
			rm -f linux-$VERSION.tar.xz sha256sums.asc 2>/dev/null
	    fi
	done
fi

# download failed will exit
[ $idx -gt $MAX_TRIES ] && { echo "Download failure, exit."; exit 1; }

[ ! -d "linux-$VERSION" ] && tar -xf linux-"$VERSION".tar.xz

cd linux-"$VERSION" || exit

#Check incoming parameters
if [[ "$1" == "--clean" ]]; then
	#Delete configuration files and compiled files
	make mrproper
	#Delete compiled target and temporary files
	make clean
	echo "The kernel source code has been restored to its initial state and all settings and previous compilations have been cleaned up"
fi

# copy config file
cp ../config .config

# disable DEBUG_INFO to speedup build
scripts/config --disable DEBUG_INFO

# apply patches
cp ../patch.d/*.diff ./
# shellcheck source=src/util.sh
source ../patch.d/*.sh

# build deb packages
CPU_CORES=$(($(grep -c processor < /proc/cpuinfo)*2))
echo "Use $CPU_CORES CPUs to compile the kernel."
echo "------------------------------------------------------------------"

yes '' | make bindeb-pkg -j"$CPU_CORES" | tee ../build.log

# move deb packages to artifact dir
cd ..
rm -rfv *dbg*.deb
mkdir "artifact" 2>/dev/null
mv ./*.deb artifact/
