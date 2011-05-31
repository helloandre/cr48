#!/bin/sh
#
# Copyright (c) 2005 Junio C Hamano
#

test_description='Test the very basics part #1.

The rest of the test suite does not check the basic operation of git
plumbing commands to work very carefully.  Their job is to concentrate
on tricky features that caused bugs in the past to detect regression.

This test runs very basic features, like registering things in cache,
writing tree, etc.

Note that this test *deliberately* hard-codes many expected object
IDs.  When object ID computation changes, like in the previous case of
swapping compression and hashing order, the person who is making the
modification *should* take notice and update the test vectors here.
'

################################################################
# It appears that people try to run tests without building...

../git >/dev/null
if test $? != 1
then
	echo >&2 'You do not seem to have built git yet.'
	exit 1
fi

. ./test-lib.sh

################################################################
# git init has been done in an empty repository.
# make sure it is empty.

find .git/objects -type f -print >should-be-empty
test_expect_success \
    '.git/objects should be empty after git init in an empty repo.' \
    'cmp -s /dev/null should-be-empty'

# also it should have 2 subdirectories; no fan-out anymore, pack, and info.
# 3 is counting "objects" itself
find .git/objects -type d -print >full-of-directories
test_expect_success \
    '.git/objects should have 3 subdirectories.' \
    'test $(wc -l < full-of-directories) = 3'

################################################################
# Test harness
test_expect_success 'success is reported like this' '
    :
'
test_expect_failure 'pretend we have a known breakage' '
    false
'

test_expect_success 'pretend we have fixed a known breakage (run in sub test-lib)' "
    mkdir passing-todo &&
    (cd passing-todo &&
    cat >passing-todo.sh <<EOF &&
#!$SHELL_PATH

test_description='A passing TODO test

This is run in a sub test-lib so that we do not get incorrect passing
metrics
'

# Point to the t/test-lib.sh, which isn't in ../ as usual
TEST_DIRECTORY=\"$TEST_DIRECTORY\"
. \"\$TEST_DIRECTORY\"/test-lib.sh

test_expect_failure 'pretend we have fixed a known breakage' '
    :
'

test_done
EOF
    chmod +x passing-todo.sh &&
    ./passing-todo.sh >out 2>err &&
    ! test -s err &&
sed -e 's/^> //' >expect <<EOF &&
> ok 1 - pretend we have fixed a known breakage # TODO known breakage
> # fixed 1 known breakage(s)
> # passed all 1 test(s)
> 1..1
EOF
    test_cmp expect out)
"
test_set_prereq HAVEIT
haveit=no
test_expect_success HAVEIT 'test runs if prerequisite is satisfied' '
    test_have_prereq HAVEIT &&
    haveit=yes
'
donthaveit=yes
test_expect_success DONTHAVEIT 'unmet prerequisite causes test to be skipped' '
    donthaveit=no
'
if test $haveit$donthaveit != yesyes
then
	say "bug in test framework: prerequisite tags do not work reliably"
	exit 1
fi

test_set_prereq HAVETHIS
haveit=no
test_expect_success HAVETHIS,HAVEIT 'test runs if prerequisites are satisfied' '
    test_have_prereq HAVEIT &&
    test_have_prereq HAVETHIS &&
    haveit=yes
'
donthaveit=yes
test_expect_success HAVEIT,DONTHAVEIT 'unmet prerequisites causes test to be skipped' '
    donthaveit=no
'
donthaveiteither=yes
test_expect_success DONTHAVEIT,HAVEIT 'unmet prerequisites causes test to be skipped' '
    donthaveiteither=no
'
if test $haveit$donthaveit$donthaveiteither != yesyesyes
then
	say "bug in test framework: multiple prerequisite tags do not work reliably"
	exit 1
fi

clean=no
test_expect_success 'tests clean up after themselves' '
    test_when_finished clean=yes
'

if test $clean != yes
then
	say "bug in test framework: basic cleanup command does not work reliably"
	exit 1
fi

