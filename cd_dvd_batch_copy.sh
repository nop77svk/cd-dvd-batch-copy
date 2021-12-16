#!/bin/bash
set -o errexit
set -o errtrace
set -o functrace
set -o nounset
set -o pipefail
[ -n "${DEBUG:-}" ] && set -x # xtrace

# -------------------------------------------------------------------------------------------------

TARGET_ROOT=/cygdrive/e/cd.majus
SOURCE_DRIVE_LETTER=W

function InfoMessage()
{
	echo "$@" >&2
}

function InfoMessageNoLF()
{
	InfoMessage -n "$@"
}

function ThrowException()
{
	(
		InfoMessage "$@"
		false
	)
}

function infrastructure_check()
{
	InfoMessage Checking for proper OS infrastructure
	( uname -a | grep -Eiq '^cygwin_nt.*\s+cygwin' ) || ThrowException " * Failed: CygWin on Windows NT" \
		|| ThrowException " * There are no more options :-("
}

function eject_cdrom()
{
	InfoMessage "Ejecting media"
	powershell "(new-object -COM Shell.Application).NameSpace(17).ParseName('${SOURCE_DRIVE_LETTER}:').InvokeVerb('Eject')"
}

function is_media_loaded()
{
	wmic cdrom list full | grep -E '^MediaLoaded=' | grep -qi '=true'
}

function get_media_volume_info()
{
	declare -n o_result=$1
	InfoMessage Retrieving CD/DVD media information
	eval $( wmic cdrom list full | tr -d '\r' | grep -E '^(VolumeName|VolumeSerialNumber)=' | sed "s/=\(.*\)$/='\1'/gi" )
	o_result="${VolumeSerialNumber}"
	if [ -n "${VolumeName}" ] ; then
		o_result="${o_result} ${VolumeName}"
	fi
}

# note: unused as of now
function compare_lists_of_files()
{
	InfoMessage "Comparing $1 against $2"
	l_number_of_differences=$(
		comm -3 \
			<( cd "$1" ; find . -mindepth 1 | sort ) \
			<( cd "$2" ; find . -mindepth 1 | sort ) \
			| wc -l
	)
	InfoMessage "Number of differences found: ${l_number_of_differences}"
	[ ${l_number_of_differences} -eq 0 ]
}

function copy_media()
{
	InfoMessage "Copying from $1 to $2"
	(
		cd "$1"
		rsync -rWP --size-only \
			. \
			"$2"
	)
}

function wait_for_media_inserted()
{
	InfoMessage "Insert media into the drive ${SOURCE_DRIVE_LETTER}: tray"

	InfoMessageNoLF "Waiting for media: "
	while ! is_media_loaded ; do
		sleep 1
		InfoMessageNoLF "."
	done
	InfoMessage " Loaded"
}

function calculate_checksum_for()
{
	InfoMessage "Calculating checksums for $1"
	(
		cd "$1"
		LC_ALL=en_US.cp1250
		find . -mindepth 1 -type f,l -exec md5sum -b {} \; | gzip -9c
	)
}

function check_checksum_in()
{
	InfoMessage "Checking checksums in $1/$2"
	(
		cd "$1"
		LC_ALL=en_US.cp1250
		(
			if [ "${2: -3}" = ".gz" ] ; then
				gzip -dc "$2"
			else if [ "${2: -4}" = ".bz2" ] ; then
				bzip2 -dc "$2"
			else
				cat "$2"
			fi ; fi
		) \
			| md5sum -c \
			|| ThrowException "Checksums mismatch!"
	)
}

function find_checksum_file()
{
	declare -n o_find_checksum_file=$1
	o_find_checksum_file=

	for fname in md5sum crc-md5sum checksum crc ; do
		for fext in gz bz2 ; do
			if [ -f .${fname}.${fext} ] ; then
				o_find_checksum_file=.${fname}.${fext}
				break;
			else if [ -f ${fname}.${fext} ] ; then
				o_find_checksum_file=${fname}.${fext}
				break;
			fi ; fi
		done

		if [ -n "${o_find_checksum_file:-}" ] ; then
			break;
		else if [ -f .${fname} ] ; then
			o_find_checksum_file=.${fname}
			break;
		else if [ -f ${fname} ] ; then
			o_find_checksum_file=${fname}
			break;
		fi ; fi ; fi
	done

	o_find_checksum_file=${o_find_checksum_file:-}
}

function find_checksum_file_in()
{
	declare -n o_find_checksum_file_in=$2
	o_find_checksum_file_in=
	
	(
		InfoMessage "Finding checksum file in $1"
		cd "$1"
		find_checksum_file o_find_checksum_file_in
	)

	o_find_checksum_file_in=${o_find_checksum_file_in:-}
}

# -------------------------------------------------------------------------------------------------

if ! infrastructure_check ; then
	ThrowException "ERROR: This shell script is intended to run on Windows NT w/ CygWin or something similar"
fi

mkdir ${TARGET_ROOT} || InfoMessage Target root ${TARGET_ROOT} already exists

while true ; do
	wait_for_media_inserted

	get_media_volume_info l_media_volume_info
	InfoMessage About to copy media ${l_media_volume_info}

	l_source_folder="/cygdrive/${SOURCE_DRIVE_LETTER}/"
	l_target_folder="${TARGET_ROOT}/${l_media_volume_info}"

	mkdir "${l_target_folder}" 2> /dev/null || InfoMessage Target directory already exists

	while true ; do
		while ! copy_media "${l_source_folder}" "${l_target_folder}" ; do
			InfoMessage "Retrying..."
		done

		find_checksum_file_in "${l_target_folder}" l_checksum_file
		if [ -z "${l_checksum_file:-}" ] ; then
			l_checksum_file=.md5sum.gz
			calculate_checksum_for "${l_source_folder}" > "${l_target_folder}/${l_checksum_file}"
		fi

		if check_checksum_in "${l_target_folder}" "${l_checksum_file}" ; then
			break
		else
			InfoMessage Retrying
		fi
	done

	eject_cdrom

	InfoMessage A short break prior to copying another media
	sleep 15
done
