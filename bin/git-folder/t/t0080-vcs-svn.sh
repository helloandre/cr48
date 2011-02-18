#!/bin/sh

test_description='check infrastructure for svn importer'

. ./test-lib.sh
uint32_max=4294967295

test_expect_success 'obj pool: store data' '
	cat <<-\EOF >expected &&
	0
	1
	EOF

	test-obj-pool <<-\EOF >actual &&
	alloc one 16
	set one 13
	test one 13
	reset one
	EOF
	test_cmp expected actual
'

test_expect_success 'obj pool: NULL is offset ~0' '
	echo "$uint32_max" >expected &&
	echo null one | test-obj-pool >actual &&
	test_cmp expected actual
'

test_expect_success 'obj pool: out-of-bounds access' '
	cat <<-EOF >expected &&
	0
	0
	$uint32_max
	$uint32_max
	16
	20
	$uint32_max
	EOF

	test-obj-pool <<-\EOF >actual &&
	alloc one 16
	alloc two 16
	offset one 20
	offset two 20
	alloc one 5
	offset one 20
	free one 1
	offset one 20
	reset one
	reset two
	EOF
	test_cmp expected actual
'

test_expect_success 'obj pool: high-water mark' '
	cat <<-\EOF >expected &&
	0
	0
	10
	20
	20
	20
	EOF

	test-obj-pool <<-\EOF >actual &&
	alloc one 10
	committed one
	alloc one 10
	commit one
	committed one
	alloc one 10
	free one 20
	committed one
	reset one
	EOF
	test_cmp expected actual
'

test_expect_success 'line buffer' '
	echo HELLO >expected1 &&
	printf "%s\n" "" HELLO >expected2 &&
	echo >expected3 &&
	printf "%s\n" "" Q | q_to_nul >expected4 &&
	printf "%s\n" foo "" >expected5 &&
	printf "%s\n" "" foo >expected6 &&

	test-line-buffer <<-\EOF >actual1 &&
	5
	HELLO
	EOF

	test-line-buffer <<-\EOF >actual2 &&
	0

	5
	HELLO
	EOF

	q_to_nul <<-\EOF |
	1
	Q
	EOF
	test-line-buffer >actual3 &&

	q_to_nul <<-\EOF |
	0

	1
	Q
	EOF
	test-line-buffer >actual4 &&

	test-line-buffer <<-\EOF >actual5 &&
	5
	foo
	EOF

	test-line-buffer <<-\EOF >actual6 &&
	0

	5
	foo
	EOF

	test_cmp expected1 actual1 &&
	test_cmp expected2 actual2 &&
	test_cmp expected3 actual3 &&
	test_cmp expected4 actual4 &&
	test_cmp expected5 actual5 &&
	test_cmp expected6 actual6
'

test_expect_success 'string pool' '
	echo a does not equal b >expected.differ &&
	echo a equals a >expected.match &&
	echo equals equals equals >expected.matchmore &&

	test-string-pool "a,--b" >actual.differ &&
	test-string-pool "a,a" >actual.match &&
	test-string-pool "equals-equals" >actual.matchmore &&
	test_must_fail test-string-pool a,a,a &&
	test_must_fail test-string-pool a &&

	test_cmp expected.differ actual.differ &&
	test_cmp expected.match actual.match &&
	test_cmp expected.matchmore actual.matchmore
'

test_expect_success 'treap sort' '
	cat <<-\EOF >unsorted &&
	68
	12
	13
	13
	68
	13
	13
	21
	10
	11
	12
	13
	13
	EOF
	sort unsorted >expected &&

	test-treap <unsorted >actual &&
	test_cmp expected actual
'

test_done
