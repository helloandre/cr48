#!/bin/sh
#
# Copyright (c) 2007 Johannes E. Schindelin
#

test_description='git rebase interactive

This test runs git rebase "interactively", by faking an edit, and verifies
that the result still makes sense.

Initial setup:

     one - two - three - four (conflict-branch)
   /
 A - B - C - D - E            (master)
 | \
 |   F - G - H                (branch1)
 |     \
 |\      I                    (branch2)
 | \
 |   J - K - L - M            (no-conflict-branch)
  \
    N - O - P                 (no-ff-branch)

 where A, B, D and G all touch file1, and one, two, three, four all
 touch file "conflict".
'
. ./test-lib.sh

. "$TEST_DIRECTORY"/lib-rebase.sh

test_cmp_rev () {
	git rev-parse --verify "$1" >expect.rev &&
	git rev-parse --verify "$2" >actual.rev &&
	test_cmp expect.rev actual.rev
}

set_fake_editor

# WARNING: Modifications to the initial repository can change the SHA ID used
# in the expect2 file for the 'stop on conflicting pick' test.

test_expect_success 'setup' '
	test_commit A file1 &&
	test_commit B file1 &&
	test_commit C file2 &&
	test_commit D file1 &&
	test_commit E file3 &&
	git checkout -b branch1 A &&
	test_commit F file4 &&
	test_commit G file1 &&
	test_commit H file5 &&
	git checkout -b branch2 F &&
	test_commit I file6 &&
	git checkout -b conflict-branch A &&
	test_commit one conflict &&
	test_commit two conflict &&
	test_commit three conflict &&
	test_commit four conflict &&
	git checkout -b no-conflict-branch A &&
	test_commit J fileJ &&
	test_commit K fileK &&
	test_commit L fileL &&
	test_commit M fileM &&
	git checkout -b no-ff-branch A &&
	test_commit N fileN &&
	test_commit O fileO &&
	test_commit P fileP
'

# "exec" commands are ran with the user shell by default, but this may
# be non-POSIX. For example, if SHELL=zsh then ">file" doesn't work
# to create a file. Unseting SHELL avoids such non-portable behavior
# in tests. It must be exported for it to take effect where needed.
SHELL=
export SHELL

test_expect_success 'rebase -i with the exec command' '
	git checkout master &&
	(
	FAKE_LINES="1 exec_>touch-one
		2 exec_>touch-two exec_false exec_>touch-three
		3 4 exec_>\"touch-file__name_with_spaces\";_>touch-after-semicolon 5" &&
	export FAKE_LINES &&
	test_must_fail git rebase -i A
	) &&
	test_path_is_file touch-one &&
	test_path_is_file touch-two &&
	test_path_is_missing touch-three " (should have stopped before)" &&
	test_cmp_rev C HEAD &&
	git rebase --continue &&
	test_path_is_file touch-three &&
	test_path_is_file "touch-file  name with spaces" &&
	test_path_is_file touch-after-semicolon &&
	test_cmp_rev master HEAD &&
	rm -f touch-*
'

test_expect_success 'rebase -i with the exec command runs from tree root' '
	git checkout master &&
	mkdir subdir && (cd subdir &&
	FAKE_LINES="1 exec_>touch-subdir" \
		git rebase -i HEAD^
	) &&
	test_path_is_file touch-subdir &&
	rm -fr subdir
'

test_expect_success 'rebase -i with the exec command checks tree cleanness' '
	git checkout master &&
	(
	FAKE_LINES="exec_echo_foo_>file1 1" &&
	export FAKE_LINES &&
	test_must_fail git rebase -i HEAD^
	) &&
	test_cmp_rev master^ HEAD &&
	git reset --hard &&
	git rebase --continue
'

test_expect_success 'no changes are a nop' '
	git checkout branch2 &&
	git rebase -i F &&
	test "$(git symbolic-ref -q HEAD)" = "refs/heads/branch2" &&
	test $(git rev-parse I) = $(git rev-parse HEAD)
'

test_expect_success 'test the [branch] option' '
	git checkout -b dead-end &&
	git rm file6 &&
	git commit -m "stop here" &&
	git rebase -i F branch2 &&
	test "$(git symbolic-ref -q HEAD)" = "refs/heads/branch2" &&
	test $(git rev-parse I) = $(git rev-parse branch2) &&
	test $(git rev-parse I) = $(git rev-parse HEAD)
