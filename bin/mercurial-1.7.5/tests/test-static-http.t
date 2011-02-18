
  $ cp "$TESTDIR"/printenv.py .
  $ hg clone http://localhost:$HGPORT/ copy
  abort: error: Connection refused
  [255]
  $ test -d copy
  [1]

This server doesn't do range requests so it's basically only good for
one pull

  $ cat > dumb.py <<EOF
  > import BaseHTTPServer, SimpleHTTPServer, os, signal
  > 
  > def run(server_class=BaseHTTPServer.HTTPServer,
  >         handler_class=SimpleHTTPServer.SimpleHTTPRequestHandler):
  >     server_address = ('localhost', int(os.environ['HGPORT']))
  >     httpd = server_class(server_address, handler_class)
  >     httpd.serve_forever()
  > 
  > signal.signal(signal.SIGTERM, lambda x: sys.exit(0))
  > run()
  > EOF
  $ python dumb.py 2>/dev/null &
  $ echo $! >> $DAEMON_PIDS
  $ mkdir remote
  $ cd remote
  $ hg init
  $ echo foo > bar
  $ hg add bar
  $ hg commit -m"test"
  $ hg tip
  changeset:   0:61c9426e69fe
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     test
  
  $ cd ..
  $ hg clone static-http://localhost:$HGPORT/remote local
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd local
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  1 files, 1 changesets, 1 total revisions
  $ cat bar
  foo
  $ cd ../remote
  $ echo baz > quux
  $ hg commit -A -mtest2
  adding quux

check for HTTP opener failures when cachefile does not exist

  $ rm .hg/*.cache
  $ cd ../local
  $ echo '[hooks]' >> .hg/hgrc
  $ echo 'changegroup = python ../printenv.py changegroup' >> .hg/hgrc
  $ hg pull
  changegroup hook: HG_NODE=822d6e31f08b9d6e3b898ce5e52efc0a4bf4905a HG_SOURCE=pull HG_URL=http://localhost:$HGPORT/remote 
  pulling from static-http://localhost:$HGPORT/remote
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  (run 'hg update' to get a working copy)

trying to push

  $ hg update
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo more foo >> bar
  $ hg commit -m"test"
  $ hg push
  pushing to static-http://localhost:$HGPORT/remote
  abort: cannot lock static-http repository
  [255]

trying clone -r

  $ cd ..
  $ hg clone -r donotexist static-http://localhost:$HGPORT/remote local0
  abort: unknown revision 'donotexist'!
  [255]
  $ hg clone -r 0 static-http://localhost:$HGPORT/remote local0
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

test with "/" URI (issue 747)

  $ hg init
  $ echo a > a
  $ hg add a
  $ hg ci -ma
  $ hg clone static-http://localhost:$HGPORT/ local2
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd local2
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  1 files, 1 changesets, 1 total revisions
  $ cat a
  a
  $ hg paths
  default = static-http://localhost:$HGPORT/

test with empty repo (issue965)

  $ cd ..
  $ hg init remotempty
  $ hg clone static-http://localhost:$HGPORT/remotempty local3
  no changes found
  updating to branch default
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd local3
  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  0 files, 0 changesets, 0 total revisions
  $ hg paths
  default = static-http://localhost:$HGPORT/remotempty

test with non-repo

  $ cd ..
  $ mkdir notarepo
  $ hg clone static-http://localhost:$HGPORT/notarepo local3
  abort: 'http://localhost:$HGPORT/notarepo' does not appear to be an hg repository!
  [255]
  $ kill $!
