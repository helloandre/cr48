This test makes sure that we don't mark a file as merged with its ancestor
when we do a merge.

  $ cat <<EOF > merge
  > import sys, os
  > print "merging for", os.path.basename(sys.argv[1])
  > EOF
  $ HGMERGE="python ../merge"; export HGMERGE

Creating base:

  $ hg init a
  $ cd a
  $ echo 1 > foo
  $ echo 1 > bar
  $ echo 1 > baz
  $ echo 1 > quux
  $ hg add foo bar baz quux
  $ hg commit -m "base"

  $ cd ..
  $ hg clone a b
  updating to branch default
  4 files updated, 0 files merged, 0 files removed, 0 files unresolved

Creating branch a:

  $ cd a
  $ echo 2a > foo
  $ echo 2a > bar
  $ hg commit -m "branch a"

Creating branch b:

  $ cd ..
  $ cd b
  $ echo 2b > foo
  $ echo 2b > baz
  $ hg commit -m "branch b"

We shouldn't have anything but n state here:

  $ hg debugstate --nodates | grep -v "^n"
  [1]

Merging:

  $ hg pull ../a
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files (+1 heads)
  (run 'hg heads' to see heads, 'hg merge' to merge)

  $ hg merge -v
  merging for foo
  resolving manifests
  getting bar
  merging foo
  1 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ echo 2m > foo
  $ echo 2b > baz
  $ echo new > quux

We shouldn't have anything but foo in merge state here:

  $ hg debugstate --nodates | grep "^m"
  m 644          3 foo

  $ hg ci -m "merge"

main: we should have a merge here:

  $ hg debugindex .hg/store/00changelog.i
     rev    offset  length   base linkrev nodeid       p1           p2
       0         0      73      0       0 cdca01651b96 000000000000 000000000000
       1        73      68      1       1 f6718a9cb7f3 cdca01651b96 000000000000
       2       141      68      2       2 bdd988058d16 cdca01651b96 000000000000
       3       209      66      3       3 d8a521142a3c f6718a9cb7f3 bdd988058d16

log should show foo and quux changed:

  $ hg log -v -r tip
  changeset:   3:d8a521142a3c
  tag:         tip
  parent:      1:f6718a9cb7f3
  parent:      2:bdd988058d16
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  files:       foo quux
  description:
  merge
  
  

foo: we should have a merge here:

  $ hg debugindex .hg/store/data/foo.i
     rev    offset  length   base linkrev nodeid       p1           p2
       0         0       3      0       0 b8e02f643373 000000000000 000000000000
       1         3       4      1       1 2ffeddde1b65 b8e02f643373 000000000000
       2         7       4      2       2 33d1fb69067a b8e02f643373 000000000000
       3        11       4      3       3 aa27919ee430 2ffeddde1b65 33d1fb69067a

bar: we should not have a merge here:

  $ hg debugindex .hg/store/data/bar.i
     rev    offset  length   base linkrev nodeid       p1           p2
       0         0       3      0       0 b8e02f643373 000000000000 000000000000
       1         3       4      1       2 33d1fb69067a b8e02f643373 000000000000

baz: we should not have a merge here:

  $ hg debugindex .hg/store/data/baz.i
     rev    offset  length   base linkrev nodeid       p1           p2
       0         0       3      0       0 b8e02f643373 000000000000 000000000000
       1         3       4      1       1 2ffeddde1b65 b8e02f643373 000000000000

quux: we should not have a merge here:

  $ hg debugindex .hg/store/data/quux.i
     rev    offset  length   base linkrev nodeid       p1           p2
       0         0       3      0       0 b8e02f643373 000000000000 000000000000
       1         3       5      1       3 6128c0f33108 b8e02f643373 000000000000

Manifest entries should match tips of all files:

  $ hg manifest --debug
  33d1fb69067a0139622a3fa3b7ba1cdb1367972e 644   bar
  2ffeddde1b65b4827f6746174a145474129fa2ce 644   baz
  aa27919ee4303cfd575e1fb932dd64d75aa08be4 644   foo
  6128c0f33108e8cfbb4e0824d13ae48b466d7280 644   quux

Everything should be clean now:

  $ hg status

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  4 files, 4 changesets, 10 total revisions

