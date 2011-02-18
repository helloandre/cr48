#!/bin/sh
#
# Copyright (c) 2005 Junio C Hamano
#

test_description='git apply symlinks and partial files

'

. ./test-lib.sh

test_expect_success SYMLINKS setup '

	ln -s path1/path2/path3/path4/path5 link1 &&
	git add link? &&
	git commit -m initial &&

	git branch side &&

	rm -f link? &&

	ln -s htap6 link1 &&
	git update-index link? &&
	git commit -m second &&

	git diff-tree -p HEAD^ HEAD >patch  &&
	git apply --stat --summary patch

'

test_expect_success SYMLINKS 'apply symlink patch' '

	git checkout side &&
	git apply patch &&
	git diff-files -p >patched &&
	test_cmp patch patched

'

test_expect_success SYMLINKS 'apply --index symlink patch' '

	git checkout -f side &&
	git apply --index patch &&
	git diff-index --cached -p HEAD >patched &&
	test_cmp patch patched

'

test_done