'

test_expect_success 'test --onto <branch>' '
	git checkout -b test-onto branch2 &&
	git rebase -i --onto branch1 F &&
	test "$(git symbolic-ref -q HEAD)" = "refs/heads/test-onto" &&
	test $(git rev-parse HEAD^) = $(git rev-parse branch1) &&
	test $(git rev-parse I) = $(git rev-parse branch2)
'

test_expect_success 'rebase on top of a non-conflicting commit' '
	git checkout branch1 &&
	git tag original-branch1 &&
	git rebase -i branch2 &&
	test file6 = $(git diff --name-only original-branch1) &&
	test "$(git symbolic-ref -q HEAD)" = "refs/heads/branch1" &&
	test $(git rev-parse I) = $(git rev-parse branch2) &&
	test $(git rev-parse I) = $(git rev-parse HEAD~2)
'

test_expect_success 'reflog for the branch shows state before rebase' '
	test $(git rev-parse branch1@{1}) = $(git rev-parse original-branch1)
'

test_expect_success 'exchange two commits' '
	FAKE_LINES="2 1" git rebase -i HEAD~2 &&
	test H = $(git cat-file commit HEAD^ | sed -ne \$p) &&
	test G = $(git cat-file commit HEAD | sed -ne \$p)
'

cat > expect << EOF
diff --git a/file1 b/file1
index f70f10e..fd79235 100644
--- a/file1
+++ b/file1
@@ -1 +1 @@
-A
+G
EOF

cat > expect2 << EOF
<<<<<<< HEAD
D
=======
G
>>>>>>> 5d18e54... G
EOF

test_expect_success 'stop on conflicting pick' '
	git tag new-branch1 &&
	test_must_fail git rebase -i master &&
	test "$(git rev-parse HEAD~3)" = "$(git rev-parse master)" &&
	test_cmp expect .git/rebase-merge/patch &&
	test_cmp expect2 file1 &&
	test "$(git diff --name-status |
		sed -n -e "/^U/s/^U[^a-z]*//p")" = file1 &&
	test 4 = $(grep -v "^#" < .git/rebase-merge/done | wc -l) &&
	test 0 = $(grep -c "^[^#]" < .git/rebase-merge/git-rebase-todo)
'

test_expect_success 'abort' '
	git rebase --abort &&
	test $(git rev-parse new-branch1) = $(git rev-parse HEAD) &&
	test "$(git symbolic-ref -q HEAD)" = "refs/heads/branch1" &&
	test_path_is_missing .git/rebase-merge
'

test_expect_success 'abort with error when new base cannot be checked out' '
	git rm --cached file1 &&
	git commit -m "remove file in base" &&
	test_must_fail git rebase -i master > output 2>&1 &&
	grep "The following untracked working tree files would be overwritten by checkout:" \
		output &&
	grep "file1" output &&
	test_path_is_missing .git/rebase-merge &&
	git reset --hard HEAD^
'

test_expect_success 'retain authorship' '
	echo A > file7 &&
	git add file7 &&
	test_tick &&
	GIT_AUTHOR_NAME="Twerp Snog" git commit -m "different author" &&
	git tag twerp &&
	git rebase -i --onto master HEAD^ &&
	git show HEAD | grep "^Author: Twerp Snog"
'

test_expect_success 'squash' '
	git reset --hard twerp &&
	echo B > file7 &&
	test_tick &&
	GIT_AUTHOR_NAME="Nitfol" git commit -m "nitfol" file7 &&
	echo "******************************" &&
	FAKE_LINES="1 squash 2" EXPECT_HEADER_COUNT=2 \
		git rebase -i --onto master HEAD~2 &&
	test B = $(cat file7) &&
	test $(git rev-parse HEAD^) = $(git rev-parse master)
'

test_expect_success 'retain authorship when squashing' '
	git show HEAD | grep "^Author: Twerp Snog"
'

test_expect_success '-p handles "no changes" gracefully' '
	HEAD=$(git rev-parse HEAD) &&
	git rebase -i -p HEAD^ &&
	git update-index --refresh &&
	git diff-files --quiet &&
	git diff-index --quiet --cached HEAD -- &&
	test $HEAD = $(git rev-parse HEAD)
'

test_expect_failure 'exchange two commits with -p' '
	FAKE_LINES="2 1" git rebase -i -p HEAD~2 &&
	test H = $(git cat-file commit HEAD^ | sed -ne \$p) &&
	test G = $(git cat-file commit HEAD | sed -ne \$p)
