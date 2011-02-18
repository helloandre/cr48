  $ hg init

  $ echo "[merge]" >> .hg/hgrc
  $ echo "followcopies = 1" >> .hg/hgrc

  $ echo foo > a
  $ echo foo > a2
  $ hg add a a2
  $ hg ci -m "start"

  $ hg mv a b
  $ hg mv a2 b2
  $ hg ci -m "rename"

  $ hg co 0
  2 files updated, 0 files merged, 2 files removed, 0 files unresolved

  $ echo blahblah > a
  $ echo blahblah > a2
  $ hg mv a2 c2
  $ hg ci -m "modify"
  created new head

  $ hg merge -y --debug
    searching for copies back to rev 1
    unmatched files in local:
     c2
    unmatched files in other:
     b
     b2
    all copies found (* = to merge, ! = divergent):
     c2 -> a2 !
     b -> a *
     b2 -> a2 !
    checking for directory renames
   a2: divergent renames -> dr
  resolving manifests
   overwrite None partial False
   ancestor af1939970a1c local 044f8520aeeb+ remote 85c198ef2f6c
   a: remote moved to b -> m
   b2: remote created -> g
  preserving a for resolve of b
  removing a
  updating: a 1/3 files (33.33%)
  picked tool 'internal:merge' for b (binary False symlink False)
  merging a and b to b
  my b@044f8520aeeb+ other b@85c198ef2f6c ancestor a@af1939970a1c
   premerge successful
  updating: a2 2/3 files (66.67%)
  note: possible conflict - a2 was renamed multiple times to:
   c2
   b2
  updating: b2 3/3 files (100.00%)
  getting b2
  1 files updated, 1 files merged, 0 files removed, 0 files unresolved
  (branch merge, don't forget to commit)

  $ hg status -AC
  M b
    a
  M b2
  R a
  C c2

  $ cat b
  blahblah

  $ hg ci -m "merge"

  $ hg debugindex .hg/store/data/b.i
     rev    offset  length   base linkrev nodeid       p1           p2
       0         0      67      0       1 57eacc201a7f 000000000000 000000000000
       1        67      72      1       3 4727ba907962 000000000000 57eacc201a7f

  $ hg debugrename b
  b renamed from a:dd03b83622e78778b403775d0d074b9ac7387a66

This used to trigger a "divergent renames" warning, despite no renames

  $ hg cp b b3
  $ hg cp b b4
  $ hg ci -A -m 'copy b twice'
  $ hg up eb92d88a9712
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg up
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg rm b3 b4
  $ hg ci -m 'clean up a bit of our mess'

We'd rather not warn on divergent renames done in the same changeset (issue2113)

  $ hg cp b b3
  $ hg mv b b4
  $ hg ci -A -m 'divergent renames in same changeset'
  $ hg up c761c6948de0
  1 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ hg up
  note: possible conflict - b was renamed multiple times to:
   b3
   b4
  2 files updated, 0 files merged, 1 files removed, 0 files unresolved
