#!/bin/bash

RMEXE=
TREEISH=
OUT=
OUTFORMAT=".zip"

function syntax() {
	[ "$*" != "" ] && echo "$*" 1>&2
	echo "Syntax: $0 [--tar] [--no-exe] <tree-ish> [<outfile>]" 1>&2
	exit 1
}

# Parse arguments.
while [ "$#" -gt 0 ]; do
	if [ "$1" == '-h' -o "$1" == '-?' -o "$1" == '--help' ]; then
		syntax
	
	elif [ "$1" == '--tar' ]; then
		OUTFORMAT=".tar.gz"
		
	elif [ "$1" == '--no-exe' ]; then
		RMEXE=Y
		
	else
		if [ -z "$TREEISH" ]; then
			TREEISH="$1"
		elif [ -z "$OUT" ]; then
			OUT="$1"
		else
			syntax "Invalid argument: $1"
		fi
	fi
	
	shift
done

# Make sure the <tree-ish> has been set.
[ -z "$TREEISH" ] && syntax "The <tree-ish> argument is missing." 1>&2

# Make sure the <out-file> does not exist, if specified.
[ -n "$OUT" -a -e "$OUT" ] && echo "$OUT already exists" 1>&2 && exit 1

ORIGDIR="$(pwd)"
SCRIPTDIR="$(cd "$(dirname "$0")"; pwd)"
REPODIR="$(dirname "$SCRIPTDIR")"

cd "$REPODIR"

echo "Determining SHA1..."

# Get SHA1
SHA1="$(git rev-list --no-walk "$TREEISH" 2> /dev/null)"
[ "$SHA1" == "" ] && echo "Failed to determine SHA1" 1>&2 && exit 1

# Double check SHA1
if ! git rev-list --quiet "$SHA1" &> /dev/null; then
	echo "Failed to double check SHA1 ($SHA1)" 1>&2
	exit 1
fi

# Get short SHA1
SHORTSHA1="$(git rev-parse --short "$SHA1" 2> /dev/null)"
[ "$SHORTSHA1" == "" ] && echo "Failed to determine short SHA1" 1>&2 && exit 1

# Default to using the short SHA1
VERSIONTEXT="$SHORTSHA1"
OUTTEXT="$SHORTSHA1"

# Include TREEISH if it is a tag name.
if git tag -l --points-at "$SHA1" "$TREEISH" 2> /dev/null | grep -q "$TREEISH"; then
	VERSIONTEXT="$TREEISH ($VERSIONTEXT)"
	OUTTEXT="${TREEISH}_$OUTTEXT"
fi

echo "Normalized version text: $VERSIONTEXT"

if [ -z "$OUT" ]; then
	OUT="diskusagereports_$OUTTEXT$OUTFORMAT"
	echo "Defaulting output to: $OUT"
	
	# Make sure the <out-file> does not exist, if specified.
	[ -e "$ORIGDIR/$OUT" ] && echo "$OUT already exists." 1>&2 && exit 1
fi

# Normalize system temp dir.
[ -z "$TMPDIR" ] && TMPDIR="/tmp"
TMPDIR="$(cd "$TMPDIR"; pwd)"

TMPDIR="$(mktemp -d "$TMPDIR/diskusagereports_createarchive_$SHORTSHA1.XXXXXXXX")"
[ ! -d "$TMPDIR" ] && echo "Failed to create temp directory at: $TMPDIR" 1>&2 && exit 1

function exitClean() {
	rm -rf "$TMPDIR"
	[ "$?" != "0" ] && echo "Failed to remove temp dir: $TMPDIR" 1>&2
	exit $1
}

EXTRACTDIR="$TMPDIR/diskusagereports_$SHORTSHA1"
mkdir "$EXTRACTDIR"
[ "$?" != "0" ] && echo "Failed to create $EXTRACTDIR" 1>&2 && exitClean 1

echo "Creating raw archive..."

git archive --format=tar "$SHA1" > "$TMPDIR/raw.tar"
[ "$?" != "0" ] && exitClean 1

cat "$TMPDIR/raw.tar" | tar x -C "$EXTRACTDIR"
[ "$?" != "0" ] && exitClean 1

bash "$SCRIPTDIR/preparerelease.sh" "$EXTRACTDIR" "$VERSIONTEXT"
[ "$?" != "0" ] && exitClean 1

if [ "$RMEXE" == "Y" ]; then
	echo "Removing EXE files..."
	find "$EXTRACTDIR" -iname '*.exe' -print0 | xargs -0 rm
	[ "$?" != 0 ] && echo "Failed" 1>&2 && exitClean 1
fi

echo "Compressing..."
cd "$TMPDIR"

if [ "$OUTFORMAT" == ".tar.gz" ]; then
	tar czf "$TMPDIR/final.archive" "diskusagereports_$SHORTSHA1"
	[ "$?" != "0" ] && echo "FAILED" 1>&2 && exitClean 1
else
	zip -qr - "diskusagereports_$SHORTSHA1" > "$TMPDIR/final.archive"
	[ "$?" != "0" ] && echo "FAILED" 1>&2 && exitClean 1
fi

cd "$ORIGDIR"
mv "$TMPDIR/final.archive" "$OUT"
[ "$?" != "0" ] && echo "Failed to move temp archive file to $OUT" 1>&2 && exitClean 1

exit 0
