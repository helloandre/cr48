#!/bin/sh
#
# Copyright (c) 2005, Linus Torvalds
# Copyright (c) 2005, Junio C Hamano
#
# Clone a repository into a different directory that does not yet exist.

# See git-sh-setup why.
unset CDPATH

OPTIONS_SPEC="\
git-clone [options] [--] <repo> [<dir>]
--
n,no-checkout        don't create a checkout
bare                 create a bare repository
naked                create a bare repository
l,local              to clone from a local repository
no-hardlinks         don't use local hardlinks, always copy
s,shared             setup as a shared repository
template=            path to the template directory
q,quiet              be quiet
reference=           reference repository
o,origin=            use <name> instead of 'origin' to track upstream
u,upload-pack=       path to git-upload-pack on the remote
depth=               create a shallow clone of that depth

use-separate-remote  compatibility, do not use
no-separate-remote   compatibility, do not use"

die() {
	echo >&2 "$@"
	exit 1
}

usage() {
	exec "$0" -h
}

eval "$(echo "$OPTIONS_SPEC" | git rev-parse --parseopt -- "$@" || echo exit $?)"

get_repo_base() {
	(
		cd "`/bin/pwd`" &&
		cd "$1" || cd "$1.git" &&
		{
			cd .git
			pwd
		}
	) 2>/dev/null
}

if [ -n "$GIT_SSL_NO_VERIFY" -o \
	"`git config --bool http.sslVerify`" = false ]; then
    curl_extra_args="-k"
fi

http_fetch () {
	# $1 = Remote, $2 = Local
	curl -nsfL $curl_extra_args "$1" >"$2"
	curl_exit_status=$?
	case $curl_exit_status in
	126|127) exit ;;
	*)	 return $curl_exit_status ;;
	esac
}

clone_dumb_http () {
	# $1 - remote, $2 - local
	cd "$2" &&
	clone_tmp="$GIT_DIR/clone-tmp" &&
	mkdir -p "$clone_tmp" || exit 1
	if [ -n "$GIT_CURL_FTP_NO_EPSV" -o \
		"`git config --bool http.noEPSV`" = true ]; then
		curl_extra_args="${curl_extra_args} --disable-epsv"
	fi
	http_fetch "$1/info/refs" "$clone_tmp/refs" ||
		die "Cannot get remote repository information.
Perhaps git-update-server-info needs to be run there?"
	test "z$quiet" = z && v=-v || v=
	while read sha1 refname
	do
		name=`expr "z$refname" : 'zrefs/\(.*\)'` &&
		case "$name" in
		*^*)	continue;;
		esac
		case "$bare,$name" in
		yes,* | ,heads/* | ,tags/*) ;;
		*)	continue ;;
		esac
		if test -n "$use_separate_remote" &&
		   branch_name=`expr "z$name" : 'zheads/\(.*\)'`
		then
			tname="remotes/$origin/$branch_name"
		else
			tname=$name
		fi
		git-http-fetch $v -a -w "$tname" "$sha1" "$1" || exit 1
	done <"$clone_tmp/refs"
	rm -fr "$clone_tmp"
	http_fetch "$1/HEAD" "$GIT_DIR/REMOTE_HEAD" ||
	rm -f "$GIT_DIR/REMOTE_HEAD"
	if test -f "$GIT_DIR/REMOTE_HEAD"; then
		head_sha1=`cat "$GIT_DIR/REMOTE_HEAD"`
		case "$head_sha1" in
		'ref: refs/'*)
			;;
		*)
			git-http-fetch $v -a "$head_sha1" "$1" ||
			rm -f "$GIT_DIR/REMOTE_HEAD"
			;;
		esac
	fi
}

quiet=
local=no
use_local_hardlink=yes
local_shared=no
unset template
no_checkout=
upload_pack=
bare=
reference=
origin=
origin_override=
use_separate_remote=t
depth=
no_progress=
local_explicitly_asked_for=
test -t 1 || no_progress=--no-progress

while test $# != 0
do
	case "$1" in
	-n|--no-checkout)
		no_checkout=yes ;;
	--naked|--bare)
		bare=yes ;;
	-l|--local)
		local_explicitly_asked_for=yes
		use_local_hardlink=yes
		;;
	--no-hardlinks)
		use_local_hardlink=no ;;
	-s|--shared)
		local_shared=yes ;;
	--template)
		shift; template="--template=$1" ;;
	-q|--quiet)
		quiet=-q ;;
	--use-separate-remote|--no-separate-remote)
		die "clones are always made with separate-remote layout" ;;
	--reference)
		shift; reference="$1" ;;
	-o|--origin)
		shift;
		case "$1" in
		'')
		    usage ;;
		*/*)
		    die "'$1' is not suitable for an origin name"
		esac
		git check-ref-format "heads/$1" ||
		    die "'$1' is not suitable for a branch name"
		test -z "$origin_override" ||
		    die "Do not give more than one --origin options."
		origin_override=yes
		origin="$1"
		;;
	-u|--upload-pack)
		shift
		upload_pack="--upload-pack=$1" ;;
	--depth)
		shift
		depth="--depth=$1" ;;
	--)
		shift
		break ;;
	*)
		usage ;;
	esac
	shift
