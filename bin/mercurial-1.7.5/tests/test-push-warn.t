  $ echo "[extensions]" >> $HGRCPATH
  $ echo "graphlog=" >> $HGRCPATH

  $ mkdir a
  $ cd a
  $ hg init
  $ echo foo > t1
  $ hg add t1
  $ hg commit -m "1"

  $ cd ..
  $ hg clone a b
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd a
  $ echo foo > t2
  $ hg add t2
  $ hg commit -m "2"

  $ cd ../b
  $ echo foo > t3
  $ hg add t3
  $ hg commit -m "3"

  $ hg push ../a
  pushing to ../a
  searching for changes
  abort: push creates new remote heads on branch 'default'!
  (you should pull and merge or use push -f to force)
  [255]

  $ hg pull ../a
  pulling from ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)
  (run 'hg heads' to see heads, 'hg merge' to merge)

  $ hg push ../a
  pushing to ../a
  searching for changes
  abort: push creates new remote heads on branch 'default'!
  (did you forget to merge? use push -f to force)
  [255]

  $ hg merge
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg commit -m "4"
  $ hg push ../a
  pushing to ../a
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 1 changes to 1 files

  $ cd ..

  $ hg init c
  $ cd c
  $ for i in 0 1 2; do
  >     echo $i >> foo
  >     hg ci -Am $i
  > done
  adding foo
  $ cd ..

  $ hg clone c d
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ cd d
  $ for i in 0 1; do
  >    hg co -C $i
  >    echo d-$i >> foo
  >    hg ci -m d-$i
  > done
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  created new head
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  created new head

  $ HGMERGE=true hg merge 3
  merging foo
  0 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg ci -m c-d

  $ hg push ../c
  pushing to ../c
  searching for changes
  abort: push creates new remote heads on branch 'default'!
  (did you forget to merge? use push -f to force)
  [255]

  $ hg push -r 2 ../c
  pushing to ../c
  searching for changes
  no changes found

  $ hg push -r 3 ../c
  pushing to ../c
  searching for changes
  abort: push creates new remote heads on branch 'default'!
  (did you forget to merge? use push -f to force)
  [255]

  $ hg push -r 3 -r 4 ../c
  pushing to ../c
  searching for changes
  abort: push creates new remote heads on branch 'default'!
  (did you forget to merge? use push -f to force)
  [255]

  $ hg push -f -r 3 -r 4 ../c
  pushing to ../c
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 1 files (+2 heads)

  $ hg push -r 5 ../c
  pushing to ../c
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (-1 heads)

  $ hg in ../c
  comparing with ../c
  searching for changes
  no changes found
  [1]


Issue450: push -r warns about remote head creation even if no heads
will be created

  $ hg init ../e
  $ hg push -r 0 ../e
  pushing to ../e
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files

  $ hg push -r 1 ../e
  pushing to ../e
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files

  $ cd ..


Issue736: named branches are not considered for detection of
unmerged heads in "hg push"

  $ hg init f
  $ cd f
  $ hg -q branch a
  $ echo 0 > foo
  $ hg -q ci -Am 0
  $ echo 1 > foo
  $ hg -q ci -m 1
  $ hg -q up 0
  $ echo 2 > foo
  $ hg -q ci -m 2
  $ hg -q up 0
  $ hg -q branch b
  $ echo 3 > foo
  $ hg -q ci -m 3
  $ cd ..

  $ hg -q clone f g
  $ cd g

Push on existing branch and new branch:

  $ hg -q up 1
  $ echo 4 > foo
  $ hg -q ci -m 4
  $ hg -q up 0
  $ echo 5 > foo
  $ hg -q branch c
  $ hg -q ci -m 5

  $ hg push ../f
  pushing to ../f
  searching for changes
  abort: push creates new remote branches: c!
  (use 'hg push --new-branch' to create new remote branches)
  [255]

  $ hg push -r 4 -r 5 ../f
  pushing to ../f
  searching for changes
  abort: push creates new remote branches: c!
  (use 'hg push --new-branch' to create new remote branches)
  [255]


Multiple new branches:

  $ hg -q branch d
  $ echo 6 > foo
  $ hg -q ci -m 6

  $ hg push ../f
  pushing to ../f
  searching for changes
  abort: push creates new remote branches: c, d!
  (use 'hg push --new-branch' to create new remote branches)
  [255]

  $ hg push -r 4 -r 6 ../f
  pushing to ../f
  searching for changes
  abort: push creates new remote branches: c, d!
  (use 'hg push --new-branch' to create new remote branches)
  [255]

  $ cd ../g


