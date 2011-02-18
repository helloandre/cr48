#!/bin/sh
#
# Copyright (c) 2005-2006 Pavel Roskin
#

OPTIONS_KEEPDASHDASH=
OPTIONS_SPEC="\
git-clean [options] <paths>...

Clean untracked files from the working directory

When optional <paths>... arguments are given, the paths
affected are further limited to those that match them.
--
d remove directories as well
f override clean.requireForce and clean anyway
n don't remove anything, just show what would be done
q be quiet, only report errors
x remove ignored files as well
X remove only ignored files"

SUBDIRECTORY_OK=Yes
. git-sh-setup
require_work_tree

ignored=
ignoredonly=
cleandir=
rmf="rm -f --"
rmrf="rm -rf --"
rm_refuse="echo Not removing"
echo1="echo"

disabled=$(git config --bool clean.requireForce)

while test $# != 0
do
	case "$1" in
	-d)
		cleandir=1
		;;
	-f)
		disabled=false
		;;
	-n)
		disabled=false
		rmf="echo Would remove"
		rmrf="echo Would remove"
		rm_refuse="echo Would not remove"
		echo1=":"
		;;
	-q)
		echo1=":"
		;;
	-x)
		ignored=1
		;;
	-X)
		ignoredonly=1
		;;
	--)
		shift
		break
		;;
	*)
		usage # should not happen
		;;
	esac
	shift
done

# requireForce used to default to false but now it defaults to true.
# IOW, lack of explicit "clean.requireForce = false" is taken as
# "clean.requireForce = true".
case "$disabled" in
"")
	die "clean.requireForce not set and -n or -f not given; refusing to clean"
	;;
"true")
	die "clean.requireForce set and -n or -f not given; refusing to clean"
	;;
esac

if [ "$ignored,$ignoredonly" = "1,1" ]; then
	die "-x and -X cannot be set together"
fi

if [ -z "$ignored" ]; then
	excl="--exclude-per-directory=.gitignore"
	excl_info= excludes_file=
	if [ -f "$GIT_DIR/info/exclude" ]; then
		excl_info="--exclude-from=$GIT_DIR/info/exclude"
	fi
	if cfg_excl=$(git config core.excludesfile) && test -f "$cfg_excl"
	then
		excludes_file="--exclude-from=$cfg_excl"
	fi
	if [ "$ignoredonly" ]; then
		excl="$excl --ignored"
	fi
fi

git ls-files --others --directory \
	$excl ${excl_info:+"$excl_info"} ${excludes_file:+"$excludes_file"} \
	-- "$@" |
while read -r file; do
	if [ -d "$file" -a ! -L "$file" ]; then
		if [ -z "$cleandir" ]; then
			$rm_refuse "$file"
			continue
		fi
		$echo1 "Removing $file"
		$rmrf "$file"
	else
		$echo1 "Removing $file"
		$rmf "$file"
	fi
done
