#!/bin/sh
#
# Copyright (c) 2007 Frank Lichtenheld
#

test_description='git-cvsserver access

tests read access to a git repository with the
cvs CLI client via git-cvsserver server'

. ./test-lib.sh

if ! test_have_prereq PERL; then
	skip_all='skipping git cvsserver tests, perl not available'
	test_done
fi
cvs >/dev/null 2>&1
if test $? -ne 1
then
    skip_all='skipping git-cvsserver tests, cvs not found'
    test_done
fi
"$PERL_PATH" -e 'use DBI; use DBD::SQLite' >/dev/null 2>&1 || {
    skip_all='skipping git-cvsserver tests, Perl SQLite interface unavailable'
    test_done
}

unset GIT_DIR GIT_CONFIG
WORKDIR=$(pwd)
SERVERDIR=$(pwd)/gitcvs.git
git_config="$SERVERDIR/config"
CVSROOT=":fork:$SERVERDIR"
CVSWORK="$(pwd)/cvswork"
CVS_SERVER=git-cvsserver
export CVSROOT CVS_SERVER

rm -rf "$CVSWORK" "$SERVERDIR"
test_expect_success 'setup' '
  echo >empty &&
  git add empty &&
  git commit -q -m "First Commit" &&
  mkdir secondroot &&
  ( cd secondroot &&
  git init &&
  touch secondrootfile &&
  git add secondrootfile &&
  git commit -m "second root") &&
  git pull secondroot master &&
  git clone -q --bare "$WORKDIR/.git" "$SERVERDIR" >/dev/null 2>&1 &&
  GIT_DIR="$SERVERDIR" git config --bool gitcvs.enabled true &&
  GIT_DIR="$SERVERDIR" git config gitcvs.logfile "$SERVERDIR/gitcvs.log" &&
  GIT_DIR="$SERVERDIR" git config gitcvs.authdb "$SERVERDIR/auth.db" &&
  echo cvsuser:cvGVEarMLnhlA > "$SERVERDIR/auth.db"
'

# note that cvs doesn't accept absolute pathnames
# as argument to co -d
test_expect_success 'basic checkout' \
  'GIT_CONFIG="$git_config" cvs -Q co -d cvswork master &&
   test "$(echo $(grep -v ^D cvswork/CVS/Entries|cut -d/ -f2,3,5 | head -n 1))" = "empty/1.1/" &&
   test "$(echo $(grep -v ^D cvswork/CVS/Entries|cut -d/ -f2,3,5 | sed -ne \$p))" = "secondrootfile/1.1/"'

#------------------------
# PSERVER AUTHENTICATION
#------------------------

cat >request-anonymous  <<EOF
BEGIN AUTH REQUEST
$SERVERDIR
anonymous

END AUTH REQUEST
EOF

cat >request-git  <<EOF
BEGIN AUTH REQUEST
$SERVERDIR
git

END AUTH REQUEST
EOF

cat >login-anonymous <<EOF
BEGIN VERIFICATION REQUEST
$SERVERDIR
anonymous

END VERIFICATION REQUEST
EOF

cat >login-git <<EOF
BEGIN VERIFICATION REQUEST
$SERVERDIR
git

END VERIFICATION REQUEST
EOF

cat >login-git-ok <<EOF
BEGIN VERIFICATION REQUEST
$SERVERDIR
cvsuser
Ah<Z:yZZ30 e
END VERIFICATION REQUEST
EOF

test_expect_success 'pserver authentication' \
  'cat request-anonymous | git-cvsserver pserver >log 2>&1 &&
   sed -ne \$p log | grep "^I LOVE YOU\$"'

test_expect_success 'pserver authentication failure (non-anonymous user)' \
  'if cat request-git | git-cvsserver pserver >log 2>&1
   then
       false
   else
       true
   fi &&
   sed -ne \$p log | grep "^I HATE YOU\$"'

test_expect_success 'pserver authentication success (non-anonymous user with password)' \
  'cat login-git-ok | git-cvsserver pserver >log 2>&1 &&
   sed -ne \$p log | grep "^I LOVE YOU\$"'

test_expect_success 'pserver authentication (login)' \
  'cat login-anonymous | git-cvsserver pserver >log 2>&1 &&
   sed -ne \$p log | grep "^I LOVE YOU\$"'

test_expect_success 'pserver authentication failure (login/non-anonymous user)' \
  'if cat login-git | git-cvsserver pserver >log 2>&1
   then
       false
   else
       true
   fi &&
   sed -ne \$p log | grep "^I HATE YOU\$"'


# misuse pserver authentication for testing of req_Root

cat >request-relative  <<EOF
BEGIN AUTH REQUEST
gitcvs.git
anonymous