'

test_expect_success 'preserve merges with -p' '
	git checkout -b to-be-preserved master^ &&
	: > unrelated-file &&
	git add unrelated-file &&
	test_tick &&
	git commit -m "unrelated" &&
	git checkout -b another-branch master &&
	echo B > file1 &&
	test_tick &&
	git commit -m J file1 &&
	test_tick &&
	git merge to-be-preserved &&
	echo C > file1 &&
	test_tick &&
	git commit -m K file1 &&
	echo D > file1 &&
	test_tick &&
	git commit -m L1 file1 &&
	git checkout HEAD^ &&
	echo 1 > unrelated-file &&
	test_tick &&
	git commit -m L2 unrelated-file &&
	test_tick &&
	git merge another-branch &&
	echo E > file1 &&
	test_tick &&
	git commit -m M file1 &&
	git checkout -b to-be-rebased &&
	test_tick &&
	git rebase -i -p --onto branch1 master &&
	git update-index --refresh &&
	git diff-files --quiet &&
	git diff-index --quiet --cached HEAD -- &&
	test $(git rev-parse HEAD~6) = $(git rev-parse branch1) &&
	test $(git rev-parse HEAD~4^2) = $(git rev-parse to-be-preserved) &&
	test $(git rev-parse HEAD^^2^) = $(git rev-parse HEAD^^^) &&
	test $(git show HEAD~5:file1) = B &&
	test $(git show HEAD~3:file1) = C &&
	test $(git show HEAD:file1) = E &&
	test $(git show HEAD:unrelated-file) = 1
'

test_expect_success 'edit ancestor with -p' '
	FAKE_LINES="1 edit 2 3 4" git rebase -i -p HEAD~3 &&
	echo 2 > unrelated-file &&
	test_tick &&
	git commit -m L2-modified --amend unrelated-file &&
	git rebase --continue &&
	git update-index --refresh &&
	git diff-files --quiet &&
	git diff-index --quiet --cached HEAD -- &&
	test $(git show HEAD:unrelated-file) = 2
'

test_expect_success '--continue tries to commit' '
	test_tick &&
	test_must_fail git rebase -i --onto new-branch1 HEAD^ &&
	echo resolved > file1 &&
	git add file1 &&
	FAKE_COMMIT_MESSAGE="chouette!" git rebase --continue &&
	test $(git rev-parse HEAD^) = $(git rev-parse new-branch1) &&
	git show HEAD | grep chouette
'

test_expect_success 'verbose flag is heeded, even after --continue' '
	git reset --hard HEAD@{1} &&
	test_tick &&
	test_must_fail git rebase -v -i --onto new-branch1 HEAD^ &&
	echo resolved > file1 &&
	git add file1 &&
	git rebase --continue > output &&
	grep "^ file1 |    2 +-$" output
'

test_expect_success 'multi-squash only fires up editor once' '
	base=$(git rev-parse HEAD~4) &&
	FAKE_COMMIT_AMEND="ONCE" FAKE_LINES="1 squash 2 squash 3 squash 4" \
		EXPECT_HEADER_COUNT=4 \
		git rebase -i $base &&
	test $base = $(git rev-parse HEAD^) &&
	test 1 = $(git show | grep ONCE | wc -l)
'

test_expect_success 'multi-fixup does not fire up editor' '
	git checkout -b multi-fixup E &&
	base=$(git rev-parse HEAD~4) &&
	FAKE_COMMIT_AMEND="NEVER" FAKE_LINES="1 fixup 2 fixup 3 fixup 4" \
		git rebase -i $base &&
	test $base = $(git rev-parse HEAD^) &&
	test 0 = $(git show | grep NEVER | wc -l) &&
	git checkout to-be-rebased &&
	git branch -D multi-fixup
'

test_expect_success 'commit message used after conflict' '
	git checkout -b conflict-fixup conflict-branch &&
	base=$(git rev-parse HEAD~4) &&
	(
		FAKE_LINES="1 fixup 3 fixup 4" &&
		export FAKE_LINES &&
		test_must_fail git rebase -i $base
	) &&
	echo three > conflict &&
	git add conflict &&
	FAKE_COMMIT_AMEND="ONCE" EXPECT_HEADER_COUNT=2 \
		git rebase --continue &&
	test $base = $(git rev-parse HEAD^) &&
	test 1 = $(git show | grep ONCE | wc -l) &&
	git checkout to-be-rebased &&
	git branch -D conflict-fixup
