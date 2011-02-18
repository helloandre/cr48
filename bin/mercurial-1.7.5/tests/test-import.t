  $ hg init a
  $ mkdir a/d1
  $ mkdir a/d1/d2
  $ echo line 1 > a/a
  $ echo line 1 > a/d1/d2/a
  $ hg --cwd a ci -Ama
  adding a
  adding d1/d2/a

  $ echo line 2 >> a/a
  $ hg --cwd a ci -u someone -d '1 0' -m'second change'


import exported patch

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a export tip > tip.patch
  $ hg --cwd b import ../tip.patch
  applying ../tip.patch

message should be same

  $ hg --cwd b tip | grep 'second change'
  summary:     second change

committer should be same

  $ hg --cwd b tip | grep someone
  user:        someone
  $ rm -r b


import exported patch with external patcher

  $ cat > dummypatch.py <<EOF
  > print 'patching file a'
  > file('a', 'wb').write('line2\n')
  > EOF
  $ chmod +x dummypatch.py
  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a export tip > tip.patch
  $ hg --config ui.patch='python ../dummypatch.py' --cwd b import ../tip.patch
  applying ../tip.patch
  $ cat b/a
  line2
  $ rm -r b


import of plain diff should fail without message

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a diff -r0:1 > tip.patch
  $ hg --cwd b import ../tip.patch
  applying ../tip.patch
  abort: empty commit message
  [255]
  $ rm -r b


import of plain diff should be ok with message

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a diff -r0:1 > tip.patch
  $ hg --cwd b import -mpatch ../tip.patch
  applying ../tip.patch
  $ rm -r b


import of plain diff with specific date and user

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a diff -r0:1 > tip.patch
  $ hg --cwd b import -mpatch -d '1 0' -u 'user@nowhere.net' ../tip.patch
  applying ../tip.patch
  $ hg -R b tip -pv
  changeset:   1:ca68f19f3a40
  tag:         tip
  user:        user@nowhere.net
  date:        Thu Jan 01 00:00:01 1970 +0000
  files:       a
  description:
  patch
  
  
  diff -r 80971e65b431 -r ca68f19f3a40 a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:01 1970 +0000
  @@ -1,1 +1,2 @@
   line 1
  +line 2
  
  $ rm -r b


import of plain diff should be ok with --no-commit

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a diff -r0:1 > tip.patch
  $ hg --cwd b import --no-commit ../tip.patch
  applying ../tip.patch
  $ hg --cwd b diff --nodates
  diff -r 80971e65b431 a
  --- a/a
  +++ b/a
  @@ -1,1 +1,2 @@
   line 1
  +line 2
  $ rm -r b


import of malformed plain diff should fail

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a diff -r0:1 > tip.patch
  $ sed 's/1,1/foo/' < tip.patch > broken.patch
  $ hg --cwd b import -mpatch ../broken.patch
  applying ../broken.patch
  abort: bad hunk #1
  [255]
  $ rm -r b


hg -R repo import
put the clone in a subdir - having a directory named "a"
used to hide a bug.

  $ mkdir dir
  $ hg clone -r0 a dir/b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a export tip > dir/tip.patch
  $ cd dir
  $ hg -R b import tip.patch
  applying tip.patch
  $ cd ..
  $ rm -r dir


import from stdin

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a export tip | hg --cwd b import -
  applying patch from stdin
  $ rm -r b


import two patches in one stream

  $ hg init b
  $ hg --cwd a export 0:tip | hg --cwd b import -
  applying patch from stdin
  applied 80971e65b431
  $ hg --cwd a id
  1d4bd90af0e4 tip
  $ hg --cwd b id
  1d4bd90af0e4 tip
  $ rm -r b


override commit message

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a export tip | hg --cwd b import -m 'override' -
  applying patch from stdin
  $ hg --cwd b tip | grep override
  summary:     override
  $ rm -r b

  $ cat > mkmsg.py <<EOF
  > import email.Message, sys
  > msg = email.Message.Message()
  > msg.set_payload('email commit message\n' + open('tip.patch', 'rb').read())
  > msg['Subject'] = 'email patch'
  > msg['From'] = 'email patcher'
  > sys.stdout.write(msg.as_string())
  > EOF


