#!/bin/sh

test_description='diff hunk header truncation'

. ./test-lib.sh

N='日本語'
N1='日'
N2='日本'
NS="$N$N$N$N$N$N$N$N$N$N$N$N$N"

test_expect_success setup '

	(
		echo "A $NS"
		for c in B C D E F G H I J K
		do
			echo "  $c"
		done
		echo "L  $NS"
		for c in M N O P Q R S T U V
		do
			echo "  $c"
		done
	) >file &&
	git add file &&

	sed -e "/^  [EP]/s/$/ modified/" <file >file+ &&
	mv file+ file

'

test_expect_success 'hunk header truncation with an overly long line' '

	git diff | sed -n -e "s/^.*@@//p" >actual &&
	(
		echo " A $N$N$N$N$N$N$N$N$N2"
		echo " L  $N$N$N$N$N$N$N$N$N1"
	) >expected &&
	test_cmp actual expected

'

test_done
