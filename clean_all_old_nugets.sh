#!/bin/bash
set -o errexit
set -o errtrace
set -o functrace
set -o nounset
set -o pipefail
[ -n "${DEBUG:-}" ] && set -x # xtrace

# -------------------------------------------------------------------------------------------------

Here=${PWD}
ScriptPath=$( dirname "$0" )

function InfoMessage()
{
	echo "$@" >&2
}

function InfoMessageNoLF()
{
	InfoMessage -n "$@"
}

# -------------------------------------------------------------------------------------------------

cd "${USERPROFILE}"/.nuget/packages
for d in * ; do
	echo "$d"
	(
		cd "$d"
		l_folders_to_remove=$( ls -1 | /bin/sort -t . -gr | tail +2 )
		echo "${l_folders_to_remove}"
		rm -rv ${l_folders_to_remove}
	)
	break
done