test_expect_success 'tests clean up even on failures' "
    mkdir failing-cleanup &&
    (cd failing-cleanup &&
    cat >failing-cleanup.sh <<EOF &&
#!$SHELL_PATH

test_description='Failing tests with cleanup commands'

# Point to the t/test-lib.sh, which isn't in ../ as usual
TEST_DIRECTORY=\"$TEST_DIRECTORY\"
. \"\$TEST_DIRECTORY\"/test-lib.sh

test_expect_success 'tests clean up even after a failure' '
    touch clean-after-failure &&
    test_when_finished rm clean-after-failure &&
    (exit 1)
'

test_expect_success 'failure to clean up causes the test to fail' '
    test_when_finished \"(exit 2)\"
'

test_done
EOF
    chmod +x failing-cleanup.sh &&
    test_must_fail ./failing-cleanup.sh >out 2>err &&
    ! test -s err &&
    ! test -f \"trash directory.failing-cleanup/clean-after-failure\" &&
sed -e 's/Z$//' -e 's/^> //' >expect <<\EOF &&
> not ok - 1 tests clean up even after a failure
> #	Z
> #	    touch clean-after-failure &&
> #	    test_when_finished rm clean-after-failure &&
> #	    (exit 1)
> #	Z
> not ok - 2 failure to clean up causes the test to fail
> #	Z
> #	    test_when_finished \"(exit 2)\"
> #	Z
> # failed 2 among 2 test(s)
> 1..2
EOF
    test_cmp expect out)
"

################################################################
# Basics of the basics

# updating a new file without --add should fail.
test_expect_success 'git update-index without --add should fail adding.' '
    test_must_fail git update-index should-be-empty
'

# and with --add it should succeed, even if it is empty (it used to fail).
test_expect_success \
    'git update-index with --add should succeed.' \
    'git update-index --add should-be-empty'

test_expect_success \
    'writing tree out with git write-tree' \
    'tree=$(git write-tree)'

# we know the shape and contents of the tree and know the object ID for it.
test_expect_success \
    'validate object ID of a known tree.' \
    'test "$tree" = 7bb943559a305bdd6bdee2cef6e5df2413c3d30a'

# Removing paths.
rm -f should-be-empty full-of-directories
test_expect_success 'git update-index without --remove should fail removing.' '
    test_must_fail git update-index should-be-empty
'

test_expect_success \
    'git update-index with --remove should be able to remove.' \
    'git update-index --remove should-be-empty'

# Empty tree can be written with recent write-tree.
test_expect_success \
    'git write-tree should be able to write an empty tree.' \
    'tree=$(git write-tree)'

test_expect_success \
    'validate object ID of a known tree.' \
    'test "$tree" = 4b825dc642cb6eb9a060e54bf8d69288fbee4904'

# Various types of objects
# Some filesystems do not support symblic links; on such systems
# some expected values are different
mkdir path2 path3 path3/subp3
paths='path0 path2/file2 path3/file3 path3/subp3/file3'
for p in $paths
do
    echo "hello $p" >$p
done
if test_have_prereq SYMLINKS
then
	for p in $paths
	do
		ln -s "hello $p" ${p}sym
	done
	expectfilter=cat
	expectedtree=087704a96baf1c2d1c869a8b084481e121c88b5b
	expectedptree1=21ae8269cacbe57ae09138dcc3a2887f904d02b3
	expectedptree2=3c5e5399f3a333eddecce7a9b9465b63f65f51e2
else
	expectfilter='grep -v sym'
	expectedtree=8e18edf7d7edcf4371a3ac6ae5f07c2641db7c46
	expectedptree1=cfb8591b2f65de8b8cc1020cd7d9e67e7793b325
	expectedptree2=ce580448f0148b985a513b693fdf7d802cacb44f
fi

test_expect_success \
    'adding various types of objects with git update-index --add.' \
    'find path* ! -type d -print | xargs git update-index --add'

# Show them and see that matches what we expect.
test_expect_success \
    'showing stage with git ls-files --stage' \
    'git ls-files --stage >current'

$expectfilter >expected <<\EOF
100644 f87290f8eb2cbbea7857214459a0739927eab154 0	path0
120000 15a98433ae33114b085f3eb3bb03b832b3180a01 0	path0sym
100644 3feff949ed00a62d9f7af97c15cd8a30595e7ac7 0	path2/file2
120000 d8ce161addc5173867a3c3c730924388daedbc38 0	path2/file2sym
100644 0aa34cae68d0878578ad119c86ca2b5ed5b28376 0	path3/file3
120000 8599103969b43aff7e430efea79ca4636466794f 0	path3/file3sym
100644 00fb5908cb97c2564a9783c0c64087333b3b464f 0	path3/subp3/file3
120000 6649a1ebe9e9f1c553b66f5a6e74136a07ccc57c 0	path3/subp3/file3sym
EOF
test_expect_success \
    'validate git ls-files output for a known tree.' \
    'test_cmp expected current'

test_expect_success \
    'writing tree out with git write-tree.' \
    'tree=$(git write-tree)'
test_expect_success \
    'validate object ID for a known tree.' \
    'test "$tree" = "$expectedtree"'