done

repo="$1"
test -n "$repo" ||
    die 'you must specify a repository to clone.'

# --bare implies --no-checkout and --no-separate-remote
if test yes = "$bare"
then
	if test yes = "$origin_override"
	then
		die '--bare and --origin $origin options are incompatible.'
	fi
	no_checkout=yes
	use_separate_remote=
fi

if test -z "$origin"
then
	origin=origin
fi

# Turn the source into an absolute path if
# it is local
if base=$(get_repo_base "$repo"); then
	repo="$base"
	if test -z "$depth"
	then
		local=yes
	fi
elif test -f "$repo"
then
	case "$repo" in /*) ;; *) repo="$PWD/$repo" ;; esac
fi

# Decide the directory name of the new repository
if test -n "$2"
then
	dir="$2"
	test $# = 2 || die "excess parameter to git-clone"
else
	# Derive one from the repository name
	# Try using "humanish" part of source repo if user didn't specify one
	if test -f "$repo"
	then
		# Cloning from a bundle
		dir=$(echo "$repo" | sed -e 's|/*\.bundle$||' -e 's|.*/||g')
	else
		dir=$(echo "$repo" |
			sed -e 's|/$||' -e 's|:*/*\.git$||' -e 's|.*[/:]||g')
	fi
fi

[ -e "$dir" ] && die "destination directory '$dir' already exists."
[ yes = "$bare" ] && unset GIT_WORK_TREE
[ -n "$GIT_WORK_TREE" ] && [ -e "$GIT_WORK_TREE" ] &&
die "working tree '$GIT_WORK_TREE' already exists."
D=
W=
cleanup() {
	test -z "$D" && rm -rf "$dir"
	test -z "$W" && test -n "$GIT_WORK_TREE" && rm -rf "$GIT_WORK_TREE"
	cd ..
	test -n "$D" && rm -rf "$D"
	test -n "$W" && rm -rf "$W"
	exit $err
}
trap 'err=$?; cleanup' 0
mkdir -p "$dir" && D=$(cd "$dir" && pwd) || usage
test -n "$GIT_WORK_TREE" && mkdir -p "$GIT_WORK_TREE" &&
W=$(cd "$GIT_WORK_TREE" && pwd) && GIT_WORK_TREE="$W" && export GIT_WORK_TREE
if test yes = "$bare" || test -n "$GIT_WORK_TREE"; then
	GIT_DIR="$D"
else
	GIT_DIR="$D/.git"
fi &&
export GIT_DIR &&
GIT_CONFIG="$GIT_DIR/config" git-init $quiet ${template+"$template"} || usage

if test -n "$bare"
then
	GIT_CONFIG="$GIT_DIR/config" git config core.bare true
fi

if test -n "$reference"
then
	ref_git=
	if test -d "$reference"
	then
		if test -d "$reference/.git/objects"
		then
			ref_git="$reference/.git"
		elif test -d "$reference/objects"
		then
			ref_git="$reference"
		fi
	fi
	if test -n "$ref_git"
	then
		ref_git=$(cd "$ref_git" && pwd)
		echo "$ref_git/objects" >"$GIT_DIR/objects/info/alternates"
		(
			GIT_DIR="$ref_git" git for-each-ref \
				--format='%(objectname) %(*objectname)'
		) |
		while read a b
		do
			test -z "$a" ||
			git update-ref "refs/reference-tmp/$a" "$a"
			test -z "$b" ||
			git update-ref "refs/reference-tmp/$b" "$b"
		done
	else
		die "reference repository '$reference' is not a local directory."
	fi