plain diff in email, subject, message body

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a diff -r0:1 > tip.patch
  $ python mkmsg.py > msg.patch
  $ hg --cwd b import ../msg.patch
  applying ../msg.patch
  $ hg --cwd b tip | grep email
  user:        email patcher
  summary:     email patch
  $ rm -r b


plain diff in email, no subject, message body

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ grep -v '^Subject:' msg.patch | hg --cwd b import -
  applying patch from stdin
  $ rm -r b


plain diff in email, subject, no message body

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ grep -v '^email ' msg.patch | hg --cwd b import -
  applying patch from stdin
  $ rm -r b


plain diff in email, no subject, no message body, should fail

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ egrep -v '^(Subject|email)' msg.patch | hg --cwd b import -
  applying patch from stdin
  abort: empty commit message
  [255]
  $ rm -r b


hg export in email, should use patch header

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a export tip > tip.patch
  $ python mkmsg.py | hg --cwd b import -
  applying patch from stdin
  $ hg --cwd b tip | grep second
  summary:     second change
  $ rm -r b


subject: duplicate detection, removal of [PATCH]
The '---' tests the gitsendmail handling without proper mail headers

  $ cat > mkmsg2.py <<EOF
  > import email.Message, sys
  > msg = email.Message.Message()
  > msg.set_payload('email patch\n\nnext line\n---\n' + open('tip.patch').read())
  > msg['Subject'] = '[PATCH] email patch'
  > msg['From'] = 'email patcher'
  > sys.stdout.write(msg.as_string())
  > EOF


plain diff in email, [PATCH] subject, message body with subject

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a diff -r0:1 > tip.patch
  $ python mkmsg2.py | hg --cwd b import -
  applying patch from stdin
  $ hg --cwd b tip --template '{desc}\n'
  email patch
  
  next line
  ---
  $ rm -r b


Issue963: Parent of working dir incorrect after import of multiple
patches and rollback

We weren't backing up the correct dirstate file when importing many
patches: import patch1 patch2; rollback

  $ echo line 3 >> a/a
  $ hg --cwd a ci -m'third change'
  $ hg --cwd a export -o '../patch%R' 1 2
  $ hg clone -qr0 a b
  $ hg --cwd b parents --template 'parent: {rev}\n'
  parent: 0
  $ hg --cwd b import ../patch1 ../patch2
  applying ../patch1
  applying ../patch2
  applied 1d4bd90af0e4
  $ hg --cwd b rollback
  rolling back to revision 1 (undo commit)
  $ hg --cwd b parents --template 'parent: {rev}\n'
  parent: 1
  $ rm -r b


importing a patch in a subdirectory failed at the commit stage

  $ echo line 2 >> a/d1/d2/a
  $ hg --cwd a ci -u someoneelse -d '1 0' -m'subdir change'

hg import in a subdirectory

  $ hg clone -r0 a b
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 2 changes to 2 files
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg --cwd a export tip > tmp
  $ sed -e 's/d1\/d2\///' < tmp > tip.patch
  $ dir=`pwd`
  $ cd b/d1/d2 2>&1 > /dev/null
  $ hg import  ../../../tip.patch
  applying ../../../tip.patch
  $ cd "$dir"

message should be 'subdir change'

  $ hg --cwd b tip | grep 'subdir change'
  summary:     subdir change

committer should be 'someoneelse'

  $ hg --cwd b tip | grep someoneelse
  user:        someoneelse

should be empty

  $ hg --cwd b status


Test fuzziness (ambiguous patch location, fuzz=2)

  $ hg init fuzzy
  $ cd fuzzy
  $ echo line1 > a
  $ echo line0 >> a
  $ echo line3 >> a
  $ hg ci -Am adda
  adding a
  $ echo line1 > a
  $ echo line2 >> a
  $ echo line0 >> a
  $ echo line3 >> a
  $ hg ci -m change a
  $ hg export tip > tip.patch
  $ hg up -C 0
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo line1 > a
  $ echo line0 >> a
  $ echo line1 >> a
  $ echo line0 >> a
  $ hg ci -m brancha
  created new head
  $ hg import --no-commit -v tip.patch
  applying tip.patch
  patching file a
  Hunk #1 succeeded at 1 with fuzz 2 (offset -2 lines).
  $ hg revert -a
  reverting a

