#!/bin/sh
#
# Copyright (c) 2007 Eric Wong
#

test_description='git svn log tests'
. ./lib-git-svn.sh

test_expect_success 'setup repository and import' '
	mkdir import &&
	(
		cd import &&
		for i in trunk branches/a branches/b tags/0.1 tags/0.2 tags/0.3
		do
			mkdir -p $i &&
			echo hello >>$i/README ||
			exit 1
		done &&
		svn_cmd import -m test . "$svnrepo"
	) &&
	git svn init "$svnrepo" -T trunk -b branches -t tags &&
	git svn fetch &&
	git reset --hard trunk &&
	echo bye >> README &&
	git commit -a -m bye &&
	git svn dcommit &&
	git reset --hard a &&
	echo why >> FEEDME &&
	git update-index --add FEEDME &&
	git commit -m feedme &&
	git svn dcommit &&
	git reset --hard trunk &&
	echo aye >> README &&
	git commit -a -m aye &&
	git svn dcommit &&
	git reset --hard b &&
	echo spy >> README &&
	git commit -a -m spy &&
	echo try >> README &&
	git commit -a -m try &&
	git svn dcommit
	'

test_expect_success 'run log' "
	git reset --hard a &&
	git svn log -r2 trunk | grep ^r2 &&
	git svn log -r4 trunk | grep ^r4 &&
	git svn log -r3 | grep ^r3
	"

test_expect_success 'run log against a from trunk' "
	git reset --hard trunk &&
	git svn log -r3 a | grep ^r3
	"

printf 'r1 \nr2 \nr4 \n' > expected-range-r1-r2-r4

test_expect_success 'test ascending revision range' "
	git reset --hard trunk &&
	git svn log -r 1:4 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r1-r2-r4 -
	"

printf 'r4 \nr2 \nr1 \n' > expected-range-r4-r2-r1

test_expect_success 'test descending revision range' "
	git reset --hard trunk &&
	git svn log -r 4:1 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r4-r2-r1 -
	"

printf 'r1 \nr2 \n' > expected-range-r1-r2

test_expect_success 'test ascending revision range with unreachable revision' "
	git reset --hard trunk &&
	git svn log -r 1:3 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r1-r2 -
	"

printf 'r2 \nr1 \n' > expected-range-r2-r1

test_expect_success 'test descending revision range with unreachable revision' "
	git reset --hard trunk &&
	git svn log -r 3:1 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r2-r1 -
	"

printf 'r2 \n' > expected-range-r2

test_expect_success 'test ascending revision range with unreachable upper boundary revision and 1 commit' "
	git reset --hard trunk &&
	git svn log -r 2:3 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r2 -
	"

test_expect_success 'test descending revision range with unreachable upper boundary revision and 1 commit' "
	git reset --hard trunk &&
	git svn log -r 3:2 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r2 -
	"

printf 'r4 \n' > expected-range-r4

test_expect_success 'test ascending revision range with unreachable lower boundary revision and 1 commit' "
	git reset --hard trunk &&
	git svn log -r 3:4 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r4 -
	"

test_expect_success 'test descending revision range with unreachable lower boundary revision and 1 commit' "
	git reset --hard trunk &&
	git svn log -r 4:3 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r4 -
	"

printf -- '------------------------------------------------------------------------\n' > expected-separator

test_expect_success 'test ascending revision range with unreachable boundary revisions and no commits' "
	git reset --hard trunk &&
	git svn log -r 5:6 | test_cmp expected-separator -
	"

test_expect_success 'test descending revision range with unreachable boundary revisions and no commits' "
	git reset --hard trunk &&
	git svn log -r 6:5 | test_cmp expected-separator -
	"

test_expect_success 'test ascending revision range with unreachable boundary revisions and 1 commit' "
	git reset --hard trunk &&
	git svn log -r 3:5 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r4 -
	"

test_expect_success 'test descending revision range with unreachable boundary revisions and 1 commit' "
	git reset --hard trunk &&
	git svn log -r 5:3 | grep '^r[0-9]' | cut -d'|' -f1 | test_cmp expected-range-r4 -
	"

test_done