test_expect_success \
    'showing tree with git ls-tree' \
    'git ls-tree $tree >current'
cat >expected <<\EOF
100644 blob f87290f8eb2cbbea7857214459a0739927eab154	path0
120000 blob 15a98433ae33114b085f3eb3bb03b832b3180a01	path0sym
040000 tree 58a09c23e2ca152193f2786e06986b7b6712bdbe	path2
040000 tree 21ae8269cacbe57ae09138dcc3a2887f904d02b3	path3
EOF
test_expect_success SYMLINKS \
    'git ls-tree output for a known tree.' \
    'test_cmp expected current'

# This changed in ls-tree pathspec change -- recursive does
# not show tree nodes anymore.
test_expect_success \
    'showing tree with git ls-tree -r' \
    'git ls-tree -r $tree >current'
$expectfilter >expected <<\EOF
100644 blob f87290f8eb2cbbea7857214459a0739927eab154	path0
120000 blob 15a98433ae33114b085f3eb3bb03b832b3180a01	path0sym
100644 blob 3feff949ed00a62d9f7af97c15cd8a30595e7ac7	path2/file2
120000 blob d8ce161addc5173867a3c3c730924388daedbc38	path2/file2sym
100644 blob 0aa34cae68d0878578ad119c86ca2b5ed5b28376	path3/file3
120000 blob 8599103969b43aff7e430efea79ca4636466794f	path3/file3sym
100644 blob 00fb5908cb97c2564a9783c0c64087333b3b464f	path3/subp3/file3
120000 blob 6649a1ebe9e9f1c553b66f5a6e74136a07ccc57c	path3/subp3/file3sym
EOF
test_expect_success \
    'git ls-tree -r output for a known tree.' \
    'test_cmp expected current'

# But with -r -t we can have both.
test_expect_success \
    'showing tree with git ls-tree -r -t' \
    'git ls-tree -r -t $tree >current'
cat >expected <<\EOF
100644 blob f87290f8eb2cbbea7857214459a0739927eab154	path0
120000 blob 15a98433ae33114b085f3eb3bb03b832b3180a01	path0sym
040000 tree 58a09c23e2ca152193f2786e06986b7b6712bdbe	path2
100644 blob 3feff949ed00a62d9f7af97c15cd8a30595e7ac7	path2/file2
120000 blob d8ce161addc5173867a3c3c730924388daedbc38	path2/file2sym
040000 tree 21ae8269cacbe57ae09138dcc3a2887f904d02b3	path3
100644 blob 0aa34cae68d0878578ad119c86ca2b5ed5b28376	path3/file3
120000 blob 8599103969b43aff7e430efea79ca4636466794f	path3/file3sym
040000 tree 3c5e5399f3a333eddecce7a9b9465b63f65f51e2	path3/subp3
100644 blob 00fb5908cb97c2564a9783c0c64087333b3b464f	path3/subp3/file3
120000 blob 6649a1ebe9e9f1c553b66f5a6e74136a07ccc57c	path3/subp3/file3sym
EOF
test_expect_success SYMLINKS \
    'git ls-tree -r output for a known tree.' \
    'test_cmp expected current'

test_expect_success \
    'writing partial tree out with git write-tree --prefix.' \
    'ptree=$(git write-tree --prefix=path3)'
test_expect_success \
    'validate object ID for a known tree.' \
    'test "$ptree" = "$expectedptree1"'

test_expect_success \
    'writing partial tree out with git write-tree --prefix.' \
    'ptree=$(git write-tree --prefix=path3/subp3)'
test_expect_success \
    'validate object ID for a known tree.' \
    'test "$ptree" = "$expectedptree2"'

cat >badobjects <<EOF
100644 blob 1000000000000000000000000000000000000000	dir/file1
100644 blob 2000000000000000000000000000000000000000	dir/file2
100644 blob 3000000000000000000000000000000000000000	dir/file3
100644 blob 4000000000000000000000000000000000000000	dir/file4
100644 blob 5000000000000000000000000000000000000000	dir/file5
EOF

rm .git/index
test_expect_success \
    'put invalid objects into the index.' \
    'git update-index --index-info < badobjects'

test_expect_success 'writing this tree without --missing-ok.' '
    test_must_fail git write-tree
'

test_expect_success \
    'writing this tree with --missing-ok.' \
    'git write-tree --missing-ok'


################################################################
rm .git/index
test_expect_success \
    'git read-tree followed by write-tree should be idempotent.' \
    'git read-tree $tree &&
     test -f .git/index &&
     newtree=$(git write-tree) &&
     test "$newtree" = "$tree"'