fi

rm -f "$GIT_DIR/CLONE_HEAD"

# We do local magic only when the user tells us to.
case "$local" in
yes)
	( cd "$repo/objects" ) ||
		die "cannot chdir to local '$repo/objects'."

	if test "$local_shared" = yes
	then
		mkdir -p "$GIT_DIR/objects/info"
		echo "$repo/objects" >>"$GIT_DIR/objects/info/alternates"
	else
		cpio_quiet_flag=""
		cpio --help 2>&1 | grep -- --quiet >/dev/null && \
			cpio_quiet_flag=--quiet
		l= &&
		if test "$use_local_hardlink" = yes
		then
			# See if we can hardlink and drop "l" if not.
			sample_file=$(cd "$repo" && \
				      find objects -type f -print | sed -e 1q)
			# objects directory should not be empty because
			# we are cloning!
			test -f "$repo/$sample_file" ||
				die "fatal: cannot clone empty repository"
			if ln "$repo/$sample_file" "$GIT_DIR/objects/sample" 2>/dev/null
			then
				rm -f "$GIT_DIR/objects/sample"
				l=l
			elif test -n "$local_explicitly_asked_for"
			then
				echo >&2 "Warning: -l asked but cannot hardlink to $repo"
			fi
		fi &&
		cd "$repo" &&
		# Create dirs using umask and permissions and destination
		find objects -type d -print | (cd "$GIT_DIR" && xargs mkdir -p) &&
		# Copy existing 0444 permissions on content
		find objects ! -type d -print | cpio $cpio_quiet_flag -pumd$l "$GIT_DIR/" || \
			exit 1
	fi
	git-ls-remote "$repo" >"$GIT_DIR/CLONE_HEAD" || exit 1
	;;
*)
	case "$repo" in
	rsync://*)
		case "$depth" in
		"") ;;
		*) die "shallow over rsync not supported" ;;
		esac
		rsync $quiet -av --ignore-existing  \
			--exclude info "$repo/objects/" "$GIT_DIR/objects/" ||
		exit
		# Look at objects/info/alternates for rsync -- http will
		# support it natively and git native ones will do it on the
		# remote end.  Not having that file is not a crime.
		rsync -q "$repo/objects/info/alternates" \
			"$GIT_DIR/TMP_ALT" 2>/dev/null ||
			rm -f "$GIT_DIR/TMP_ALT"
		if test -f "$GIT_DIR/TMP_ALT"
		then
		    ( cd "$D" &&
		      . git-parse-remote &&
		      resolve_alternates "$repo" <"$GIT_DIR/TMP_ALT" ) |
		    while read alt
		    do
			case "$alt" in 'bad alternate: '*) die "$alt";; esac
			case "$quiet" in
			'')	echo >&2 "Getting alternate: $alt" ;;
			esac
			rsync $quiet -av --ignore-existing  \
			    --exclude info "$alt" "$GIT_DIR/objects" || exit
		    done
		    rm -f "$GIT_DIR/TMP_ALT"
		fi
		git-ls-remote "$repo" >"$GIT_DIR/CLONE_HEAD" || exit 1
		;;
	https://*|http://*|ftp://*)
		case "$depth" in
		"") ;;
		*) die "shallow over http or ftp not supported" ;;
		esac
		if test -z "@@NO_CURL@@"
		then
			clone_dumb_http "$repo" "$D"
		else
			die "http transport not supported, rebuild Git with curl support"
		fi
		;;
	*)
		if [ -f "$repo" ] ; then
			git bundle unbundle "$repo" > "$GIT_DIR/CLONE_HEAD" ||
			die "unbundle from '$repo' failed."
		else
			case "$upload_pack" in
			'') git-fetch-pack --all -k $quiet $depth $no_progress "$repo";;
			*) git-fetch-pack --all -k \
				$quiet "$upload_pack" $depth $no_progress "$repo" ;;
			esac >"$GIT_DIR/CLONE_HEAD" ||
			die "fetch-pack from '$repo' failed."
		fi
		;;
	esac
	;;
