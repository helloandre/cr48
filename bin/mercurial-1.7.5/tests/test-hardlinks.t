  $ cat > nlinks.py <<EOF
  > import os, sys
  > for f in sorted(sys.stdin.readlines()):
  >     f = f[:-1]
  >     print os.lstat(f).st_nlink, f
  > EOF

  $ nlinksdir()
  > {
  >     find $1 -type f | python $TESTTMP/nlinks.py
  > }

Prepare repo r1:

  $ mkdir r1
  $ cd r1
  $ hg init

  $ echo c1 > f1
  $ hg add f1
  $ hg ci -m0

  $ mkdir d1
  $ cd d1
  $ echo c2 > f2
  $ hg add f2
  $ hg ci -m1
  $ cd ../..

  $ nlinksdir r1/.hg/store
  1 r1/.hg/store/00changelog.i
  1 r1/.hg/store/00manifest.i
  1 r1/.hg/store/data/d1/f2.i
  1 r1/.hg/store/data/f1.i
  1 r1/.hg/store/fncache
  1 r1/.hg/store/undo


Create hardlinked clone r2:

  $ hg clone -U --debug r1 r2
  linked 7 files

Create non-hardlinked clone r3:

  $ hg clone --pull r1 r3
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved


Repos r1 and r2 should now contain hardlinked files:

  $ nlinksdir r1/.hg/store
  2 r1/.hg/store/00changelog.i
  2 r1/.hg/store/00manifest.i
  2 r1/.hg/store/data/d1/f2.i
  2 r1/.hg/store/data/f1.i
  2 r1/.hg/store/fncache
  1 r1/.hg/store/undo

  $ nlinksdir r2/.hg/store
  2 r2/.hg/store/00changelog.i
  2 r2/.hg/store/00manifest.i
  2 r2/.hg/store/data/d1/f2.i
  2 r2/.hg/store/data/f1.i
  2 r2/.hg/store/fncache

Repo r3 should not be hardlinked:

  $ nlinksdir r3/.hg/store
  1 r3/.hg/store/00changelog.i
  1 r3/.hg/store/00manifest.i
  1 r3/.hg/store/data/d1/f2.i
  1 r3/.hg/store/data/f1.i
  1 r3/.hg/store/fncache
  1 r3/.hg/store/undo


Create a non-inlined filelog in r3:

  $ cd r3/d1
  $ python -c 'for x in range(10000): print x' >> data1
  $ for j in 0 1 2 3 4 5 6 7 8 9; do
  >   cat data1 >> f2
  >   hg commit -m$j
  > done
  $ cd ../..

  $ nlinksdir r3/.hg/store
  1 r3/.hg/store/00changelog.i
  1 r3/.hg/store/00manifest.i
  1 r3/.hg/store/data/d1/f2.d
  1 r3/.hg/store/data/d1/f2.i
  1 r3/.hg/store/data/f1.i
  1 r3/.hg/store/fncache
  1 r3/.hg/store/undo

Push to repo r1 should break up most hardlinks in r2:

  $ hg -R r2 verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  2 files, 2 changesets, 2 total revisions

  $ cd r3
  $ hg push
  pushing to $TESTTMP/r1
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 10 changesets with 10 changes to 1 files

  $ cd ..

  $ nlinksdir r2/.hg/store
  1 r2/.hg/store/00changelog.i
  1 r2/.hg/store/00manifest.i
  1 r2/.hg/store/data/d1/f2.i
  2 r2/.hg/store/data/f1.i
  1 r2/.hg/store/fncache

  $ hg -R r2 verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  2 files, 2 changesets, 2 total revisions


  $ cd r1
  $ hg up
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

Committing a change to f1 in r1 must break up hardlink f1.i in r2:

  $ echo c1c1 >> f1
  $ hg ci -m00
  $ cd ..

  $ nlinksdir r2/.hg/store
  1 r2/.hg/store/00changelog.i
  1 r2/.hg/store/00manifest.i
  1 r2/.hg/store/data/d1/f2.i
  1 r2/.hg/store/data/f1.i
  1 r2/.hg/store/fncache

