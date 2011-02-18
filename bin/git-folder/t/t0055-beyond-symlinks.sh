#!/bin/sh

test_description='update-index and add refuse to add beyond symlinks'

. ./test-lib.sh

test_expect_success SYMLINKS setup '
	>a &&
	mkdir b &&
	ln -s b c &&
	>c/d &&
	git update-index --add a b/d
'

test_expect_success SYMLINKS 'update-index --add beyond symlinks' '
	test_must_fail git update-index --add c/d &&
	! ( git ls-files | grep c/d )
'

test_expect_success SYMLINKS 'add beyond symlinks' '
	test_must_fail git add c/d &&
	! ( git ls-files | grep c/d )
'

test_done
