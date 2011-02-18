#!/bin/sh

test_description='git checkout --patch'

. ./lib-patch-mode.sh

test_expect_success PERL 'setup' '
	mkdir dir &&
	echo parent > dir/foo &&
	echo dummy > bar &&
	git add bar dir/foo &&
	git commit -m initial &&
	test_tick &&
	test_commit second dir/foo head &&
	set_and_save_state bar bar_work bar_index &&
	save_head
'

# note: bar sorts before dir/foo, so the first 'n' is always to skip 'bar'

test_expect_success PERL 'saying "n" does nothing' '
	set_and_save_state dir/foo work head &&
	(echo n; echo n) | git checkout -p &&
	verify_saved_state bar &&
	verify_saved_state dir/foo
'

test_expect_success PERL 'git checkout -p' '
	(echo n; echo y) | git checkout -p &&
	verify_saved_state bar &&
	verify_state dir/foo head head
'

test_expect_success PERL 'git checkout -p with staged changes' '
	set_state dir/foo work index &&
	(echo n; echo y) | git checkout -p &&
	verify_saved_state bar &&
	verify_state dir/foo index index
'

test_expect_success PERL 'git checkout -p HEAD with NO staged changes: abort' '
	set_and_save_state dir/foo work head &&
	(echo n; echo y; echo n) | git checkout -p HEAD &&
	verify_saved_state bar &&
	verify_saved_state dir/foo
'

test_expect_success PERL 'git checkout -p HEAD with NO staged changes: apply' '
	(echo n; echo y; echo y) | git checkout -p HEAD &&
	verify_saved_state bar &&
	verify_state dir/foo head head
'

test_expect_success PERL 'git checkout -p HEAD with change already staged' '
	set_state dir/foo index index &&
	# the third n is to get out in case it mistakenly does not apply
	(echo n; echo y; echo n) | git checkout -p HEAD &&
	verify_saved_state bar &&
	verify_state dir/foo head head
'

test_expect_success PERL 'git checkout -p HEAD^' '
	# the third n is to get out in case it mistakenly does not apply
	(echo n; echo y; echo n) | git checkout -p HEAD^ &&
	verify_saved_state bar &&
	verify_state dir/foo parent parent
'

test_expect_success PERL 'git checkout -p handles deletion' '
	set_state dir/foo work index &&
	rm dir/foo &&
	(echo n; echo y) | git checkout -p &&
	verify_saved_state bar &&
	verify_state dir/foo index index
'

# The idea in the rest is that bar sorts first, so we always say 'y'
# first and if the path limiter fails it'll apply to bar instead of
# dir/foo.  There's always an extra 'n' to reject edits to dir/foo in
# the failure case (and thus get out of the loop).

test_expect_success PERL 'path limiting works: dir' '
	set_state dir/foo work head &&
	(echo y; echo n) | git checkout -p dir &&
	verify_saved_state bar &&
	verify_state dir/foo head head
'

test_expect_success PERL 'path limiting works: -- dir' '
	set_state dir/foo work head &&
	(echo y; echo n) | git checkout -p -- dir &&
	verify_saved_state bar &&
	verify_state dir/foo head head
'

test_expect_success PERL 'path limiting works: HEAD^ -- dir' '
	# the third n is to get out in case it mistakenly does not apply
	(echo y; echo n; echo n) | git checkout -p HEAD^ -- dir &&
	verify_saved_state bar &&
	verify_state dir/foo parent parent
'

test_expect_success PERL 'path limiting works: foo inside dir' '
	set_state dir/foo work head &&
	# the third n is to get out in case it mistakenly does not apply
	(echo y; echo n; echo n) | (cd dir && git checkout -p foo) &&
	verify_saved_state bar &&
	verify_state dir/foo head head
'

test_expect_success PERL 'none of this moved HEAD' '
	verify_saved_head
'

test_done