END AUTH REQUEST
EOF

cat >request-conflict  <<EOF
BEGIN AUTH REQUEST
$SERVERDIR
anonymous

END AUTH REQUEST
Root $WORKDIR
EOF

test_expect_success 'req_Root failure (relative pathname)' \
  'if cat request-relative | git-cvsserver pserver >log 2>&1
   then
       echo unexpected success
       false
   else
       true
   fi &&
   tail log | grep "^error 1 Root must be an absolute pathname$"'

test_expect_success 'req_Root failure (conflicting roots)' \
  'cat request-conflict | git-cvsserver pserver >log 2>&1 &&
   tail log | grep "^error 1 Conflicting roots specified$"'

test_expect_success 'req_Root (strict paths)' \
  'cat request-anonymous | git-cvsserver --strict-paths pserver "$SERVERDIR" >log 2>&1 &&
   sed -ne \$p log | grep "^I LOVE YOU\$"'

test_expect_success 'req_Root failure (strict-paths)' '
    ! cat request-anonymous |
    git-cvsserver --strict-paths pserver "$WORKDIR" >log 2>&1
'

test_expect_success 'req_Root (w/o strict-paths)' \
  'cat request-anonymous | git-cvsserver pserver "$WORKDIR/" >log 2>&1 &&
   sed -ne \$p log | grep "^I LOVE YOU\$"'

test_expect_success 'req_Root failure (w/o strict-paths)' '
    ! cat request-anonymous |
    git-cvsserver pserver "$WORKDIR/gitcvs" >log 2>&1
'

cat >request-base  <<EOF
BEGIN AUTH REQUEST
/gitcvs.git
anonymous

END AUTH REQUEST
Root /gitcvs.git
EOF

test_expect_success 'req_Root (base-path)' \
  'cat request-base | git-cvsserver --strict-paths --base-path "$WORKDIR/" pserver "$SERVERDIR" >log 2>&1 &&
   sed -ne \$p log | grep "^I LOVE YOU\$"'

test_expect_success 'req_Root failure (base-path)' '
    ! cat request-anonymous |
    git-cvsserver --strict-paths --base-path "$WORKDIR" pserver "$SERVERDIR" >log 2>&1
'

GIT_DIR="$SERVERDIR" git config --bool gitcvs.enabled false || exit 1

test_expect_success 'req_Root (export-all)' \
  'cat request-anonymous | git-cvsserver --export-all pserver "$WORKDIR" >log 2>&1 &&
   sed -ne \$p log | grep "^I LOVE YOU\$"'

test_expect_success 'req_Root failure (export-all w/o whitelist)' \
  '! (cat request-anonymous | git-cvsserver --export-all pserver >log 2>&1 || false)'

test_expect_success 'req_Root (everything together)' \
  'cat request-base | git-cvsserver --export-all --strict-paths --base-path "$WORKDIR/" pserver "$SERVERDIR" >log 2>&1 &&
   sed -ne \$p log | grep "^I LOVE YOU\$"'

GIT_DIR="$SERVERDIR" git config --bool gitcvs.enabled true || exit 1

#--------------
# CONFIG TESTS
#--------------

test_expect_success 'gitcvs.enabled = false' \
  'GIT_DIR="$SERVERDIR" git config --bool gitcvs.enabled false &&
   if GIT_CONFIG="$git_config" cvs -Q co -d cvswork2 master >cvs.log 2>&1
   then
     echo unexpected cvs success
     false
   else
     true
   fi &&
   grep "GITCVS emulation disabled" cvs.log &&
   test ! -d cvswork2'

rm -fr cvswork2
test_expect_success 'gitcvs.ext.enabled = true' \
  'GIT_DIR="$SERVERDIR" git config --bool gitcvs.ext.enabled true &&
   GIT_DIR="$SERVERDIR" git config --bool gitcvs.enabled false &&
   GIT_CONFIG="$git_config" cvs -Q co -d cvswork2 master >cvs.log 2>&1 &&
   test_cmp cvswork cvswork2'

rm -fr cvswork2
test_expect_success 'gitcvs.ext.enabled = false' \
  'GIT_DIR="$SERVERDIR" git config --bool gitcvs.ext.enabled false &&
   GIT_DIR="$SERVERDIR" git config --bool gitcvs.enabled true &&
   if GIT_CONFIG="$git_config" cvs -Q co -d cvswork2 master >cvs.log 2>&1
   then
     echo unexpected cvs success
     false
   else
     true
   fi &&
   grep "GITCVS emulation disabled" cvs.log &&
   test ! -d cvswork2'

