#!/bin/sh
#
# Copyright (c) 2007 Steven Grimm
#

test_description='git commit

Tests for selected commit options.'

. ./test-lib.sh

commit_msg_is () {
	test "`git log --pretty=format:%s%b -1`" = "$1"
}

# A sanity check to see if commit is working at all.
test_expect_success 'a basic commit in an empty tree should succeed' '
	echo content > foo &&
	git add foo &&
	git commit -m "initial commit"
'

test_expect_success 'nonexistent template file should return error' '
	echo changes >> foo &&
	git add foo &&
	test_must_fail git commit --template "$PWD"/notexist
'

test_expect_success 'nonexistent template file in config should return error' '
	git config commit.template "$PWD"/notexist &&
	test_must_fail git commit &&
	git config --unset commit.template
'

# From now on we'll use a template file that exists.
TEMPLATE="$PWD"/template

test_expect_success 'unedited template should not commit' '
	echo "template line" > "$TEMPLATE" &&
	test_must_fail git commit --template "$TEMPLATE"
'

test_expect_success 'unedited template with comments should not commit' '
	echo "# comment in template" >> "$TEMPLATE" &&
	test_must_fail git commit --template "$TEMPLATE"
'

test_expect_success 'a Signed-off-by line by itself should not commit' '
	(
		test_set_editor "$TEST_DIRECTORY"/t7500/add-signed-off &&
		test_must_fail git commit --template "$TEMPLATE"
	)
'

test_expect_success 'adding comments to a template should not commit' '
	(
		test_set_editor "$TEST_DIRECTORY"/t7500/add-comments &&
		test_must_fail git commit --template "$TEMPLATE"
	)
'

test_expect_success 'adding real content to a template should commit' '
	(
		test_set_editor "$TEST_DIRECTORY"/t7500/add-content &&
		git commit --template "$TEMPLATE"
	) &&
	commit_msg_is "template linecommit message"
'

test_expect_success '-t option should be short for --template' '
	echo "short template" > "$TEMPLATE" &&
	echo "new content" >> foo &&
	git add foo &&
	(
		test_set_editor "$TEST_DIRECTORY"/t7500/add-content &&
		git commit -t "$TEMPLATE"
	) &&
	commit_msg_is "short templatecommit message"
'

test_expect_success 'config-specified template should commit' '
	echo "new template" > "$TEMPLATE" &&
	git config commit.template "$TEMPLATE" &&
	echo "more content" >> foo &&
	git add foo &&
	(
		test_set_editor "$TEST_DIRECTORY"/t7500/add-content &&
		git commit
	) &&
	git config --unset commit.template &&
	commit_msg_is "new templatecommit message"
'

test_expect_success 'explicit commit message should override template' '
	echo "still more content" >> foo &&
	git add foo &&
	GIT_EDITOR="$TEST_DIRECTORY"/t7500/add-content git commit --template "$TEMPLATE" \
		-m "command line msg" &&
	commit_msg_is "command line msg"
'

test_expect_success 'commit message from file should override template' '
	echo "content galore" >> foo &&
	git add foo &&
	echo "standard input msg" |
	(
		test_set_editor "$TEST_DIRECTORY"/t7500/add-content &&
		git commit --template "$TEMPLATE" --file -
	) &&
	commit_msg_is "standard input msg"
'

test_expect_success 'using alternate GIT_INDEX_FILE (1)' '

	cp .git/index saved-index &&
	(
		echo some new content >file &&
	        GIT_INDEX_FILE=.git/another_index &&
		export GIT_INDEX_FILE &&
		git add file &&
		git commit -m "commit using another index" &&
		git diff-index --exit-code HEAD &&
		git diff-files --exit-code
	) &&
	cmp .git/index saved-index >/dev/null

'

test_expect_success 'using alternate GIT_INDEX_FILE (2)' '

	cp .git/index saved-index &&
	(
		rm -f .git/no-such-index &&
		GIT_INDEX_FILE=.git/no-such-index &&
		export GIT_INDEX_FILE &&
		git commit -m "commit using nonexistent index" &&
		test -z "$(git ls-files)" &&
		test -z "$(git ls-tree HEAD)"

	) &&
	cmp .git/index saved-index >/dev/null
'

cat > expect << EOF
zort

Signed-off-by: C O Mitter <committer@example.com>
EOF

test_expect_success '--signoff' '
	echo "yet another content *narf*" >> foo &&
	echo "zort" | git commit -s -F - foo &&
	git cat-file commit HEAD | sed "1,/^\$/d" > output &&
	test_cmp expect output
'

