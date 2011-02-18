#!/bin/sh

test_description='git log'

. ./test-lib.sh

test_expect_success setup '

	echo one >one &&
	git add one &&
	test_tick &&
	git commit -m initial &&

	echo ichi >one &&
	git add one &&
	test_tick &&
	git commit -m second &&

	git mv one ichi &&
	test_tick &&
	git commit -m third &&

	cp ichi ein &&
	git add ein &&
	test_tick &&
	git commit -m fourth &&

	mkdir a &&
	echo ni >a/two &&
	git add a/two &&
	test_tick &&
	git commit -m fifth  &&

	git rm a/two &&
	test_tick &&
	git commit -m sixth

'

printf "sixth\nfifth\nfourth\nthird\nsecond\ninitial" > expect
test_expect_success 'pretty' '

	git log --pretty="format:%s" > actual &&
	test_cmp expect actual
'

printf "sixth\nfifth\nfourth\nthird\nsecond\ninitial\n" > expect
test_expect_success 'pretty (tformat)' '

	git log --pretty="tformat:%s" > actual &&
	test_cmp expect actual
'

test_expect_success 'pretty (shortcut)' '

	git log --pretty="%s" > actual &&
	test_cmp expect actual
'

test_expect_success 'format' '

	git log --format="%s" > actual &&
	test_cmp expect actual
'

cat > expect << EOF
 This is
  the sixth
  commit.
 This is
  the fifth
  commit.
EOF

test_expect_success 'format %w(12,1,2)' '

	git log -2 --format="%w(12,1,2)This is the %s commit." > actual &&
	test_cmp expect actual
'

test_expect_success 'format %w(,1,2)' '

	git log -2 --format="%w(,1,2)This is%nthe %s%ncommit." > actual &&
	test_cmp expect actual
'

cat > expect << EOF
804a787 sixth
394ef78 fifth
5d31159 fourth
2fbe8c0 third
f7dab8e second
3a2fdcb initial
EOF
test_expect_success 'oneline' '

	git log --oneline > actual &&
	test_cmp expect actual
'

test_expect_success 'diff-filter=A' '

	git log --pretty="format:%s" --diff-filter=A HEAD > actual &&
	git log --pretty="format:%s" --diff-filter A HEAD > actual-separate &&
	printf "fifth\nfourth\nthird\ninitial" > expect &&
	test_cmp expect actual &&
	test_cmp expect actual-separate

'

test_expect_success 'diff-filter=M' '

	actual=$(git log --pretty="format:%s" --diff-filter=M HEAD) &&
	expect=$(echo second) &&
	test "$actual" = "$expect" || {
		echo Oops
		echo "Actual: $actual"
		false
	}

'

test_expect_success 'diff-filter=D' '

	actual=$(git log --pretty="format:%s" --diff-filter=D HEAD) &&
	expect=$(echo sixth ; echo third) &&
	test "$actual" = "$expect" || {
		echo Oops
		echo "Actual: $actual"
		false
	}

'

test_expect_success 'diff-filter=R' '

	actual=$(git log -M --pretty="format:%s" --diff-filter=R HEAD) &&
	expect=$(echo third) &&
	test "$actual" = "$expect" || {
		echo Oops
		echo "Actual: $actual"
		false
	}

'

test_expect_success 'diff-filter=C' '

	actual=$(git log -C -C --pretty="format:%s" --diff-filter=C HEAD) &&
	expect=$(echo fourth) &&
	test "$actual" = "$expect" || {
		echo Oops
		echo "Actual: $actual"
		false
	}

'

test_expect_success 'git log --follow' '

	actual=$(git log --follow --pretty="format:%s" ichi) &&
	expect=$(echo third ; echo second ; echo initial) &&
	test "$actual" = "$expect" || {
		echo Oops
		echo "Actual: $actual"
		false
	}

'

cat > expect << EOF
804a787 sixth
394ef78 fifth
5d31159 fourth
EOF
test_expect_success 'git log --no-walk <commits> sorts by commit time' '
	git log --no-walk --oneline 5d31159 804a787 394ef78 > actual &&
	test_cmp expect actual
'

cat > expect << EOF
5d31159 fourth
804a787 sixth
394ef78 fifth
EOF
test_expect_success 'git show <commits> leaves list of commits as given' '
	git show --oneline -s 5d31159 804a787 394ef78 > actual &&
	test_cmp expect actual
'

test_expect_success 'setup case sensitivity tests' '
	echo case >one &&
	test_tick &&
	git add one &&
	git commit -a -m Second
'

test_expect_success 'log --grep' '
	echo second >expect &&
	git log -1 --pretty="tformat:%s" --grep=sec >actual &&
	test_cmp expect actual
'

test_expect_success 'log --grep option parsing' '
	echo second >expect &&
	git log -1 --pretty="tformat:%s" --grep sec >actual &&
	test_cmp expect actual &&
	test_must_fail git log -1 --pretty="tformat:%s" --grep
'

test_expect_success 'log -i --grep' '
	echo Second >expect &&
	git log -1 --pretty="tformat:%s" -i --grep=sec >actual &&
	test_cmp expect actual
'

test_expect_success 'log --grep -i' '
	echo Second >expect &&
	git log -1 --pretty="tformat:%s" --grep=sec -i >actual &&
	test_cmp expect actual
'

cat > expect <<EOF
* Second
* sixth
* fifth
* fourth
* third
* second
* initial
EOF

test_expect_success 'simple log --graph' '
	git log --graph --pretty=tformat:%s >actual &&
	test_cmp expect actual
'

test_expect_success 'set up merge history' '
	git checkout -b side HEAD~4 &&
	test_commit side-1 1 1 &&
	test_commit side-2 2 2 &&
	git checkout master &&
	git merge side
