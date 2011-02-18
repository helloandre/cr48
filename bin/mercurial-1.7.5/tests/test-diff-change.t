Testing diff --change

  $ hg init a
  $ cd a

  $ echo "first" > file.txt
  $ hg add file.txt
  $ hg commit -m 'first commit' # 0

  $ echo "second" > file.txt
  $ hg commit -m 'second commit' # 1

  $ echo "third" > file.txt
  $ hg commit -m 'third commit' # 2

  $ hg diff --nodates --change 1
  diff -r 4bb65dda5db4 -r e9b286083166 file.txt
  --- a/file.txt
  +++ b/file.txt
  @@ -1,1 +1,1 @@
  -first
  +second

  $ hg diff --change e9b286083166
  diff -r 4bb65dda5db4 -r e9b286083166 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,1 +1,1 @@
  -first
  +second


Testing diff --change when merge:

  $ for i in 1 2 3 4 5 6 7 8 9 10; do
  $    echo $i >> file.txt
  $ done
  $ hg commit -m "lots of text" # 3

  $ sed -e 's,^2$,x,' file.txt > file.txt.tmp
  $ mv file.txt.tmp file.txt
  $ hg commit -m "change 2 to x" # 4

  $ hg up -r 3
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ sed -e 's,^8$,y,' file.txt > file.txt.tmp
  $ mv file.txt.tmp file.txt
  $ hg commit -m "change 8 to y"
  created new head

  $ hg up -C -r 4
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg merge -r 5
  merging file.txt
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)
  $ hg commit -m "merge 8 to y" # 6

  $ hg diff --change 5
  diff -r ae119d680c82 -r 9085c5c02e52 file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -6,6 +6,6 @@
   5
   6
   7
  -8
  +y
   9
   10

must be similar to 'hg diff --change 5':

  $ hg diff -c 6
  diff -r 273b50f17c6d -r 979ca961fd2e file.txt
  --- a/file.txt	Thu Jan 01 00:00:00 1970 +0000
  +++ b/file.txt	Thu Jan 01 00:00:00 1970 +0000
  @@ -6,6 +6,6 @@
   5
   6
   7
  -8
  +y
   9
   10