Fail on multiple head push:

  $ hg -q up 1
  $ echo 7 > foo
  $ hg -q ci -m 7

  $ hg push -r 4 -r 7 ../f
  pushing to ../f
  searching for changes
  abort: push creates new remote heads on branch 'a'!
  (did you forget to merge? use push -f to force)
  [255]

Push replacement head on existing branches:

  $ hg -q up 3
  $ echo 8 > foo
  $ hg -q ci -m 8

  $ hg push -r 7 -r 8 ../f
  pushing to ../f
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 1 files


Merge of branch a to other branch b followed by unrelated push
on branch a:

  $ hg -q up 7
  $ HGMERGE=true hg -q merge 8
  $ hg -q ci -m 9
  $ hg -q up 8
  $ echo 10 > foo
  $ hg -q ci -m 10

  $ hg push -r 9 ../f
  pushing to ../f
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (-1 heads)

  $ hg push -r 10 ../f
  pushing to ../f
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)


Cheating the counting algorithm:

  $ hg -q up 9
  $ HGMERGE=true hg -q merge 2
  $ hg -q ci -m 11
  $ hg -q up 1
  $ echo 12 > foo
  $ hg -q ci -m 12

  $ hg push -r 11 -r 12 ../f
  pushing to ../f
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 1 files


Failed push of new named branch:

  $ echo 12 > foo
  $ hg -q ci -m 12a
  [1]
  $ hg -q up 11
  $ echo 13 > foo
  $ hg -q branch e
  $ hg -q ci -m 13d

  $ hg push -r 12 -r 13 ../f
  pushing to ../f
  searching for changes
  abort: push creates new remote branches: e!
  (use 'hg push --new-branch' to create new remote branches)
  [255]


Using --new-branch to push new named branch:

  $ hg push --new-branch -r 12 -r 13 ../f
  pushing to ../f
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files


Checking prepush logic does not allow silently pushing
multiple new heads:

  $ cd ..
  $ hg init h
  $ echo init > h/init
  $ hg -R h ci -Am init
  adding init
  $ echo a > h/a
  $ hg -R h ci -Am a
  adding a
  $ hg clone h i
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R h up 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo b > h/b
  $ hg -R h ci -Am b
  adding b
  created new head
  $ hg -R i up 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo c > i/c
  $ hg -R i ci -Am c
  adding c
  created new head

  $ hg -R i push h
  pushing to h
  searching for changes
  abort: push creates new remote heads on branch 'default'!
  (you should pull and merge or use push -f to force)
  [255]


Check prepush logic with merged branches:

  $ hg init j
  $ hg -R j branch a
  marked working directory as branch a
  $ echo init > j/foo
  $ hg -R j ci -Am init
  adding foo
  $ hg clone j k
  updating to branch a
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo a1 > j/foo
  $ hg -R j ci -m a1
  $ hg -R k branch b
  marked working directory as branch b
  $ echo b > k/foo
  $ hg -R k ci -m b
  $ hg -R k up 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ hg -R k merge b
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg -R k ci -m merge

  $ hg -R k push -r a j
  pushing to j
  searching for changes
  abort: push creates new remote branches: b!
  (use 'hg push --new-branch' to create new remote branches)
  [255]


Prepush -r should not allow you to sneak in new heads:

  $ hg init l
  $ cd l
  $ echo a >> foo
  $ hg -q add foo
  $ hg -q branch a
  $ hg -q ci -ma
  $ hg -q up null
  $ echo a >> foo
  $ hg -q add foo
  $ hg -q branch b
  $ hg -q ci -mb
  $ cd ..
  $ hg -q clone l m -u a
  $ cd m
  $ hg -q merge b
  $ hg -q ci -mmb
  $ hg -q up 0
  $ echo a >> foo
  $ hg -q ci -ma2
  $ hg -q up 2
  $ echo a >> foo
  $ hg -q branch -f b
  $ hg -q ci -mb2
  $ hg -q merge 3
  $ hg -q ci -mma

  $ hg push ../l -b b
  pushing to ../l
  searching for changes
  abort: push creates new remote heads on branch 'a'!
  (did you forget to merge? use push -f to force)
  [255]

  $ cd ..


Check prepush with new branch head on former topo non-head:

  $ hg init n
  $ cd n
  $ hg branch A
  marked working directory as branch A
  $ echo a >a
  $ hg ci -Ama
  adding a
  $ hg branch B
  marked working directory as branch B
  $ echo b >b
  $ hg ci -Amb
  adding b

