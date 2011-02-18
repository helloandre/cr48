  $ hg init

  $ cat > a <<EOF
  > a
  > b
  > c
  > EOF
  $ hg ci -Am adda
  adding a

  $ cat > a <<EOF
  > d
  > e
  > f
  > EOF
  $ hg ci -m moda

  $ hg diff --reverse -r0 -r1
  diff -r 2855cdcfcbb7 -r 8e1805a3cf6e a
  --- a/a	Thu Jan 01 00:00:00 1970 +0000
  +++ b/a	Thu Jan 01 00:00:00 1970 +0000
  @@ -1,3 +1,3 @@
  -d
  -e
  -f
  +a
  +b
  +c

  $ cat >> a <<EOF
  > g
  > h
  > EOF
  $ hg diff --reverse --nodates
  diff -r 2855cdcfcbb7 a
  --- a/a
  +++ b/a
  @@ -1,5 +1,3 @@
   d
   e
   f
  -g
  -h

