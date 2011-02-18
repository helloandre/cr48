#!/bin/sh

test_description='merging with submodules'

. ./test-lib.sh

#
# history
#
#        a --- c
#      /   \ /
# root      X
#      \   / \
#        b --- d
#

test_expect_success setup '

	mkdir sub &&
	(cd sub &&
	 git init &&
	 echo original > file &&
	 git add file &&
	 test_tick &&
	 git commit -m sub-root) &&
	git add sub &&
	test_tick &&
	git commit -m root &&

	git checkout -b a master &&
	(cd sub &&
	 echo A > file &&
	 git add file &&
	 test_tick &&
	 git commit -m sub-a) &&
	git add sub &&
	test_tick &&
	git commit -m a &&

	git checkout -b b master &&
	(cd sub &&
	 echo B > file &&
	 git add file &&
	 test_tick &&
	 git commit -m sub-b) &&
	git add sub &&
	test_tick &&
	git commit -m b &&

	git checkout -b c a &&
	git merge -s ours b &&

	git checkout -b d b &&
	git merge -s ours a
'

# History setup
#
#      b
#    /   \
#   a     d
#    \   /
#      c
#
# a in the main repository records to sub-a in the submodule and
# analogous b and c. d should be automatically found by merging c into
# b in the main repository.
test_expect_success 'setup for merge search' '
	mkdir merge-search &&
	(cd merge-search &&
	git init &&
	mkdir sub &&
	(cd sub &&
	 git init &&
	 echo "file-a" > file-a &&
	 git add file-a &&
	 git commit -m "sub-a" &&
	 git branch sub-a) &&
	git add sub &&
	git commit -m "a" &&
	git branch a &&

	git checkout -b b &&
	(cd sub &&
	 git checkout -b sub-b &&
	 echo "file-b" > file-b &&
	 git add file-b &&
	 git commit -m "sub-b") &&
	git commit -a -m "b" &&

	git checkout -b c a &&
	(cd sub &&
	 git checkout -b sub-c sub-a &&
	 echo "file-c" > file-c &&
	 git add file-c &&
	 git commit -m "sub-c") &&
	git commit -a -m "c" &&

	git checkout -b d a &&
	(cd sub &&
	 git checkout -b sub-d sub-b &&
	 git merge sub-c) &&
	git commit -a -m "d" &&
	git branch test b)
'

test_expect_success 'merge with one side as a fast-forward of the other' '
	(cd merge-search &&
	 git checkout -b test-forward b &&
	 git merge d &&
	 git ls-tree test-forward sub | cut -f1 | cut -f3 -d" " > actual &&
	 (cd sub &&
	  git rev-parse sub-d > ../expect) &&
	 test_cmp actual expect)
'

test_expect_success 'merging should conflict for non fast-forward' '
	(cd merge-search &&
	 git checkout -b test-nonforward b &&
	 (cd sub &&
	  git rev-parse sub-d > ../expect) &&
	 test_must_fail git merge c 2> actual  &&
	 grep $(cat expect) actual > /dev/null &&
	 git reset --hard)
'

test_expect_success 'merging should fail for ambiguous common parent' '
	(cd merge-search &&
	git checkout -b test-ambiguous b &&
	(cd sub &&
	 git checkout -b ambiguous sub-b &&
	 git merge sub-c &&
	 git rev-parse sub-d > ../expect1 &&
	 git rev-parse ambiguous > ../expect2) &&
	test_must_fail git merge c 2> actual &&
	grep $(cat expect1) actual > /dev/null &&
	grep $(cat expect2) actual > /dev/null &&
	git reset --hard)
'

# in a situation like this
#
# submodule tree:
#
#    sub-a --- sub-b --- sub-d
#
# main tree:
#
#    e (sub-a)
#   /
#  bb (sub-b)
#   \
#    f (sub-d)
#
# A merge between e and f should fail because one of the submodule
# commits (sub-a) does not descend from the submodule merge-base (sub-b).
#
test_expect_success 'merging should fail for changes that are backwards' '
	(cd merge-search &&
	git checkout -b bb a &&
	(cd sub &&
	 git checkout sub-b) &&
	git commit -a -m "bb" &&

	git checkout -b e bb &&
	(cd sub &&
	 git checkout sub-a) &&
	git commit -a -m "e" &&

	git checkout -b f bb &&
	(cd sub &&
	 git checkout sub-d) &&
	git commit -a -m "f" &&

	git checkout -b test-backward e &&
	test_must_fail git merge f)
'

test_expect_success 'merging with a modify/modify conflict between merge bases' '
	git reset --hard HEAD &&
	git checkout -b test2 c &&
	git merge d
'

test_done
