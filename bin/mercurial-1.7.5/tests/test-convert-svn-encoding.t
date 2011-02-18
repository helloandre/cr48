
  $ "$TESTDIR/hghave" svn svn-bindings || exit 80

  $ cat > $HGRCPATH <<EOF
  > [extensions]
  > convert = 
  > graphlog =
  > EOF

  $ svnadmin create svn-repo
  $ svnadmin load -q svn-repo < "$TESTDIR/svn/encoding.svndump"

Convert while testing all possible outputs

  $ hg --debug convert svn-repo A-hg
  initializing destination A-hg repository
  reparent to file://*/svn-repo (glob)
  run hg sink pre-conversion action
  scanning source...
  found trunk at 'trunk'
  found tags at 'tags'
  found branches at 'branches'
  found branch branch\xc3\xa9 at 5 (esc)
  found branch branch\xc3\xa9e at 6 (esc)
  scanning: 1 revisions
  reparent to file://*/svn-repo/trunk (glob)
  fetching revision log for "/trunk" from 4 to 0
  parsing revision 4 (2 changes)
  parsing revision 3 (4 changes)
  parsing revision 2 (3 changes)
  parsing revision 1 (3 changes)
  no copyfrom path, don't know what to do.
  '/branches' is not under '/trunk', ignoring
  '/tags' is not under '/trunk', ignoring
  scanning: 2 revisions
  reparent to file://*/svn-repo/branches/branch%C3%A9 (glob)
  fetching revision log for "/branches/branch\xc3\xa9" from 5 to 0 (esc)
  parsing revision 5 (1 changes)
  reparent to file://*/svn-repo (glob)
  reparent to file://*/svn-repo/branches/branch%C3%A9 (glob)
  found parent of branch /branches/branch\xc3\xa9 at 4: /trunk (esc)
  scanning: 3 revisions
  reparent to file://*/svn-repo/branches/branch%C3%A9e (glob)
  fetching revision log for "/branches/branch\xc3\xa9e" from 6 to 0 (esc)
  parsing revision 6 (1 changes)
  reparent to file://*/svn-repo (glob)
  reparent to file://*/svn-repo/branches/branch%C3%A9e (glob)
  found parent of branch /branches/branch\xc3\xa9e at 5: /branches/branch\xc3\xa9 (esc)
  scanning: 4 revisions
  scanning: 5 revisions
  scanning: 6 revisions
  sorting...
  converting...
  5 init projA
  source: svn:afeb9c47-92ff-4c0c-9f72-e1f6eb8ac9af/trunk@1
  converting: 0/6 revisions (0.00%)
  4 hello
  source: svn:afeb9c47-92ff-4c0c-9f72-e1f6eb8ac9af/trunk@2
  converting: 1/6 revisions (16.67%)
  reparent to file://*/svn-repo/trunk (glob)
  scanning paths: /trunk/\xc3\xa0 0/3 (0.00%) (esc)
  scanning paths: /trunk/\xc3\xa0/e\xcc\x81 1/3 (33.33%) (esc)
  scanning paths: /trunk/\xc3\xa9 2/3 (66.67%) (esc)
  \xc3\xa0/e\xcc\x81 (esc)
  getting files: \xc3\xa0/e\xcc\x81 1/2 (50.00%) (esc)
  \xc3\xa9 (esc)
  getting files: \xc3\xa9 2/2 (100.00%) (esc)
  3 copy files
  source: svn:afeb9c47-92ff-4c0c-9f72-e1f6eb8ac9af/trunk@3
  converting: 2/6 revisions (33.33%)
  scanning paths: /trunk/\xc3\xa0 0/4 (0.00%) (esc)
  gone from -1
  reparent to file://*/svn-repo (glob)
  reparent to file://*/svn-repo/trunk (glob)
  scanning paths: /trunk/\xc3\xa8 1/4 (25.00%) (esc)
  copied to \xc3\xa8 from \xc3\xa9@2 (esc)
  scanning paths: /trunk/\xc3\xa9 2/4 (50.00%) (esc)
  gone from -1
  reparent to file://*/svn-repo (glob)
  reparent to file://*/svn-repo/trunk (glob)
  scanning paths: /trunk/\xc3\xb9 3/4 (75.00%) (esc)
  mark /trunk/\xc3\xb9 came from \xc3\xa0:2 (esc)
  \xc3\xa0/e\xcc\x81 (esc)
  getting files: \xc3\xa0/e\xcc\x81 1/4 (25.00%) (esc)
  \xc3\xa8 (esc)
  getting files: \xc3\xa8 2/4 (50.00%) (esc)
   \xc3\xa8: copy \xc3\xa9:6b67ccefd5ce6de77e7ead4f5292843a0255329f (esc)
  \xc3\xa9 (esc)
  getting files: \xc3\xa9 3/4 (75.00%) (esc)
  \xc3\xb9/e\xcc\x81 (esc)
  getting files: \xc3\xb9/e\xcc\x81 4/4 (100.00%) (esc)
   \xc3\xb9/e\xcc\x81: copy \xc3\xa0/e\xcc\x81:a9092a3d84a37b9993b5c73576f6de29b7ea50f6 (esc)
  2 remove files
  source: svn:afeb9c47-92ff-4c0c-9f72-e1f6eb8ac9af/trunk@4
  converting: 3/6 revisions (50.00%)
  scanning paths: /trunk/\xc3\xa8 0/2 (0.00%) (esc)
  gone from -1
  reparent to file://*/svn-repo (glob)
  reparent to file://*/svn-repo/trunk (glob)
  scanning paths: /trunk/\xc3\xb9 1/2 (50.00%) (esc)
  gone from -1
  reparent to file://*/svn-repo (glob)
  reparent to file://*/svn-repo/trunk (glob)
  \xc3\xa8 (esc)
  getting files: \xc3\xa8 1/2 (50.00%) (esc)
  \xc3\xb9/e\xcc\x81 (esc)
  getting files: \xc3\xb9/e\xcc\x81 2/2 (100.00%) (esc)
  1 branch to branch?
  source: svn:afeb9c47-92ff-4c0c-9f72-e1f6eb8ac9af/branches/branch?@5
  converting: 4/6 revisions (66.67%)
  reparent to file://*/svn-repo/branches/branch%C3%A9 (glob)
  scanning paths: /branches/branch\xc3\xa9 0/1 (0.00%) (esc)
  0 branch to branch?e
  source: svn:afeb9c47-92ff-4c0c-9f72-e1f6eb8ac9af/branches/branch?e@6
  converting: 5/6 revisions (83.33%)
  reparent to file://*/svn-repo/branches/branch%C3%A9e (glob)
  scanning paths: /branches/branch\xc3\xa9e 0/1 (0.00%) (esc)
  reparent to file://*/svn-repo (glob)
  reparent to file://*/svn-repo/branches/branch%C3%A9e (glob)
  reparent to file://*/svn-repo (glob)
  reparent to file://*/svn-repo/branches/branch%C3%A9e (glob)
  updating tags
  .hgtags
  run hg sink post-conversion action
  $ cd A-hg
  $ hg up
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

Check tags are in UTF-8

  $ cat .hgtags
  221c3fdaf24df5f14c0a64c597581e2eacfb47bb branch\xc3\xa9e (esc)
  7a40952c2db29cf00d9e31df3749e98d8a4bdcbf branch\xc3\xa9 (esc)

  $ cd ..