rm -fr cvswork2
test_expect_success 'gitcvs.dbname' \
  'GIT_DIR="$SERVERDIR" git config --bool gitcvs.ext.enabled true &&
   GIT_DIR="$SERVERDIR" git config gitcvs.dbname %Ggitcvs.%a.%m.sqlite &&
   GIT_CONFIG="$git_config" cvs -Q co -d cvswork2 master >cvs.log 2>&1 &&
   test_cmp cvswork cvswork2 &&
   test -f "$SERVERDIR/gitcvs.ext.master.sqlite" &&
   cmp "$SERVERDIR/gitcvs.master.sqlite" "$SERVERDIR/gitcvs.ext.master.sqlite"'

rm -fr cvswork2
test_expect_success 'gitcvs.ext.dbname' \
  'GIT_DIR="$SERVERDIR" git config --bool gitcvs.ext.enabled true &&
   GIT_DIR="$SERVERDIR" git config gitcvs.ext.dbname %Ggitcvs1.%a.%m.sqlite &&
   GIT_DIR="$SERVERDIR" git config gitcvs.dbname %Ggitcvs2.%a.%m.sqlite &&
   GIT_CONFIG="$git_config" cvs -Q co -d cvswork2 master >cvs.log 2>&1 &&
   test_cmp cvswork cvswork2 &&
   test -f "$SERVERDIR/gitcvs1.ext.master.sqlite" &&
   test ! -f "$SERVERDIR/gitcvs2.ext.master.sqlite" &&
   cmp "$SERVERDIR/gitcvs.master.sqlite" "$SERVERDIR/gitcvs1.ext.master.sqlite"'


#------------
# CVS UPDATE
#------------

rm -fr "$SERVERDIR"
cd "$WORKDIR" &&
git clone -q --bare "$WORKDIR/.git" "$SERVERDIR" >/dev/null 2>&1 &&
GIT_DIR="$SERVERDIR" git config --bool gitcvs.enabled true &&
GIT_DIR="$SERVERDIR" git config gitcvs.logfile "$SERVERDIR/gitcvs.log" ||
exit 1

test_expect_success 'cvs update (create new file)' \
  'echo testfile1 >testfile1 &&
   git add testfile1 &&
   git commit -q -m "Add testfile1" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update &&
   test "$(echo $(grep testfile1 CVS/Entries|cut -d/ -f2,3,5))" = "testfile1/1.1/" &&
   test_cmp testfile1 ../testfile1'

cd "$WORKDIR"
test_expect_success 'cvs update (update existing file)' \
  'echo line 2 >>testfile1 &&
   git add testfile1 &&
   git commit -q -m "Append to testfile1" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update &&
   test "$(echo $(grep testfile1 CVS/Entries|cut -d/ -f2,3,5))" = "testfile1/1.2/" &&
   test_cmp testfile1 ../testfile1'

cd "$WORKDIR"
#TODO: cvsserver doesn't support update w/o -d
test_expect_failure "cvs update w/o -d doesn't create subdir (TODO)" '
   mkdir test &&
   echo >test/empty &&
   git add test &&
   git commit -q -m "Single Subdirectory" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update &&
   test ! -d test
'

cd "$WORKDIR"
test_expect_success 'cvs update (subdirectories)' \
  '(for dir in A A/B A/B/C A/D E; do
      mkdir $dir &&
      echo "test file in $dir" >"$dir/file_in_$(echo $dir|sed -e "s#/# #g")"  &&
      git add $dir;
   done) &&
   git commit -q -m "deep sub directory structure" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update -d &&
   (for dir in A A/B A/B/C A/D E; do
      filename="file_in_$(echo $dir|sed -e "s#/# #g")" &&
      if test "$(echo $(grep -v ^D $dir/CVS/Entries|cut -d/ -f2,3,5))" = "$filename/1.1/" &&
	test_cmp "$dir/$filename" "../$dir/$filename"; then
        :
      else
        echo >failure
      fi
    done) &&
   test ! -f failure'

cd "$WORKDIR"
test_expect_success 'cvs update (delete file)' \
  'git rm testfile1 &&
   git commit -q -m "Remove testfile1" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update &&
   test -z "$(grep testfile1 CVS/Entries)" &&
   test ! -f testfile1'

cd "$WORKDIR"
test_expect_success 'cvs update (re-add deleted file)' \
  'echo readded testfile >testfile1 &&
   git add testfile1 &&
   git commit -q -m "Re-Add testfile1" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update &&
   test "$(echo $(grep testfile1 CVS/Entries|cut -d/ -f2,3,5))" = "testfile1/1.4/" &&
   test_cmp testfile1 ../testfile1'

