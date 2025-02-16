#!/bin/bash

set -e

fdt=0
kernel=0
ramdisk=0
resource=0

# usage:
#	mk-fitimage.sh its_file ramdisk_file kernel_image dtb_file resource_image target_file target_arch optional_param
#
its_file="$1"
ramdisk_file="$2"
kernel_image="$3"
dtb_file="$4"
echo $dtb_file
resource_image="$5"
target_file="$6"
target_arch="$7"
optional_param="$8"

################################################################################
# Plubic Configure
################################################################################
C_BLACK="\e[30;1m"
C_RED="\e[31;1m"
C_GREEN="\e[32;1m"
C_YELLOW="\e[33;1m"
C_BLUE="\e[34;1m"
C_PURPLE="\e[35;1m"
C_CYAN="\e[36;1m"
C_WHITE="\e[37;1m"
C_NORMAL="\033[0m"

function msg_info()
{
	echo -e "${C_GREEN}[$(basename $0):info] $1${C_NORMAL}"
}

function msg_warn()
{
	echo -e "${C_YELLOW}[$(basename $0):warn] $1${C_NORMAL}"
}

function msg_error()
{
	echo -e "${C_RED}[$(basename $0):error] $1${C_NORMAL}"
}

function get_dtb_param() {
	local dump_kernel_dtb_file
	local kernel_file_dtb_dts
	local tmp_ramdisk

	if [ ! -f "${1}" ]; then
		echo "Not found ${1} ignore"
		return
	fi
	kernel_file_dtb_dts="${1}"
	dump_kernel_dtb_file=${kernel_file_dtb_dts}.dump.dts

	dtc -I dtb -O dts -o ${dump_kernel_dtb_file} ${kernel_file_dtb_dts} 2>/dev/null

	ramdisk_c=`grep -A 3 -e ramdisk_c $dump_kernel_dtb_file | grep -w "reg"|awk -F\< '{print $2}'|awk '{print $1}'`
	ramdisk_c_size=`grep -A 3 -e ramdisk_c  $dump_kernel_dtb_file |grep reg|awk -F\< '{print $2}'|awk '{print $2}' | awk -F\> '{print $1}'`

	ramdisk_r_size=`grep -A 3 ramdisk_r $dump_kernel_dtb_file |grep reg|awk -F\< '{print $2}'|awk '{print $2}' | awk -F\> '{print $1}'`
	ramdisk_r=`grep -A 3 ramdisk_r $dump_kernel_dtb_file |grep reg|awk -F\< '{print $2}'|awk '{print $1}'`

	if [ $(( ramdisk_r + ramdisk_r_size )) -ne $(( ramdisk_c )) ];then
		echo "$0:error ramdisk_r + ramdisk_r_size != ramdisk_c"
		echo "$0:error please check kernel's dts ramdisk_r/ramdisk_c"
		echo "$0:info ramdisk_r = $ramdisk_r"
		echo "$0:info ramdisk_r's size = $ramdisk_r_size"
		echo "$0:info ramdisk_c = $ramdisk_c"
		exit 1
	fi

	filesize_of_ramdisk_c_size=$(du -b $ramdisk_file | awk '{print $1}')
	if [ $(( filesize_of_ramdisk_c_size )) -gt $(( ramdisk_c_size )) ];then
		echo "$0:error filesize of $ramdisk_file go beyond the limit $ramdisk_c_size"
		echo "$0:error please check kernel's dts ramdisk_r/ramdisk_c"
		exit 1
	fi

	filesize_of_ramdisk_r_size=$(du -b ${ramdisk_file%*\.gz} | awk '{print $1}')
	if [ $(( filesize_of_ramdisk_r_size )) -gt $(( ramdisk_r_size )) ];then
		echo "$0:error filesize of ${ramdisk_file%*\.gz} go beyond the limit $ramdisk_r_size"
		echo "$0:error please check kernel's dts ramdisk_r/ramdisk_c"
		exit 1
	fi
}

