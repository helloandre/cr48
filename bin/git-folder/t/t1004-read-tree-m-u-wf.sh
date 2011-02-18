#!/bin/sh

test_description='read-tree -m -u checks working tree files'

. ./test-lib.sh

# two-tree test

test_expect_success 'two-way setup' '

	mkdir subdir &&
	echo >file1 file one &&
	echo >file2 file two &&
	echo >subdir/file1 file one in subdirectory &&
	echo >subdir/file2 file two in subdirectory &&
	git update-index --add file1 file2 subdir/file1 subdir/file2 &&
	git commit -m initial &&

	git branch side &&
	git tag -f branch-point &&

	echo file2 is not tracked on the master anymore &&
	rm -f file2 subdir/file2 &&
	git update-index --remove file2 subdir/file2 &&
	git commit -a -m "master removes file2 and subdir/file2"
'

test_expect_success 'two-way not clobbering' '

	echo >file2 master creates untracked file2 &&
	echo >subdir/file2 master creates untracked subdir/file2 &&
	if err=`git read-tree -m -u master side 2>&1`
	then
		echo should have complained
		false
	else
		echo "happy to see $err"
	fi
'

echo file2 >.gitignore

test_expect_success 'two-way with incorrect --exclude-per-directory (1)' '

	if err=`git read-tree -m --exclude-per-directory=.gitignore master side 2>&1`
	then
		echo should have complained
		false
	else
		echo "happy to see $err"
	fi
'

test_expect_success 'two-way with incorrect --exclude-per-directory (2)' '

	if err=`git read-tree -m -u --exclude-per-directory=foo --exclude-per-directory=.gitignore master side 2>&1`
	then
		echo should have complained
		false
	else
		echo "happy to see $err"
	fi
'

test_expect_success 'two-way clobbering a ignored file' '

	git read-tree -m -u --exclude-per-directory=.gitignore master side
'

rm -f .gitignore

# three-tree test

test_expect_success 'three-way not complaining on an untracked path in both' '

	rm -f file2 subdir/file2 &&
	git checkout side &&
	echo >file3 file three &&
	echo >subdir/file3 file three &&
	git update-index --add file3 subdir/file3 &&
	git commit -a -m "side adds file3 and removes file2" &&

	git checkout master &&
	echo >file2 file two is untracked on the master side &&
	echo >subdir/file2 file two is untracked on the master side &&

	git read-tree -m -u branch-point master side
'

test_expect_success 'three-way not clobbering a working tree file' '

	git reset --hard &&
	rm -f file2 subdir/file2 file3 subdir/file3 &&
	git checkout master &&
	echo >file3 file three created in master, untracked &&
	echo >subdir/file3 file three created in master, untracked &&
	if err=`git read-tree -m -u branch-point master side 2>&1`
	then
		echo should have complained
		false
	else
		echo "happy to see $err"
	fi
'

echo >.gitignore file3

test_expect_success 'three-way not complaining on an untracked file' '

	git reset --hard &&
	rm -f file2 subdir/file2 file3 subdir/file3 &&
	git checkout master &&
	echo >file3 file three created in master, untracked &&
	echo >subdir/file3 file three created in master, untracked &&

	git read-tree -m -u --exclude-per-directory=.gitignore branch-point master side
'

test_expect_success '3-way not overwriting local changes (setup)' '

	git reset --hard &&
	git checkout -b side-a branch-point &&
	echo >>file1 "new line to be kept in the merge result" &&
	git commit -a -m "side-a changes file1" &&
	git checkout -b side-b branch-point &&
	echo >>file2 "new line to be kept in the merge result" &&
	git commit -a -m "side-b changes file2" &&
	git checkout side-a

'

test_expect_success '3-way not overwriting local changes (our side)' '

	# At this point, file1 from side-a should be kept as side-b
	# did not touch it.

	git reset --hard &&

	echo >>file1 "local changes" &&
	git read-tree -m -u branch-point side-a side-b &&
	grep "new line to be kept" file1 &&
	grep "local changes" file1

'

test_expect_success '3-way not overwriting local changes (their side)' '

	# At this point, file2 from side-b should be taken as side-a
	# did not touch it.

	git reset --hard &&

	echo >>file2 "local changes" &&
	test_must_fail git read-tree -m -u branch-point side-a side-b &&
	! grep "new line to be kept" file2 &&
	grep "local changes" file2

'

test_expect_success SYMLINKS 'funny symlink in work tree' '

	git reset --hard &&
	git checkout -b sym-b side-b &&
	mkdir -p a &&
	>a/b &&
	git add a/b &&
	git commit -m "side adds a/b" &&

	rm -fr a &&
	git checkout -b sym-a side-a &&
	mkdir -p a &&
	ln -s ../b a/b &&
	git add a/b &&
	git commit -m "we add a/b" &&

	git read-tree -m -u sym-a sym-a sym-b

'

test_expect_success SYMLINKS,SANITY 'funny symlink in work tree, un-unlink-able' '

	rm -fr a b &&
	git reset --hard &&

	git checkout sym-a &&
	chmod a-w a &&
	test_must_fail git read-tree -m -u sym-a sym-a sym-b

'

# clean-up from the above test
chmod a+w a 2>/dev/null
rm -fr a b

test_expect_success 'D/F setup' '

	git reset --hard &&

	git checkout side-a &&
	rm -f subdir/file2 &&
	mkdir subdir/file2 &&
	echo qfwfq >subdir/file2/another &&
	git add subdir/file2/another &&
	test_tick &&
	git commit -m "side-a changes file2 to directory"

'

test_expect_success 'D/F' '

	git checkout side-b &&
	git read-tree -m -u branch-point side-b side-a &&
	git ls-files -u >actual &&
	(
		a=$(git rev-parse branch-point:subdir/file2)
		b=$(git rev-parse side-a:subdir/file2/another)
		echo "100644 $a 1	subdir/file2"
		echo "100644 $a 2	subdir/file2"
		echo "100644 $b 3	subdir/file2/another"
	) >expect &&
	test_cmp actual expect

'

test_expect_success 'D/F resolve' '

	git reset --hard &&
	git checkout side-b &&
	git merge-resolve branch-point -- side-b side-a

'

test_expect_success 'D/F recursive' '

	git reset --hard &&
	git checkout side-b &&
	git merge-recursive branch-point -- side-b side-a

'

test_done