$expectfilter >expected <<\EOF
:100644 100644 f87290f8eb2cbbea7857214459a0739927eab154 0000000000000000000000000000000000000000 M	path0
:120000 120000 15a98433ae33114b085f3eb3bb03b832b3180a01 0000000000000000000000000000000000000000 M	path0sym
:100644 100644 3feff949ed00a62d9f7af97c15cd8a30595e7ac7 0000000000000000000000000000000000000000 M	path2/file2
:120000 120000 d8ce161addc5173867a3c3c730924388daedbc38 0000000000000000000000000000000000000000 M	path2/file2sym
:100644 100644 0aa34cae68d0878578ad119c86ca2b5ed5b28376 0000000000000000000000000000000000000000 M	path3/file3
:120000 120000 8599103969b43aff7e430efea79ca4636466794f 0000000000000000000000000000000000000000 M	path3/file3sym
:100644 100644 00fb5908cb97c2564a9783c0c64087333b3b464f 0000000000000000000000000000000000000000 M	path3/subp3/file3
:120000 120000 6649a1ebe9e9f1c553b66f5a6e74136a07ccc57c 0000000000000000000000000000000000000000 M	path3/subp3/file3sym
EOF
test_expect_success \
    'validate git diff-files output for a know cache/work tree state.' \
    'git diff-files >current && test_cmp current expected >/dev/null'

test_expect_success \
    'git update-index --refresh should succeed.' \
    'git update-index --refresh'

test_expect_success \
    'no diff after checkout and git update-index --refresh.' \
    'git diff-files >current && cmp -s current /dev/null'

################################################################
P=$expectedtree
test_expect_success \
    'git commit-tree records the correct tree in a commit.' \
    'commit0=$(echo NO | git commit-tree $P) &&
     tree=$(git show --pretty=raw $commit0 |
	 sed -n -e "s/^tree //p" -e "/^author /q") &&
     test "z$tree" = "z$P"'

test_expect_success \
    'git commit-tree records the correct parent in a commit.' \
    'commit1=$(echo NO | git commit-tree $P -p $commit0) &&
     parent=$(git show --pretty=raw $commit1 |
	 sed -n -e "s/^parent //p" -e "/^author /q") &&
     test "z$commit0" = "z$parent"'

test_expect_success \
    'git commit-tree omits duplicated parent in a commit.' \
    'commit2=$(echo NO | git commit-tree $P -p $commit0 -p $commit0) &&
     parent=$(git show --pretty=raw $commit2 |
	 sed -n -e "s/^parent //p" -e "/^author /q" |
	 sort -u) &&
     test "z$commit0" = "z$parent" &&
     numparent=$(git show --pretty=raw $commit2 |
	 sed -n -e "s/^parent //p" -e "/^author /q" |
	 wc -l) &&
     test $numparent = 1'

test_expect_success 'update-index D/F conflict' '
	mv path0 tmp &&
	mv path2 path0 &&
	mv tmp path2 &&
	git update-index --add --replace path2 path0/file2 &&
	numpath0=$(git ls-files path0 | wc -l) &&
	test $numpath0 = 1
'

test_expect_success SYMLINKS 'real path works as expected' '
	mkdir first &&
	ln -s ../.git first/.git &&
	mkdir second &&
	ln -s ../first second/other &&
	mkdir third &&
	dir="$(cd .git; pwd -P)" &&
	dir2=third/../second/other/.git &&
	test "$dir" = "$(test-path-utils real_path $dir2)" &&
	file="$dir"/index &&
	test "$file" = "$(test-path-utils real_path $dir2/index)" &&
	basename=blub &&
	test "$dir/$basename" = "$(cd .git && test-path-utils real_path "$basename")" &&
	ln -s ../first/file .git/syml &&
	sym="$(cd first; pwd -P)"/file &&
	test "$sym" = "$(test-path-utils real_path "$dir2/syml")"
'

test_expect_success 'very long name in the index handled sanely' '

	a=a && # 1
	a=$a$a$a$a$a$a$a$a$a$a$a$a$a$a$a$a && # 16
	a=$a$a$a$a$a$a$a$a$a$a$a$a$a$a$a$a && # 256
	a=$a$a$a$a$a$a$a$a$a$a$a$a$a$a$a$a && # 4096
	a=${a}q &&

	>path4 &&
	git update-index --add path4 &&
	(
		git ls-files -s path4 |
		sed -e "s/	.*/	/" |
		tr -d "\012"
		echo "$a"
	) | git update-index --index-info &&
	len=$(git ls-files "a*" | wc -c) &&
	test $len = 4098
'

test_done