'

test_expect_success 'commit message retained after conflict' '
	git checkout -b conflict-squash conflict-branch &&
	base=$(git rev-parse HEAD~4) &&
	(
		FAKE_LINES="1 fixup 3 squash 4" &&
		export FAKE_LINES &&
		test_must_fail git rebase -i $base
	) &&
	echo three > conflict &&
	git add conflict &&
	FAKE_COMMIT_AMEND="TWICE" EXPECT_HEADER_COUNT=2 \
		git rebase --continue &&
	test $base = $(git rev-parse HEAD^) &&
	test 2 = $(git show | grep TWICE | wc -l) &&
	git checkout to-be-rebased &&
	git branch -D conflict-squash
'

cat > expect-squash-fixup << EOF
B

D

ONCE
EOF

test_expect_success 'squash and fixup generate correct log messages' '
	git checkout -b squash-fixup E &&
	base=$(git rev-parse HEAD~4) &&
	FAKE_COMMIT_AMEND="ONCE" FAKE_LINES="1 fixup 2 squash 3 fixup 4" \
		EXPECT_HEADER_COUNT=4 \
		git rebase -i $base &&
	git cat-file commit HEAD | sed -e 1,/^\$/d > actual-squash-fixup &&
	test_cmp expect-squash-fixup actual-squash-fixup &&
	git checkout to-be-rebased &&
	git branch -D squash-fixup
'

test_expect_success 'squash ignores comments' '
	git checkout -b skip-comments E &&
	base=$(git rev-parse HEAD~4) &&
	FAKE_COMMIT_AMEND="ONCE" FAKE_LINES="# 1 # squash 2 # squash 3 # squash 4 #" \
		EXPECT_HEADER_COUNT=4 \
		git rebase -i $base &&
	test $base = $(git rev-parse HEAD^) &&
	test 1 = $(git show | grep ONCE | wc -l) &&
	git checkout to-be-rebased &&
	git branch -D skip-comments
'

test_expect_success 'squash ignores blank lines' '
	git checkout -b skip-blank-lines E &&
	base=$(git rev-parse HEAD~4) &&
	FAKE_COMMIT_AMEND="ONCE" FAKE_LINES="> 1 > squash 2 > squash 3 > squash 4 >" \
		EXPECT_HEADER_COUNT=4 \
		git rebase -i $base &&
	test $base = $(git rev-parse HEAD^) &&
	test 1 = $(git show | grep ONCE | wc -l) &&
	git checkout to-be-rebased &&
	git branch -D skip-blank-lines
'

test_expect_success 'squash works as expected' '
	git checkout -b squash-works no-conflict-branch &&
	one=$(git rev-parse HEAD~3) &&
	FAKE_LINES="1 squash 3 2" EXPECT_HEADER_COUNT=2 \
		git rebase -i HEAD~3 &&
	test $one = $(git rev-parse HEAD~2)
'

test_expect_success 'interrupted squash works as expected' '
	git checkout -b interrupted-squash conflict-branch &&
	one=$(git rev-parse HEAD~3) &&
	(
		FAKE_LINES="1 squash 3 2" &&
		export FAKE_LINES &&
		test_must_fail git rebase -i HEAD~3
	) &&
	(echo one; echo two; echo four) > conflict &&
	git add conflict &&
	test_must_fail git rebase --continue &&
	echo resolved > conflict &&
	git add conflict &&
	git rebase --continue &&
	test $one = $(git rev-parse HEAD~2)
'

test_expect_success 'interrupted squash works as expected (case 2)' '
	git checkout -b interrupted-squash2 conflict-branch &&
	one=$(git rev-parse HEAD~3) &&
	(
		FAKE_LINES="3 squash 1 2" &&
		export FAKE_LINES &&
		test_must_fail git rebase -i HEAD~3
	) &&
	(echo one; echo four) > conflict &&
	git add conflict &&
	test_must_fail git rebase --continue &&
	(echo one; echo two; echo four) > conflict &&
	git add conflict &&
	test_must_fail git rebase --continue &&
	echo resolved > conflict &&
	git add conflict &&
	git rebase --continue &&
	test $one = $(git rev-parse HEAD~2)
'