test fuzziness with eol=auto

  $ hg --config patch.eol=auto import --no-commit -v tip.patch
  applying tip.patch
  patching file a
  Hunk #1 succeeded at 1 with fuzz 2 (offset -2 lines).
  $ cd ..


Test hunk touching empty files (issue906)

  $ hg init empty
  $ cd empty
  $ touch a
  $ touch b1
  $ touch c1
  $ echo d > d
  $ hg ci -Am init
  adding a
  adding b1
  adding c1
  adding d
  $ echo a > a
  $ echo b > b1
  $ hg mv b1 b2
  $ echo c > c1
  $ hg copy c1 c2
  $ rm d
  $ touch d
  $ hg diff --git
  diff --git a/a b/a
  --- a/a
  +++ b/a
  @@ -0,0 +1,1 @@
  +a
  diff --git a/b1 b/b2
  rename from b1
  rename to b2
  --- a/b1
  +++ b/b2
  @@ -0,0 +1,1 @@
  +b
  diff --git a/c1 b/c1
  --- a/c1
  +++ b/c1
  @@ -0,0 +1,1 @@
  +c
  diff --git a/c1 b/c2
  copy from c1
  copy to c2
  --- a/c1
  +++ b/c2
  @@ -0,0 +1,1 @@
  +c
  diff --git a/d b/d
  --- a/d
  +++ b/d
  @@ -1,1 +0,0 @@
  -d
  $ hg ci -m empty
  $ hg export --git tip > empty.diff
  $ hg up -C 0
  4 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg import empty.diff
  applying empty.diff
  $ for name in a b1 b2 c1 c2 d; do
  >   echo % $name file
  >   test -f $name && cat $name
  >   done
  % a file
  a
  % b1 file
  % b2 file
  b
  % c1 file
  c
  % c2 file
  c
  % d file
  $ cd ..


Test importing a patch ending with a binary file removal

  $ hg init binaryremoval
  $ cd binaryremoval
  $ echo a > a
  $ python -c "file('b', 'wb').write('a\x00b')"
  $ hg ci -Am addall
  adding a
  adding b
  $ hg rm a
  $ hg rm b
  $ hg st
  R a
  R b
  $ hg ci -m remove
  $ hg export --git . > remove.diff
  $ cat remove.diff | grep git
  diff --git a/a b/a
  diff --git a/b b/b
  $ hg up -C 0
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg import remove.diff
  applying remove.diff
  $ hg manifest
  $ cd ..


Issue927: test update+rename with common name

  $ hg init t
  $ cd t
  $ touch a
  $ hg ci -Am t
  adding a
  $ echo a > a

Here, bfile.startswith(afile)

  $ hg copy a a2
  $ hg ci -m copya
  $ hg export --git tip > copy.diff
  $ hg up -C 0
  1 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ hg import copy.diff
  applying copy.diff

a should contain an 'a'

  $ cat a
  a

and a2 should have duplicated it

  $ cat a2
  a
  $ cd ..


test -p0

  $ hg init p0
  $ cd p0
  $ echo a > a
  $ hg ci -Am t
  adding a
  $ hg import -p0 - << EOF
  > foobar
  > --- a	Sat Apr 12 22:43:58 2008 -0400
  > +++ a	Sat Apr 12 22:44:05 2008 -0400
  > @@ -1,1 +1,1 @@
  > -a
  > +bb
  > EOF
  applying patch from stdin
  $ hg status
  $ cat a
  bb
  $ cd ..


test paths outside repo root

  $ mkdir outside
  $ touch outside/foo
  $ hg init inside
  $ cd inside
  $ hg import - <<EOF
  > diff --git a/a b/b
  > rename from ../outside/foo
  > rename to bar
  > EOF
  applying patch from stdin
  abort: ../outside/foo not under root
  [255]
  $ cd ..


