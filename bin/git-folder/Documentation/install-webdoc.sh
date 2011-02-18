#!/bin/sh

T="$1"

for h in \
	*.txt *.html \
	howto/*.txt howto/*.html \
	technical/*.txt technical/*.html \
	RelNotes/*.txt *.css
do
	if test ! -f "$h"
	then
		: did not match
	elif test -f "$T/$h" &&
		$DIFF -u -I'^Last updated ' "$T/$h" "$h"
	then
		:; # up to date
	else
		echo >&2 "# install $h $T/$h"
		rm -f "$T/$h"
		mkdir -p `dirname "$T/$h"`
		cp "$h" "$T/$h"
	fi
done
strip_leading=`echo "$T/" | sed -e 's|.|.|g'`
for th in \
	"$T"/*.html "$T"/*.txt \
	"$T"/howto/*.txt "$T"/howto/*.html \
	"$T"/technical/*.txt "$T"/technical/*.html
do
	h=`expr "$th" : "$strip_leading"'\(.*\)'`
	case "$h" in
	RelNotes-*.txt | index.html) continue ;;
	esac
	test -f "$h" && continue
	echo >&2 "# rm -f $th"
	rm -f "$th"
done
ln -sf git.html "$T/index.html"
