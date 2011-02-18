#!/bin/sh

test_description='branch --contains <commit>, --merged, and --no-merged'

. ./test-lib.sh

test_expect_success setup '

	>file &&
	git add file &&
	test_tick &&
	git commit -m initial &&
	git branch side &&

	echo 1 >file &&
	test_tick &&
	git commit -a -m "second on master" &&

	git checkout side &&
	echo 1 >file &&
	test_tick &&
	git commit -a -m "second on side" &&

	git merge master

'

test_expect_success 'branch --contains=master' '

	git branch --contains=master >actual &&
	{
		echo "  master" && echo "* side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --contains master' '

	git branch --contains master >actual &&
	{
		echo "  master" && echo "* side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --contains=side' '

	git branch --contains=side >actual &&
	{
		echo "* side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'side: branch --merged' '

	git branch --merged >actual &&
	{
		echo "  master" &&
		echo "* side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'side: branch --no-merged' '

	git branch --no-merged >actual &&
	>expect &&
	test_cmp expect actual

'

test_expect_success 'master: branch --merged' '

	git checkout master &&
	git branch --merged >actual &&
	{
		echo "* master"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'master: branch --no-merged' '

	git branch --no-merged >actual &&
	{
		echo "  side"
	} >expect &&
	test_cmp expect actual

'

test_done
