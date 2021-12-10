#!/bin/bash
set -o errexit
set -o errtrace
set -o functrace
set -o nounset
set -o pipefail
[ -n "${DEBUG:-}" ] && set -x # xtrace

TARGET_ROOT=/cygdrive/e/cd.copy
SOURCE_DRIVE_LETTER=W

function InfoMessage()
{
	echo "$@" >&2
}

function InfoMessageNoLF()
{
	InfoMessage -n "$@"
}

function eject_cdrom()
{
	InfoMessage Insert media into the drive ${SOURCE_DRIVE_LETTER}: tray
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

function source_vs_target_are_the_same()
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
		rsync -ruWP --size-only \
			. \
			"$2"
	)
}

function wait_for_media_inserted()
{
	InfoMessageNoLF "Waiting for media: "
	while ! is_media_loaded ; do
		sleep 1
		InfoMessageNoLF "."
	done
	InfoMessage " Loaded"
}

# -------------------------------------------------------------------------------------------------

mkdir ${TARGET_ROOT} || InfoMessage Target root ${TARGET_ROOT} already exists

while true ; do
	wait_for_media_inserted

	get_media_volume_info l_media_volume_info
	InfoMessage About to copy media ${l_media_volume_info}

	l_source_folder="/cygdrive/${SOURCE_DRIVE_LETTER}/"
	l_target_folder="${TARGET_ROOT}/${l_media_volume_info}"

	mkdir "${l_source_folder}" 2> /dev/null || InfoMessage Target directory already exists

	while true ; do
		copy_media "${l_source_folder}" "${l_target_folder}"

		if source_vs_target_are_the_same "/cygdrive/${SOURCE_DRIVE_LETTER}" "${TARGET_ROOT}/${l_media_volume_info}" ; then
			break
		else
			InfoMessage Retrying
		fi
	done

	eject_cdrom

	InfoMessage A short break prior to copying another media
	sleep 15
done