test_expect_success 'commit message from file (1)' '
	mkdir subdir &&
	echo "Log in top directory" >log &&
	echo "Log in sub directory" >subdir/log &&
	(
		cd subdir &&
		git commit --allow-empty -F log
	) &&
	commit_msg_is "Log in sub directory"
'

test_expect_success 'commit message from file (2)' '
	rm -f log &&
	echo "Log in sub directory" >subdir/log &&
	(
		cd subdir &&
		git commit --allow-empty -F log
	) &&
	commit_msg_is "Log in sub directory"
'

test_expect_success 'commit message from stdin' '
	(
		cd subdir &&
		echo "Log with foo word" | git commit --allow-empty -F -
	) &&
	commit_msg_is "Log with foo word"
'

test_expect_success 'commit -F overrides -t' '
	(
		cd subdir &&
		echo "-F log" > f.log &&
		echo "-t template" > t.template &&
		git commit --allow-empty -F f.log -t t.template
	) &&
	commit_msg_is "-F log"
'

test_expect_success 'Commit without message is allowed with --allow-empty-message' '
	echo "more content" >>foo &&
	git add foo &&
	>empty &&
	git commit --allow-empty-message <empty &&
	commit_msg_is ""
'

test_expect_success 'Commit without message is no-no without --allow-empty-message' '
	echo "more content" >>foo &&
	git add foo &&
	>empty &&
	test_must_fail git commit <empty
'

test_expect_success 'Commit a message with --allow-empty-message' '
	echo "even more content" >>foo &&
	git add foo &&
	git commit --allow-empty-message -m"hello there" &&
	commit_msg_is "hello there"
'

commit_for_rebase_autosquash_setup () {
	echo "first content line" >>foo &&
	git add foo &&
	cat >log <<EOF &&
target message subject line

target message body line 1
target message body line 2
EOF
	git commit -F log &&
	echo "second content line" >>foo &&
	git add foo &&
	git commit -m "intermediate commit" &&
	echo "third content line" >>foo &&
	git add foo
}

test_expect_success 'commit --fixup provides correct one-line commit message' '
	commit_for_rebase_autosquash_setup &&
	git commit --fixup HEAD~1 &&
	commit_msg_is "fixup! target message subject line"
'

test_expect_success 'commit --squash works with -F' '
	commit_for_rebase_autosquash_setup &&
	echo "log message from file" >msgfile &&
	git commit --squash HEAD~1 -F msgfile  &&
	commit_msg_is "squash! target message subject linelog message from file"
'

test_expect_success 'commit --squash works with -m' '
	commit_for_rebase_autosquash_setup &&
	git commit --squash HEAD~1 -m "foo bar\nbaz" &&
	commit_msg_is "squash! target message subject linefoo bar\nbaz"
'

test_expect_success 'commit --squash works with -C' '
	commit_for_rebase_autosquash_setup &&
	git commit --squash HEAD~1 -C HEAD &&
	commit_msg_is "squash! target message subject lineintermediate commit"
'

test_expect_success 'commit --squash works with -c' '
	commit_for_rebase_autosquash_setup &&
	test_set_editor "$TEST_DIRECTORY"/t7500/edit-content &&
	git commit --squash HEAD~1 -c HEAD &&
	commit_msg_is "squash! target message subject lineedited commit"
'

test_expect_success 'commit --squash works with -C for same commit' '
	commit_for_rebase_autosquash_setup &&
	git commit --squash HEAD -C HEAD &&
	commit_msg_is "squash! intermediate commit"
'

test_expect_success 'commit --squash works with -c for same commit' '
	commit_for_rebase_autosquash_setup &&
	test_set_editor "$TEST_DIRECTORY"/t7500/edit-content &&
	git commit --squash HEAD -c HEAD &&
	commit_msg_is "squash! edited commit"
'

test_expect_success 'commit --squash works with editor' '
	commit_for_rebase_autosquash_setup &&
	test_set_editor "$TEST_DIRECTORY"/t7500/add-content &&
	git commit --squash HEAD~1 &&
	commit_msg_is "squash! target message subject linecommit message"
'

test_expect_success 'invalid message options when using --fixup' '
	echo changes >>foo &&
	echo "message" >log &&
	git add foo &&
	test_must_fail git commit --fixup HEAD~1 --squash HEAD~2 &&
	test_must_fail git commit --fixup HEAD~1 -C HEAD~2 &&
	test_must_fail git commit --fixup HEAD~1 -c HEAD~2 &&
	test_must_fail git commit --fixup HEAD~1 -m "cmdline message" &&
	test_must_fail git commit --fixup HEAD~1 -F log
'

test_done
