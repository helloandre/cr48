#!/bin/sh

test_description='git branch display tests'
. ./test-lib.sh

test_expect_success 'make commits' '
	echo content >file &&
	git add file &&
	git commit -m one &&
	echo content >>file &&
	git commit -a -m two
'

test_expect_success 'make branches' '
	git branch branch-one &&
	git branch branch-two HEAD^
'

test_expect_success 'make remote branches' '
	git update-ref refs/remotes/origin/branch-one branch-one &&
	git update-ref refs/remotes/origin/branch-two branch-two &&
	git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/branch-one
'

cat >expect <<'EOF'
  branch-one
  branch-two
* master
EOF
test_expect_success 'git branch shows local branches' '
	git branch >actual &&
	test_cmp expect actual
'

cat >expect <<'EOF'
  origin/HEAD -> origin/branch-one
  origin/branch-one
  origin/branch-two
EOF
test_expect_success 'git branch -r shows remote branches' '
	git branch -r >actual &&
	test_cmp expect actual
'

cat >expect <<'EOF'
  branch-one
  branch-two
* master
  remotes/origin/HEAD -> origin/branch-one
  remotes/origin/branch-one
  remotes/origin/branch-two
EOF
test_expect_success 'git branch -a shows local and remote branches' '
	git branch -a >actual &&
	test_cmp expect actual
'

cat >expect <<'EOF'
two
one
two
EOF
test_expect_success 'git branch -v shows branch summaries' '
	git branch -v >tmp &&
	awk "{print \$NF}" <tmp >actual &&
	test_cmp expect actual
'

cat >expect <<'EOF'
* (no branch)
  branch-one
  branch-two
  master
EOF
test_expect_success C_LOCALE_OUTPUT 'git branch shows detached HEAD properly' '
	git checkout HEAD^0 &&
	git branch >actual &&
	test_cmp expect actual
'

test_done