cd "$WORKDIR"
test_expect_success 'cvs update (merge)' \
  'echo Line 0 >expected &&
   for i in 1 2 3 4 5 6 7
   do
     echo Line $i >>merge
     echo Line $i >>expected
   done &&
   echo Line 8 >>expected &&
   git add merge &&
   git commit -q -m "Merge test (pre-merge)" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update &&
   test "$(echo $(grep merge CVS/Entries|cut -d/ -f2,3,5))" = "merge/1.1/" &&
   test_cmp merge ../merge &&
   ( echo Line 0; cat merge ) >merge.tmp &&
   mv merge.tmp merge &&
   cd "$WORKDIR" &&
   echo Line 8 >>merge &&
   git add merge &&
   git commit -q -m "Merge test (merge)" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   sleep 1 && touch merge &&
   GIT_CONFIG="$git_config" cvs -Q update &&
   test_cmp merge ../expected'

cd "$WORKDIR"

cat >expected.C <<EOF
<<<<<<< merge.mine
Line 0
=======
LINE 0
>>>>>>> merge.3
EOF

for i in 1 2 3 4 5 6 7 8
do
  echo Line $i >>expected.C
done

test_expect_success 'cvs update (conflict merge)' \
  '( echo LINE 0; cat merge ) >merge.tmp &&
   mv merge.tmp merge &&
   git add merge &&
   git commit -q -m "Merge test (conflict)" &&
   git push gitcvs.git >/dev/null &&
   cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update &&
   test_cmp merge ../expected.C'

cd "$WORKDIR"
test_expect_success 'cvs update (-C)' \
  'cd cvswork &&
   GIT_CONFIG="$git_config" cvs -Q update -C &&
   test_cmp merge ../merge'

cd "$WORKDIR"
test_expect_success 'cvs update (merge no-op)' \
   'echo Line 9 >>merge &&
    cp merge cvswork/merge &&
    git add merge &&
    git commit -q -m "Merge test (no-op)" &&
    git push gitcvs.git >/dev/null &&
    cd cvswork &&
    sleep 1 && touch merge &&
    GIT_CONFIG="$git_config" cvs -Q update &&
    test_cmp merge ../merge'

cd "$WORKDIR"
test_expect_success 'cvs update (-p)' '
    touch really-empty &&
    echo Line 1 > no-lf &&
    printf "Line 2" >> no-lf &&
    git add really-empty no-lf &&
    git commit -q -m "Update -p test" &&
    git push gitcvs.git >/dev/null &&
    cd cvswork &&
    GIT_CONFIG="$git_config" cvs update &&
    rm -f failures &&
    for i in merge no-lf empty really-empty; do
        GIT_CONFIG="$git_config" cvs update -p "$i" >$i.out
	test_cmp $i.out ../$i >>failures 2>&1
    done &&
    test -z "$(cat failures)"
'

cd "$WORKDIR"
test_expect_success 'cvs update (module list supports packed refs)' '
    GIT_DIR="$SERVERDIR" git pack-refs --all &&
    GIT_CONFIG="$git_config" cvs -n up -d 2> out &&
    grep "cvs update: New directory \`master'\''" < out
'

#------------
# CVS STATUS
#------------

cd "$WORKDIR"
test_expect_success 'cvs status' '
    mkdir status.dir &&
    echo Line > status.dir/status.file &&
    echo Line > status.file &&
    git add status.dir status.file &&
    git commit -q -m "Status test" &&
    git push gitcvs.git >/dev/null &&
    cd cvswork &&
    GIT_CONFIG="$git_config" cvs update &&
    GIT_CONFIG="$git_config" cvs status | grep "^File: status.file" >../out &&
    test $(wc -l <../out) = 2
'

cd "$WORKDIR"
test_expect_success 'cvs status (nonrecursive)' '
    cd cvswork &&
    GIT_CONFIG="$git_config" cvs status -l | grep "^File: status.file" >../out &&
    test $(wc -l <../out) = 1
'

cd "$WORKDIR"
test_expect_success 'cvs status (no subdirs in header)' '
    cd cvswork &&
    GIT_CONFIG="$git_config" cvs status | grep ^File: >../out &&
    ! grep / <../out
'

#------------
# CVS CHECKOUT
#------------

cd "$WORKDIR"
test_expect_success 'cvs co -c (shows module database)' '
    GIT_CONFIG="$git_config" cvs co -c > out &&
    grep "^master[	 ]\+master$" < out &&
    ! grep -v "^master[	 ]\+master$" < out
'

#------------
# CVS ANNOTATE
#------------

cd "$WORKDIR"
test_expect_success 'cvs annotate' '
    cd cvswork &&
    GIT_CONFIG="$git_config" cvs annotate merge >../out &&
    sed -e "s/ .*//" ../out >../actual &&
    for i in 3 1 1 1 1 1 1 1 2 4; do echo 1.$i; done >../expect &&
    test_cmp ../expect ../actual
'

test_done