test_expect_success 'ignore patch if in upstream' '
	HEAD=$(git rev-parse HEAD) &&
	git checkout -b has-cherry-picked HEAD^ &&
	echo unrelated > file7 &&
	git add file7 &&
	test_tick &&
	git commit -m "unrelated change" &&
	git cherry-pick $HEAD &&
	EXPECT_COUNT=1 git rebase -i $HEAD &&
	test $HEAD = $(git rev-parse HEAD^)
'

test_expect_success '--continue tries to commit, even for "edit"' '
	parent=$(git rev-parse HEAD^) &&
	test_tick &&
	FAKE_LINES="edit 1" git rebase -i HEAD^ &&
	echo edited > file7 &&
	git add file7 &&
	FAKE_COMMIT_MESSAGE="chouette!" git rebase --continue &&
	test edited = $(git show HEAD:file7) &&
	git show HEAD | grep chouette &&
	test $parent = $(git rev-parse HEAD^)
'

test_expect_success 'aborted --continue does not squash commits after "edit"' '
	old=$(git rev-parse HEAD) &&
	test_tick &&
	FAKE_LINES="edit 1" git rebase -i HEAD^ &&
	echo "edited again" > file7 &&
	git add file7 &&
	(
		FAKE_COMMIT_MESSAGE=" " &&
		export FAKE_COMMIT_MESSAGE &&
		test_must_fail git rebase --continue
	) &&
	test $old = $(git rev-parse HEAD) &&
	git rebase --abort
'

test_expect_success 'auto-amend only edited commits after "edit"' '
	test_tick &&
	FAKE_LINES="edit 1" git rebase -i HEAD^ &&
	echo "edited again" > file7 &&
	git add file7 &&
	FAKE_COMMIT_MESSAGE="edited file7 again" git commit &&
	echo "and again" > file7 &&
	git add file7 &&
	test_tick &&
	(
		FAKE_COMMIT_MESSAGE="and again" &&
		export FAKE_COMMIT_MESSAGE &&
		test_must_fail git rebase --continue
	) &&
	git rebase --abort
'

test_expect_success 'rebase a detached HEAD' '
	grandparent=$(git rev-parse HEAD~2) &&
	git checkout $(git rev-parse HEAD) &&
	test_tick &&
	FAKE_LINES="2 1" git rebase -i HEAD~2 &&
	test $grandparent = $(git rev-parse HEAD~2)
'

test_expect_success 'rebase a commit violating pre-commit' '

	mkdir -p .git/hooks &&
	PRE_COMMIT=.git/hooks/pre-commit &&
	echo "#!/bin/sh" > $PRE_COMMIT &&
	echo "test -z \"\$(git diff --cached --check)\"" >> $PRE_COMMIT &&
	chmod a+x $PRE_COMMIT &&
	echo "monde! " >> file1 &&
	test_tick &&
	test_must_fail git commit -m doesnt-verify file1 &&
	git commit -m doesnt-verify --no-verify file1 &&
	test_tick &&
	FAKE_LINES=2 git rebase -i HEAD~2

'

test_expect_success 'rebase with a file named HEAD in worktree' '

	rm -fr .git/hooks &&
	git reset --hard &&
	git checkout -b branch3 A &&

	(
		GIT_AUTHOR_NAME="Squashed Away" &&
		export GIT_AUTHOR_NAME &&
		>HEAD &&
		git add HEAD &&
		git commit -m "Add head" &&
		>BODY &&
		git add BODY &&
		git commit -m "Add body"
	) &&

	FAKE_LINES="1 squash 2" git rebase -i to-be-rebased &&
	test "$(git show -s --pretty=format:%an)" = "Squashed Away"

'

test_expect_success 'do "noop" when there is nothing to cherry-pick' '

	git checkout -b branch4 HEAD &&
	GIT_EDITOR=: git commit --amend \
		--author="Somebody else <somebody@else.com>" &&
	test $(git rev-parse branch3) != $(git rev-parse branch4) &&
	git rebase -i branch3 &&
	test $(git rev-parse branch3) = $(git rev-parse branch4)

'

test_expect_success 'submodule rebase setup' '
	git checkout A &&
	mkdir sub &&
	(
		cd sub && git init && >elif &&
		git add elif && git commit -m "submodule initial"
	) &&
	echo 1 >file1 &&
	git add file1 sub &&
	test_tick &&
	git commit -m "One" &&
	echo 2 >file1 &&
	test_tick &&
	git commit -a -m "Two" &&
	(
		cd sub && echo 3 >elif &&
		git commit -a -m "submodule second"
	) &&
	test_tick &&
	git commit -a -m "Three changes submodule"