'

cat > expect <<\EOF
*   Merge branch 'side'
|\
| * side-2
| * side-1
* | Second
* | sixth
* | fifth
* | fourth
|/
* third
* second
* initial
EOF

test_expect_success 'log --graph with merge' '
	git log --graph --date-order --pretty=tformat:%s |
		sed "s/ *\$//" >actual &&
	test_cmp expect actual
'

cat > expect <<\EOF
*   commit master
|\  Merge: A B
| | Author: A U Thor <author@example.com>
| |
| |     Merge branch 'side'
| |
| * commit side
| | Author: A U Thor <author@example.com>
| |
| |     side-2
| |
| * commit tags/side-1
| | Author: A U Thor <author@example.com>
| |
| |     side-1
| |
* | commit master~1
| | Author: A U Thor <author@example.com>
| |
| |     Second
| |
* | commit master~2
| | Author: A U Thor <author@example.com>
| |
| |     sixth
| |
* | commit master~3
| | Author: A U Thor <author@example.com>
| |
| |     fifth
| |
* | commit master~4
|/  Author: A U Thor <author@example.com>
|
|       fourth
|
* commit tags/side-1~1
| Author: A U Thor <author@example.com>
|
|     third
|
* commit tags/side-1~2
| Author: A U Thor <author@example.com>
|
|     second
|
* commit tags/side-1~3
  Author: A U Thor <author@example.com>

      initial
EOF

test_expect_success 'log --graph with full output' '
	git log --graph --date-order --pretty=short |
		git name-rev --name-only --stdin |
		sed "s/Merge:.*/Merge: A B/;s/ *\$//" >actual &&
	test_cmp expect actual
'

test_expect_success 'set up more tangled history' '
	git checkout -b tangle HEAD~6 &&
	test_commit tangle-a tangle-a a &&
	git merge master~3 &&
	git merge side~1 &&
	git checkout master &&
	git merge tangle &&
	git checkout -b reach &&
	test_commit reach &&
	git checkout master &&
	git checkout -b octopus-a &&
	test_commit octopus-a &&
	git checkout master &&
	git checkout -b octopus-b &&
	test_commit octopus-b &&
	git checkout master &&
	test_commit seventh &&
	git merge octopus-a octopus-b &&
	git merge reach
'

cat > expect <<\EOF
*   Merge commit 'reach'
|\
| \
|  \
*-. \   Merge commit 'octopus-a'; commit 'octopus-b'
|\ \ \
* | | | seventh
| | * | octopus-b
| |/ /
|/| |
| * | octopus-a
|/ /
| * reach
|/
*   Merge branch 'tangle'
|\
| *   Merge branch 'side' (early part) into tangle
| |\
| * \   Merge branch 'master' (early part) into tangle
| |\ \
| * | | tangle-a
* | | |   Merge branch 'side'
|\ \ \ \
| * | | | side-2
| | |_|/
| |/| |
| * | | side-1
* | | | Second
* | | | sixth
| |_|/
|/| |
* | | fifth
* | | fourth
|/ /
* | third
|/
* second
* initial
EOF

test_expect_success 'log --graph with merge' '
	git log --graph --date-order --pretty=tformat:%s |
		sed "s/ *\$//" >actual &&
	test_cmp expect actual
'

test_expect_success 'log.decorate configuration' '
	test_might_fail git config --unset-all log.decorate &&

	git log --oneline >expect.none &&
	git log --oneline --decorate >expect.short &&
	git log --oneline --decorate=full >expect.full &&

	echo "[log] decorate" >>.git/config &&
	git log --oneline >actual &&
	test_cmp expect.short actual &&

	git config --unset-all log.decorate &&
	git config log.decorate true &&
	git log --oneline >actual &&
	test_cmp expect.short actual &&
	git log --oneline --decorate=full >actual &&
	test_cmp expect.full actual &&
	git log --oneline --decorate=no >actual &&
	test_cmp expect.none actual &&

	git config --unset-all log.decorate &&
	git config log.decorate no &&
	git log --oneline >actual &&
	test_cmp expect.none actual &&
	git log --oneline --decorate >actual &&
	test_cmp expect.short actual &&
	git log --oneline --decorate=full >actual &&
	test_cmp expect.full actual &&

	git config --unset-all log.decorate &&
	git config log.decorate 1 &&
	git log --oneline >actual &&
	test_cmp expect.short actual &&
	git log --oneline --decorate=full >actual &&
	test_cmp expect.full actual &&
	git log --oneline --decorate=no >actual &&
	test_cmp expect.none actual &&

	git config --unset-all log.decorate &&
	git config log.decorate short &&
	git log --oneline >actual &&
	test_cmp expect.short actual &&
	git log --oneline --no-decorate >actual &&
	test_cmp expect.none actual &&
	git log --oneline --decorate=full >actual &&
	test_cmp expect.full actual &&

	git config --unset-all log.decorate &&
	git config log.decorate full &&
	git log --oneline >actual &&
	test_cmp expect.full actual &&
	git log --oneline --no-decorate >actual &&
	test_cmp expect.none actual &&
	git log --oneline --decorate >actual &&
	test_cmp expect.short actual

'

test_expect_success 'show added path under "--follow -M"' '
	# This tests for a regression introduced in v1.7.2-rc0~103^2~2
	test_create_repo regression &&
	(
		cd regression &&
		test_commit needs-another-commit &&
		test_commit foo.bar &&
		git log -M --follow -p foo.bar.t &&
		git log -M --follow --stat foo.bar.t &&
		git log -M --follow --name-only foo.bar.t
	)
'

test_done
