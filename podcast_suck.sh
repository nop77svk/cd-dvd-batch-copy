#!/bin/bash
set -o errexit
set -o errtrace
set -o functrace
set -o nounset
set -o pipefail
[ -n "${DEBUG:-}" ] && set -x # xtrace

# -------------------------------------------------------------------------------------------------

# inputs:
i_podcast_name="Dejiny (SME)"
i_podcast_rss_uri="https://anchor.fm/s/40c6e0cc/podcast/rss"

# -------------------------------------------------------------------------------------------------

Here=$PWD
ScriptPath=$( dirname "$0" )
cd "${ScriptPath}"
ScriptPath=$PWD
cd "${Here}"

# -------------------------------------------------------------------------------------------------

mkdir "${Here}/${i_podcast_name}" 2> /dev/null || true
pushd "${Here}/${i_podcast_name}" > /dev/null
rm -f *.tmp || true
curl "${i_podcast_rss_uri}" > rss.xml.tmp

comm -3 \
	<( xmlstarlet sel -T -t -v "/rss/channel/item/guid" rss.xml.tmp | tr -d '\r' | sort -u ) \
	<( ( echo '<x>' ; cat *.rss_item.xml ; echo '</x>' ) | xmlstarlet sel -T -t -v '/x/item/guid' | tr -d '\r' | sort -u ) \
	| while read -r l_guid
do
	l_title=$( xmlstarlet sel -T -t -v "/rss/channel/item[guid='${l_guid}']/title" rss.xml.tmp | tr "\\?:/" '____' )
	echo "Now downloading: ${l_title}"
	echo "    GUID = ${l_guid}"

	xmlstarlet sel -t -c "/rss/channel/item[guid='${l_guid}']" rss.xml.tmp > rss_item.xml.tmp
	echo "    item XML temporarily stored"

	l_stream_uri=$( xmlstarlet sel -T -t -v "/item/enclosure/@url" rss_item.xml.tmp )
	echo "    enclosure URI = ${l_stream_uri}"

	echo "    ---"
	curl -L "${l_stream_uri}" | lame --preset standard -b 32 <( cat ) "${l_title}.mp3"
	echo "    ---"
	echo "    stream downloaded OK"

	mv rss_item.xml.tmp "${l_title}.rss_item.xml"
	echo "    item XML persisted"
done

rm rss.xml.tmp
popd > /dev/null