esac
test -d "$GIT_DIR/refs/reference-tmp" && rm -fr "$GIT_DIR/refs/reference-tmp"

if test -f "$GIT_DIR/CLONE_HEAD"
then
	# Read git-fetch-pack -k output and store the remote branches.
	if [ -n "$use_separate_remote" ]
	then
		branch_top="remotes/$origin"
	else
		branch_top="heads"
	fi
	tag_top="tags"
	while read sha1 name
	do
		case "$name" in
		*'^{}')
			continue ;;
		HEAD)
			destname="REMOTE_HEAD" ;;
		refs/heads/*)
			destname="refs/$branch_top/${name#refs/heads/}" ;;
		refs/tags/*)
			destname="refs/$tag_top/${name#refs/tags/}" ;;
		*)
			continue ;;
		esac
		git update-ref -m "clone: from $repo" "$destname" "$sha1" ""
	done < "$GIT_DIR/CLONE_HEAD"
fi

if test -n "$W"; then
	cd "$W" || exit
else
	cd "$D" || exit
fi

if test -z "$bare"
then
	# a non-bare repository is always in separate-remote layout
	remote_top="refs/remotes/$origin"
	head_sha1=
	test ! -r "$GIT_DIR/REMOTE_HEAD" || head_sha1=`cat "$GIT_DIR/REMOTE_HEAD"`
	case "$head_sha1" in
	'ref: refs/'*)
		# Uh-oh, the remote told us (http transport done against
		# new style repository with a symref HEAD).
		# Ideally we should skip the guesswork but for now
		# opt for minimum change.
		head_sha1=`expr "z$head_sha1" : 'zref: refs/heads/\(.*\)'`
		head_sha1=`cat "$GIT_DIR/$remote_top/$head_sha1"`
		;;
	esac

	# The name under $remote_top the remote HEAD seems to point at.
	head_points_at=$(
		(
			test -f "$GIT_DIR/$remote_top/master" && echo "master"
			cd "$GIT_DIR/$remote_top" &&
			find . -type f -print | sed -e 's/^\.\///'
		) | (
		done=f
		while read name
		do
			test t = $done && continue
			branch_tip=`cat "$GIT_DIR/$remote_top/$name"`
			if test "$head_sha1" = "$branch_tip"
			then
				echo "$name"
				done=t
			fi
		done
		)
	)

	# Upstream URL
	git config remote."$origin".url "$repo" &&

	# Set up the mappings to track the remote branches.
	git config remote."$origin".fetch \
		"+refs/heads/*:$remote_top/*" '^$' &&

	# Write out remote.$origin config, and update our "$head_points_at".
	case "$head_points_at" in
	?*)
		# Local default branch
		git symbolic-ref HEAD "refs/heads/$head_points_at" &&

		# Tracking branch for the primary branch at the remote.
		git update-ref HEAD "$head_sha1" &&

		rm -f "refs/remotes/$origin/HEAD"
		git symbolic-ref "refs/remotes/$origin/HEAD" \
			"refs/remotes/$origin/$head_points_at" &&

		git config branch."$head_points_at".remote "$origin" &&
		git config branch."$head_points_at".merge "refs/heads/$head_points_at"
		;;
	'')
		if test -z "$head_sha1"
		then
			# Source had nonexistent ref in HEAD
			echo >&2 "Warning: Remote HEAD refers to nonexistent ref, unable to checkout."
			no_checkout=t
		else
			# Source had detached HEAD pointing nowhere
			git update-ref --no-deref HEAD "$head_sha1" &&
			rm -f "refs/remotes/$origin/HEAD"
		fi
		;;
	esac

	case "$no_checkout" in
	'')
		test "z$quiet" = z -a "z$no_progress" = z && v=-v || v=
		git read-tree -m -u $v HEAD HEAD
	esac
fi
rm -f "$GIT_DIR/CLONE_HEAD" "$GIT_DIR/REMOTE_HEAD"

trap - 0
