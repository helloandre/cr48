#!/bin/sh
#
# Copyright (c) 2010 Sverre Rabbelier
#

test_description='Test remote-helper import and export commands'

. ./test-lib.sh

if test_have_prereq PYTHON && "$PYTHON_PATH" -c '
import sys
if sys.hexversion < 0x02040000:
    sys.exit(1)
'
then
    # Requires Python 2.4 or newer
	test_set_prereq PYTHON_24
fi

test_expect_success PYTHON_24 'setup repository' '
	git init --bare server/.git &&
	git clone server public &&
	(cd public &&
	 echo content >file &&
	 git add file &&
	 git commit -m one &&
	 git push origin master)
'

test_expect_success PYTHON_24 'cloning from local repo' '
	git clone "testgit::${PWD}/server" localclone &&
	test_cmp public/file localclone/file
'

test_expect_success PYTHON_24 'cloning from remote repo' '
	git clone "testgit::file://${PWD}/server" clone &&
	test_cmp public/file clone/file
'

test_expect_success PYTHON_24 'create new commit on remote' '
	(cd public &&
	 echo content >>file &&
	 git commit -a -m two &&
	 git push)
'

test_expect_success PYTHON_24 'pulling from local repo' '
	(cd localclone && git pull) &&
	test_cmp public/file localclone/file
'

test_expect_success PYTHON_24 'pulling from remote remote' '
	(cd clone && git pull) &&
	test_cmp public/file clone/file
'

test_expect_success PYTHON_24 'pushing to local repo' '
	(cd localclone &&
	echo content >>file &&
	git commit -a -m three &&
	git push) &&
	HEAD=$(git --git-dir=localclone/.git rev-parse --verify HEAD) &&
	test $HEAD = $(git --git-dir=server/.git rev-parse --verify HEAD)
'

test_expect_success PYTHON_24 'synch with changes from localclone' '
	(cd clone &&
	 git pull)
'

test_expect_success PYTHON_24 'pushing remote local repo' '
	(cd clone &&
	echo content >>file &&
	git commit -a -m four &&
	git push) &&
	HEAD=$(git --git-dir=clone/.git rev-parse --verify HEAD) &&
	test $HEAD = $(git --git-dir=server/.git rev-parse --verify HEAD)
'

test_done
