#!/bin/sh

test_description='--reverse combines with --parents'

. ./test-lib.sh


commit () {
	test_tick &&
	echo $1 > foo &&
	git add foo &&
	git commit -m "$1"
}

test_expect_success 'set up --reverse example' '
	commit one &&
	git tag root &&
	commit two &&
	git checkout -b side HEAD^ &&
	commit three &&
	git checkout master &&
	git merge -s ours side &&
	commit five
	'

test_expect_success '--reverse --parents --full-history combines correctly' '
	git rev-list --parents --full-history master -- foo |
		perl -e "print reverse <>" > expected &&
	git rev-list --reverse --parents --full-history master -- foo \
		> actual &&
	test_cmp actual expected
	'

test_expect_success '--boundary does too' '
	git rev-list --boundary --parents --full-history master ^root -- foo |
		perl -e "print reverse <>" > expected &&
	git rev-list --boundary --reverse --parents --full-history \
		master ^root -- foo > actual &&
	test_cmp actual expected
	'

test_done
