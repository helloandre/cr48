#!/bin/sh

test_description='reflog walk shows repeated commits again'
. ./test-lib.sh

test_expect_success 'setup commits' '
	test_tick &&
	echo content >file && git add file && git commit -m one &&
	git tag one &&
	echo content >>file && git add file && git commit -m two &&
	git tag two
'

test_expect_success 'setup reflog with alternating commits' '
	git checkout -b topic &&
	git reset one &&
	git reset two &&
	git reset one &&
	git reset two
'

test_expect_success 'reflog shows all entries' '
	cat >expect <<-\EOF
		topic@{0} two: updating HEAD
		topic@{1} one: updating HEAD
		topic@{2} two: updating HEAD
		topic@{3} one: updating HEAD
		topic@{4} branch: Created from HEAD
	EOF
	git log -g --format="%gd %gs" topic >actual &&
	test_cmp expect actual
'

test_done