b is now branch head of B, and a topological head
a is now branch head of A, but not a topological head

  $ hg clone . inner
  updating to branch B
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd inner
  $ hg up B
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo b1 >b1
  $ hg ci -Amb1
  adding b1

in the clone b1 is now the head of B

  $ cd ..
  $ hg up 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo a2 >a2
  $ hg ci -Ama2
  adding a2

a2 is now the new branch head of A, and a new topological head
it replaces a former inner branch head, so it should at most warn about
A, not B

glog of local:

  $ hg glog --template "{rev}: {branches} {desc}\n"
  @  2: A a2
  |
  | o  1: B b
  |/
  o  0: A a
  
glog of remote:

  $ hg glog -R inner --template "{rev}: {branches} {desc}\n"
  @  2: B b1
  |
  o  1: B b
  |
  o  0: A a
  
outgoing:

  $ hg out inner --template "{rev}: {branches} {desc}\n"
  comparing with inner
  searching for changes
  2: A a2

  $ hg push inner
  pushing to inner
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files (+1 heads)

  $ cd ..


Check prepush with new branch head on former topo head:

  $ hg init o
  $ cd o
  $ hg branch A
  marked working directory as branch A
  $ echo a >a
  $ hg ci -Ama
  adding a
  $ hg branch B
  marked working directory as branch B
  $ echo b >b
  $ hg ci -Amb
  adding b

b is now branch head of B, and a topological head

  $ hg up 0
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo a1 >a1
  $ hg ci -Ama1
  adding a1

a1 is now branch head of A, and a topological head

  $ hg clone . inner
  updating to branch A
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd inner
  $ hg up B
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo b1 >b1
  $ hg ci -Amb1
  adding b1

in the clone b1 is now the head of B

  $ cd ..
  $ echo a2 >a2
  $ hg ci -Ama2
  adding a2

a2 is now the new branch head of A, and a topological head
it replaces a former topological and branch head, so this should not warn

glog of local:

  $ hg glog --template "{rev}: {branches} {desc}\n"
  @  3: A a2
  |
  o  2: A a1
  |
  | o  1: B b
  |/
  o  0: A a
  
glog of remote:

  $ hg glog -R inner --template "{rev}: {branches} {desc}\n"
  @  3: B b1
  |
  | o  2: A a1
  | |
  o |  1: B b
  |/
  o  0: A a
  
outgoing:

  $ hg out inner --template "{rev}: {branches} {desc}\n"
  comparing with inner
  searching for changes
  3: A a2

  $ hg push inner
  pushing to inner
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files

  $ cd ..


Check prepush with new branch head and new child of former branch head
but child is on different branch:

  $ hg init p
  $ cd p
  $ hg branch A
  marked working directory as branch A
  $ echo a0 >a
  $ hg ci -Ama0
  adding a
  $ echo a1 >a
  $ hg ci -ma1
  $ hg up null
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg branch B
  marked working directory as branch B
  $ echo b0 >b
  $ hg ci -Amb0
  adding b
  $ echo b1 >b
  $ hg ci -mb1

  $ hg clone . inner
  updating to branch B
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ hg up A
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg branch -f B
  marked working directory as branch B
  $ echo a3 >a
  $ hg ci -ma3
  created new head
  $ hg up 3
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg branch -f A
  marked working directory as branch A
  $ echo b3 >b
  $ hg ci -mb3
  created new head

glog of local:

  $ hg glog --template "{rev}: {branches} {desc}\n"
  @  5: A b3
  |
  | o  4: B a3
  | |
  o |  3: B b1
  | |
  o |  2: B b0
   /
  o  1: A a1
  |
  o  0: A a0
  
glog of remote:

  $ hg glog -R inner --template "{rev}: {branches} {desc}\n"
  @  3: B b1
  |
  o  2: B b0
  
  o  1: A a1
  |
  o  0: A a0
  
outgoing:

  $ hg out inner --template "{rev}: {branches} {desc}\n"
  comparing with inner
  searching for changes
  4: B a3
  5: A b3

  $ hg push inner
  pushing to inner
  searching for changes
  abort: push creates new remote heads on branch 'A'!
  (did you forget to merge? use push -f to force)
  [255]

  $ hg push inner -r4 -r5
  pushing to inner
  searching for changes
  abort: push creates new remote heads on branch 'A'!
  (did you forget to merge? use push -f to force)
  [255]

  $ hg in inner
  comparing with inner
  searching for changes
  no changes found
  [1]