'

test_expect_success 'submodule rebase -i' '
	FAKE_LINES="1 squash 2 3" git rebase -i A
'

test_expect_success 'avoid unnecessary reset' '
	git checkout master &&
	test-chmtime =123456789 file3 &&
	git update-index --refresh &&
	HEAD=$(git rev-parse HEAD) &&
	git rebase -i HEAD~4 &&
	test $HEAD = $(git rev-parse HEAD) &&
	MTIME=$(test-chmtime -v +0 file3 | sed 's/[^0-9].*$//') &&
	test 123456789 = $MTIME
'

test_expect_success 'reword' '
	git checkout -b reword-branch master &&
	FAKE_LINES="1 2 3 reword 4" FAKE_COMMIT_MESSAGE="E changed" git rebase -i A &&
	git show HEAD | grep "E changed" &&
	test $(git rev-parse master) != $(git rev-parse HEAD) &&
	test $(git rev-parse master^) = $(git rev-parse HEAD^) &&
	FAKE_LINES="1 2 reword 3 4" FAKE_COMMIT_MESSAGE="D changed" git rebase -i A &&
	git show HEAD^ | grep "D changed" &&
	FAKE_LINES="reword 1 2 3 4" FAKE_COMMIT_MESSAGE="B changed" git rebase -i A &&
	git show HEAD~3 | grep "B changed" &&
	FAKE_LINES="1 reword 2 3 4" FAKE_COMMIT_MESSAGE="C changed" git rebase -i A &&
	git show HEAD~2 | grep "C changed"
'

test_expect_success 'rebase -i can copy notes' '
	git config notes.rewrite.rebase true &&
	git config notes.rewriteRef "refs/notes/*" &&
	test_commit n1 &&
	test_commit n2 &&
	test_commit n3 &&
	git notes add -m"a note" n3 &&
	git rebase --onto n1 n2 &&
	test "a note" = "$(git notes show HEAD)"
'

cat >expect <<EOF
an earlier note

a note
EOF

test_expect_success 'rebase -i can copy notes over a fixup' '
	git reset --hard n3 &&
	git notes add -m"an earlier note" n2 &&
	GIT_NOTES_REWRITE_MODE=concatenate FAKE_LINES="1 fixup 2" git rebase -i n1 &&
	git notes show > output &&
	test_cmp expect output
'

test_expect_success 'rebase while detaching HEAD' '
	git symbolic-ref HEAD &&
	grandparent=$(git rev-parse HEAD~2) &&
	test_tick &&
	FAKE_LINES="2 1" git rebase -i HEAD~2 HEAD^0 &&
	test $grandparent = $(git rev-parse HEAD~2) &&
	test_must_fail git symbolic-ref HEAD
'

test_tick # Ensure that the rebased commits get a different timestamp.
test_expect_success 'always cherry-pick with --no-ff' '
	git checkout no-ff-branch &&
	git tag original-no-ff-branch &&
	git rebase -i --no-ff A &&
	touch empty &&
	for p in 0 1 2
	do
		test ! $(git rev-parse HEAD~$p) = $(git rev-parse original-no-ff-branch~$p) &&
		git diff HEAD~$p original-no-ff-branch~$p > out &&
		test_cmp empty out
	done &&
	test $(git rev-parse HEAD~3) = $(git rev-parse original-no-ff-branch~3) &&
	git diff HEAD~3 original-no-ff-branch~3 > out &&
	test_cmp empty out
'

test_expect_success 'set up commits with funny messages' '
	git checkout -b funny A &&
	echo >>file1 &&
	test_tick &&
	git commit -a -m "end with slash\\" &&
	echo >>file1 &&
	test_tick &&
	git commit -a -m "something (\000) that looks like octal" &&
	echo >>file1 &&
	test_tick &&
	git commit -a -m "something (\n) that looks like a newline" &&
	echo >>file1 &&
	test_tick &&
	git commit -a -m "another commit"
'

test_expect_success 'rebase-i history with funny messages' '
	git rev-list A..funny >expect &&
	test_tick &&
	FAKE_LINES="1 2 3 4" git rebase -i A &&
	git rev-list A.. >actual &&
	test_cmp expect actual
'

test_done
