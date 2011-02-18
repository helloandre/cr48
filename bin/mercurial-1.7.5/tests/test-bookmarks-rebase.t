  $ echo "[extensions]" >> $HGRCPATH
  $ echo "rebase=" >> $HGRCPATH
  $ echo "bookmarks=" >> $HGRCPATH

initialize repository

  $ hg init

  $ echo 'a' > a
  $ hg ci -A -m "0"
  adding a

  $ echo 'b' > b
  $ hg ci -A -m "1"
  adding b

  $ hg up 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo 'c' > c
  $ hg ci -A -m "2"
  adding c
  created new head

  $ echo 'd' > d
  $ hg ci -A -m "3"
  adding d

  $ hg bookmark -r 1 one
  $ hg bookmark -r 3 two

bookmark list

  $ hg bookmark
   * two                       3:2ae46b1d99a7
     one                       1:925d80f479bb

rebase

  $ hg rebase -s two -d one
  saved backup bundle to $TESTTMP/.hg/strip-backup/*-backup.hg (glob)

  $ hg log
  changeset:   3:9163974d1cb5
  tag:         one
  tag:         tip
  tag:         two
  parent:      1:925d80f479bb
  parent:      2:db815d6d32e6
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     3
  
  changeset:   2:db815d6d32e6
  parent:      0:f7b1eb17ad24
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     2
  
  changeset:   1:925d80f479bb
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     1
  
  changeset:   0:f7b1eb17ad24
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     0
  
