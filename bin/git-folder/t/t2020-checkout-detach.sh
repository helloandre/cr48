#!/bin/sh

test_description='checkout into detached HEAD state'
. ./test-lib.sh

check_detached () {
	test_must_fail git symbolic-ref -q HEAD >/dev/null
}

check_not_detached () {
	git symbolic-ref -q HEAD >/dev/null
}

ORPHAN_WARNING='you are leaving .* commit.*behind'
check_orphan_warning() {
	grep "$ORPHAN_WARNING" "$1"
}
check_no_orphan_warning() {
	! grep "$ORPHAN_WARNING" "$1"
}

reset () {
	git checkout master &&
	check_not_detached
}

test_expect_success 'setup' '
	test_commit one &&
	test_commit two &&
	test_commit three && git tag -d three &&
	test_commit four && git tag -d four &&
	git branch branch &&
	git tag tag
'

test_expect_success 'checkout branch does not detach' '
	reset &&
	git checkout branch &&
	check_not_detached
'

test_expect_success 'checkout tag detaches' '
	reset &&
	git checkout tag &&
	check_detached
'

test_expect_success 'checkout branch by full name detaches' '
	reset &&
	git checkout refs/heads/branch &&
	check_detached
'

test_expect_success 'checkout non-ref detaches' '
	reset &&
	git checkout branch^ &&
	check_detached
'

test_expect_success 'checkout ref^0 detaches' '
	reset &&
	git checkout branch^0 &&
	check_detached
'

test_expect_success 'checkout --detach detaches' '
	reset &&
	git checkout --detach branch &&
	check_detached
'

test_expect_success 'checkout --detach without branch name' '
	reset &&
	git checkout --detach &&
	check_detached
'

test_expect_success 'checkout --detach errors out for non-commit' '
	reset &&
	test_must_fail git checkout --detach one^{tree} &&
	check_not_detached
'

test_expect_success 'checkout --detach errors out for extra argument' '
	reset &&
	git checkout master &&
	test_must_fail git checkout --detach tag one.t &&
	check_not_detached
'

test_expect_success 'checkout --detached and -b are incompatible' '
	reset &&
	test_must_fail git checkout --detach -b newbranch tag &&
	check_not_detached
'

test_expect_success 'checkout --detach moves HEAD' '
	reset &&
	git checkout one &&
	git checkout --detach two &&
	git diff --exit-code HEAD &&
	git diff --exit-code two
'

test_expect_success 'checkout warns on orphan commits' '
	reset &&
	git checkout --detach two &&
	echo content >orphan &&
	git add orphan &&
	git commit -a -m orphan &&
	git checkout master 2>stderr &&
	check_orphan_warning stderr
'

test_expect_success 'checkout does not warn leaving ref tip' '
	reset &&
	git checkout --detach two &&
	git checkout master 2>stderr &&
	check_no_orphan_warning stderr
'

test_expect_success 'checkout does not warn leaving reachable commit' '
	reset &&
	git checkout --detach HEAD^ &&
	git checkout master 2>stderr &&
	check_no_orphan_warning stderr
'

cat >expect <<'EOF'
Your branch is behind 'master' by 1 commit, and can be fast-forwarded.
EOF
test_expect_success 'tracking count is accurate after orphan check' '
	reset &&
	git branch child master^ &&
	git config branch.child.remote . &&
	git config branch.child.merge refs/heads/master &&
	git checkout child^ &&
	git checkout child >stdout &&
	test_cmp expect stdout
'

test_done