[ -f $its_file -o -f $ramdisk_file -o -f $kernel_image -o -f $dtb_file -o -z $target_file ] || exit 1

ramdisk_r="NONE"
ramdisk_c="NONE"
ramdisk_c_size="NONE"
ramdisk_r_size="NONE"
kernel_c="NONE"
if grep "load.*ramdisk_r\|comp.*ramdisk_c\|comp.*kernel_c" $its_file; then
	get_dtb_param $dtb_file
	kernel_c="$(( ramdisk_c + ramdisk_c_size ))"
fi
echo "$0:info ramdisk_r = $ramdisk_r"
echo "$0:info ramdisk_r_size = $ramdisk_r_size"
echo "$0:info ramdisk_c = $ramdisk_c"
echo "$0:info ramdisk_c_size = $ramdisk_c_size"
echo "$0:info kernel_c = $kernel_c"

target_its_file="`dirname $target_file`/.tmp_its"
rm -f $target_its_file
mkdir -p "`dirname $target_its_file`"

while read line
do
	############################# generate fdt path
	if [ $fdt -eq 1 ];then
		echo "data = /incbin/(\"$dtb_file\");" >> $target_its_file
		fdt=0
		continue
	fi
	if echo $line | grep -w "^fdt" |grep -v ";"; then
		fdt=1
		echo "$line" >> $target_its_file
		continue
	fi

	############################# generate kernel image path
	if [ ! "$kernel_c" == "NONE" ];then
		if echo "$line" | grep "comp.*kernel_c";then
			echo "comp = <$kernel_c>;" >> $target_its_file
			continue
		fi
	fi
	if [ $kernel -eq 1 ];then
		echo "data = /incbin/(\"$kernel_image\");" >> $target_its_file
		kernel=0
		continue
	fi
	if echo $line | grep -w "^kernel" |grep -v ";"; then
		kernel=1
		echo "$line" >> $target_its_file
		continue
	fi

	############################# generate ramdisk path
	if [ -f $ramdisk_file ]; then
		if [ ! "$ramdisk_c" == "NONE" ];then
			if echo "$line" | grep "comp.*ramdisk_c";then
				echo "comp = <$ramdisk_c>;" >> $target_its_file
				continue
			fi
		fi
		if [ ! "$ramdisk_r" == "NONE" ];then
			if echo "$line" | grep "load.*ramdisk_r";then
				echo "load = <$ramdisk_r>;" >> $target_its_file
				continue
			fi
		fi
		if [ $ramdisk -eq 1 ];then
			echo "data = /incbin/(\"$ramdisk_file\");" >> $target_its_file
			ramdisk=0
			continue
		fi
		if echo $line | grep -w "^ramdisk" |grep -v ";"; then
			ramdisk=1
			echo "$line" >> $target_its_file
			continue
		fi

		if echo $line | grep -w "^preload" ; then
			if echo $optional_param | grep -w "preload_none" ; then
				msg_info "found preload_none flag, skip config preload for ramdisk."
				continue
			fi
		fi
	fi

	############################# generate resource path
	if [ $resource -eq 1 ];then
		echo "data = /incbin/(\"$resource_image\");" >> $target_its_file
		resource=0
		continue
	fi
	if echo $line | grep -w "^resource" |grep -v ";"; then
		resource=1
		echo "$line" >> $target_its_file
		continue
	fi

	if [ "$RK_RAMDISK_SECURITY_BOOTUP" = "true" ];then
		if echo $line | grep -wq "uboot-ignore"; then
			echo "Enable Security boot, Skip uboot-ignore ..."
			continue
		fi
	fi

	echo "$line" >> $target_its_file
done < $its_file

if [ "$target_arch" = "arm64" ]; then
    sed -i 's/arch.*=.*\"arm\"\;/arch = \"arm64\"\;/g'
fi

mkimage -f $target_its_file  -E -p 0x800 $target_file
rm -f $target_its_file