test import with similarity and git and strip (issue295 et al.)

  $ hg init sim
  $ cd sim
  $ echo 'this is a test' > a
  $ hg ci -Ama
  adding a
  $ cat > ../rename.diff <<EOF
  > diff --git a/foo/a b/foo/a
  > deleted file mode 100644
  > --- a/foo/a
  > +++ /dev/null
  > @@ -1,1 +0,0 @@
  > -this is a test
  > diff --git a/foo/b b/foo/b
  > new file mode 100644
  > --- /dev/null
  > +++ b/foo/b
  > @@ -0,0 +1,2 @@
  > +this is a test
  > +foo
  > EOF
  $ hg import --no-commit -v -s 1 ../rename.diff -p2
  applying ../rename.diff
  patching file a
  patching file b
  removing a
  adding b
  recording removal of a as rename to b (88% similar)
  $ hg st -C
  A b
    a
  R a
  $ hg revert -a
  undeleting a
  forgetting b
  $ rm b
  $ hg import --no-commit -v -s 100 ../rename.diff -p2
  applying ../rename.diff
  patching file a
  patching file b
  removing a
  adding b
  $ hg st -C
  A b
  R a
  $ cd ..


Issue1495: add empty file from the end of patch

  $ hg init addemptyend
  $ cd addemptyend
  $ touch a
  $ hg addremove
  adding a
  $ hg ci -m "commit"
  $ cat > a.patch <<EOF
  > diff --git a/a b/a
  > --- a/a
  > +++ b/a
  > @@ -0,0 +1,1 @@
  > +a
  > diff --git a/b b/b
  > new file mode 100644
  > EOF
  $ hg import --no-commit a.patch
  applying a.patch
  $ cd ..


create file when source is not /dev/null

  $ cat > create.patch <<EOF
  > diff -Naur proj-orig/foo proj-new/foo
  > --- proj-orig/foo       1969-12-31 16:00:00.000000000 -0800
  > +++ proj-new/foo        2009-07-17 16:50:45.801368000 -0700
  > @@ -0,0 +1,1 @@
  > +a
  > EOF

some people have patches like the following too

  $ cat > create2.patch <<EOF
  > diff -Naur proj-orig/foo proj-new/foo
  > --- proj-orig/foo.orig  1969-12-31 16:00:00.000000000 -0800
  > +++ proj-new/foo        2009-07-17 16:50:45.801368000 -0700
  > @@ -0,0 +1,1 @@
  > +a
  > EOF
  $ hg init oddcreate
  $ cd oddcreate
  $ hg import --no-commit ../create.patch
  applying ../create.patch
  $ cat foo
  a
  $ rm foo
  $ hg revert foo
  $ hg import --no-commit ../create2.patch
  applying ../create2.patch
  $ cat foo
  a


Issue1859: first line mistaken for email headers

  $ hg init emailconfusion
  $ cd emailconfusion
  $ cat > a.patch <<EOF
  > module: summary
  > 
  > description
  > 
  > 
  > diff -r 000000000000 -r 9b4c1e343b55 test.txt
  > --- /dev/null
  > +++ b/a
  > @@ -0,0 +1,1 @@
  > +a
  > EOF
  $ hg import -d '0 0' a.patch
  applying a.patch
  $ hg parents -v
  changeset:   0:5a681217c0ad
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  files:       a
  description:
  module: summary
  
  description
  
  
  $ cd ..


