#!/bin/bash

# This script does the following:
# 1. Creates a new ES index (i.e., whosonfirst_v1, whosonfirst_v2)
# 2. Copies the records from the old index (if one exists already)
# 3. Sets an alias to the new index (i.e., whosonfirst => whosonfirst_v1)
# 4. Deletes the old index (if one exists)

WHOAMI=`python -c 'import os, sys; print os.path.realpath(sys.argv[1])' $0`

DIR=`dirname $WHOAMI`
PROJECT=`dirname $DIR`

if [ -z "$1" ] ; then
	echo "Usage: update-schema.sh [spelunker|boundaryissues|offline_tasks]"
	exit 1
fi

# The one argument controls two different settings:
#
#       spelunker
#           index: whosonfirst
#           schema: mappings.spelunker.json
#       boundaryissues
#           index: whosonfirst
#           schema: mappings.boundaryissues.json
#       offline_tasks
#           index: offline_tasks
#           schema: mappings.offline_tasks.json

MAPPINGS_SCHEMA="$PROJECT/schema/mappings.$1.json"
if [ ! -f $MAPPINGS_SCHEMA ] ; then
	echo "Not found: schema/mappings.$1.json"
	exit 1
fi

if [ "$1" = "spelunker" ] ; then
	INDEX_FILE="SPELUNKER_INDEX_VERSION"
	INDEX_BASE='whosonfirst'
elif [ "$1" = "boundaryissues" ] ; then
	INDEX_FILE="BOUNDARYISSUES_INDEX_VERSION"
	INDEX_BASE='whosonfirst'
elif [ "$1" = "offline_tasks" ] ; then
	INDEX_FILE="OFFLINE_TASKS_INDEX_VERSION"
	INDEX_BASE="offline_tasks"
fi

if [ ! -f "$PROJECT/$INDEX_FILE" ] ; then
	OLD_VERSION=0
	VERSION=1
	INDEX="${INDEX_BASE}_v1"
else
	OLD_VERSION=`cat $PROJECT/$INDEX_FILE`
	OLD_INDEX="${INDEX_BASE}_v$OLD_VERSION"
	VERSION=$(($OLD_VERSION + 1))
	INDEX="${INDEX_BASE}_v$VERSION"
fi

echo "Building index $INDEX"
cat $MAPPINGS_SCHEMA | curl -s -XPUT "http://localhost:9200/${INDEX}" -d @- | python -mjson.tool

if [ "$OLD_VERSION" -gt 0 ] ; then
	echo "Copying documents to $INDEX"
	stream2es es \
		--source http://localhost:9200/${INDEX_BASE} \
		--target http://localhost:9200/${INDEX} \
		--log debug
fi

if [ "$OLD_VERSION" -eq 0 ] ; then

	echo "Creating alias $INDEX_BASE => $INDEX"
	curl -s -XPOST localhost:9200/_aliases -d '
	{
		"actions": [
			{ "add": {
				"alias": "'${INDEX_BASE}'",
				"index": "'${INDEX}'"
			}}
		]
	}
	' | python -mjson.tool
else

	echo "Reassigning alias $INDEX_BASE => $INDEX"
	curl -s -XPOST localhost:9200/_aliases -d '
	{
		"actions": [
			{ "remove": {
				"alias": "'${INDEX_BASE}'",
				"index": "'${OLD_INDEX}'"
			}},
			{ "add": {
				"alias": "'${INDEX_BASE}'",
				"index": "'${INDEX}'"
			}}
		]
	}
	' | python -mjson.tool

	echo "Deleting index $OLD_INDEX"
	curl -s -XDELETE "http://localhost:9200/${OLD_INDEX}" | python -mjson.tool
fi

echo $VERSION > "$PROJECT/$INDEX_FILE"