--- in commit message

  $ hg init commitconfusion
  $ cd commitconfusion
  $ cat > a.patch <<EOF
  > module: summary
  > 
  > --- description
  > 
  > diff --git a/a b/a
  > new file mode 100644
  > --- /dev/null
  > +++ b/a
  > @@ -0,0 +1,1 @@
  > +a
  > EOF
  > hg import -d '0 0' a.patch
  > hg parents -v
  > cd ..
  > 
  > echo '% tricky header splitting'
  > cat > trickyheaders.patch <<EOF
  > From: User A <user@a>
  > Subject: [PATCH] from: tricky!
  > 
  > # HG changeset patch
  > # User User B
  > # Date 1266264441 18000
  > # Branch stable
  > # Node ID f2be6a1170ac83bf31cb4ae0bad00d7678115bc0
  > # Parent  0000000000000000000000000000000000000000
  > from: tricky!
  > 
  > That is not a header.
  > 
  > diff -r 000000000000 -r f2be6a1170ac foo
  > --- /dev/null
  > +++ b/foo
  > @@ -0,0 +1,1 @@
  > +foo
  > EOF
  applying a.patch
  changeset:   0:f34d9187897d
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  files:       a
  description:
  module: summary
  
  
  % tricky header splitting

  $ hg init trickyheaders
  $ cd trickyheaders
  $ hg import -d '0 0' ../trickyheaders.patch
  applying ../trickyheaders.patch
  $ hg export --git tip
  # HG changeset patch
  # User User B
  # Date 0 0
  # Node ID eb56ab91903632294ac504838508cb370c0901d2
  # Parent  0000000000000000000000000000000000000000
  from: tricky!
  
  That is not a header.
  
  diff --git a/foo b/foo
  new file mode 100644
  --- /dev/null
  +++ b/foo
  @@ -0,0 +1,1 @@
  +foo
  $ cd ..


Issue2102: hg export and hg import speak different languages

  $ hg init issue2102
  $ cd issue2102
  $ mkdir -p src/cmd/gc
  $ touch src/cmd/gc/mksys.bash
  $ hg ci -Am init
  adding src/cmd/gc/mksys.bash
  $ hg import - <<EOF
  > # HG changeset patch
  > # User Rob Pike
  > # Date 1216685449 25200
  > # Node ID 03aa2b206f499ad6eb50e6e207b9e710d6409c98
  > # Parent  93d10138ad8df586827ca90b4ddb5033e21a3a84
  > help management of empty pkg and lib directories in perforce
  > 
  > R=gri
  > DELTA=4  (4 added, 0 deleted, 0 changed)
  > OCL=13328
  > CL=13328
  > 
  > diff --git a/lib/place-holder b/lib/place-holder
  > new file mode 100644
  > --- /dev/null
  > +++ b/lib/place-holder
  > @@ -0,0 +1,2 @@
  > +perforce does not maintain empty directories.
  > +this file helps.
  > diff --git a/pkg/place-holder b/pkg/place-holder
  > new file mode 100644
  > --- /dev/null
  > +++ b/pkg/place-holder
  > @@ -0,0 +1,2 @@
  > +perforce does not maintain empty directories.
  > +this file helps.
  > diff --git a/src/cmd/gc/mksys.bash b/src/cmd/gc/mksys.bash
  > old mode 100644
  > new mode 100755
  > EOF
  applying patch from stdin
  $ hg sum
  parent: 1:d59915696727 tip
   help management of empty pkg and lib directories in perforce
  branch: default
  commit: (clean)
  update: (current)
  $ hg diff --git -c tip
  diff --git a/lib/place-holder b/lib/place-holder
  new file mode 100644
  --- /dev/null
  +++ b/lib/place-holder
  @@ -0,0 +1,2 @@
  +perforce does not maintain empty directories.
  +this file helps.
  diff --git a/pkg/place-holder b/pkg/place-holder
  new file mode 100644
  --- /dev/null
  +++ b/pkg/place-holder
  @@ -0,0 +1,2 @@
  +perforce does not maintain empty directories.
  +this file helps.
  diff --git a/src/cmd/gc/mksys.bash b/src/cmd/gc/mksys.bash
  old mode 100644
  new mode 100755
  $ cd ..


diff lines looking like headers

  $ hg init difflineslikeheaders
  $ cd difflineslikeheaders
  $ echo a >a
  $ echo b >b
  $ echo c >c
  $ hg ci -Am1
  adding a
  adding b
  adding c

  $ echo "key: value" >>a
  $ echo "key: value" >>b
  $ echo "foo" >>c
  $ hg ci -m2

  $ hg up -C 0
  3 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg diff --git -c1 >want
  $ hg diff -c1 | hg import --no-commit -
  applying patch from stdin
  $ hg diff --git >have
  $ diff want have
  $ cd ..

