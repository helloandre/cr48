#!/bin/sh

test_description='git remote porcelain-ish'

. ./test-lib.sh

setup_repository () {
	mkdir "$1" && (
	cd "$1" &&
	git init &&
	>file &&
	git add file &&
	test_tick &&
	git commit -m "Initial" &&
	git checkout -b side &&
	>elif &&
	git add elif &&
	test_tick &&
	git commit -m "Second" &&
	git checkout master
	)
}

tokens_match () {
	echo "$1" | tr ' ' '\012' | sort | sed -e '/^$/d' >expect &&
	echo "$2" | tr ' ' '\012' | sort | sed -e '/^$/d' >actual &&
	test_cmp expect actual
}

check_remote_track () {
	actual=$(git remote show "$1" | sed -ne 's|^    \(.*\) tracked$|\1|p')
	shift &&
	tokens_match "$*" "$actual"
}

check_tracking_branch () {
	f="" &&
	r=$(git for-each-ref "--format=%(refname)" |
		sed -ne "s|^refs/remotes/$1/||p") &&
	shift &&
	tokens_match "$*" "$r"
}

test_expect_success setup '

	setup_repository one &&
	setup_repository two &&
	(
		cd two && git branch another
	) &&
	git clone one test

'

test_expect_success 'remote information for the origin' '
(
	cd test &&
	tokens_match origin "$(git remote)" &&
	check_remote_track origin master side &&
	check_tracking_branch origin HEAD master side
)
'

test_expect_success 'add another remote' '
(
	cd test &&
	git remote add -f second ../two &&
	tokens_match "origin second" "$(git remote)" &&
	check_remote_track origin master side &&
	check_remote_track second master side another &&
	check_tracking_branch second master side another &&
	git for-each-ref "--format=%(refname)" refs/remotes |
	sed -e "/^refs\/remotes\/origin\//d" \
	    -e "/^refs\/remotes\/second\//d" >actual &&
	>expect &&
	test_cmp expect actual
)
'

test_expect_success 'remote forces tracking branches' '
(
	cd test &&
	case `git config remote.second.fetch` in
	+*) true ;;
	 *) false ;;
	esac
)
'

test_expect_success 'remove remote' '
(
	cd test &&
	git symbolic-ref refs/remotes/second/HEAD refs/remotes/second/master &&
	git remote rm second
)
'

test_expect_success 'remove remote' '
(
	cd test &&
	tokens_match origin "$(git remote)" &&
	check_remote_track origin master side &&
	git for-each-ref "--format=%(refname)" refs/remotes |
	sed -e "/^refs\/remotes\/origin\//d" >actual &&
	>expect &&
	test_cmp expect actual
)
'

test_expect_success 'remove remote protects local branches' '
(
	cd test &&
	{ cat >expect1 <<EOF
Note: A branch outside the refs/remotes/ hierarchy was not removed;
to delete it, use:
  git branch -d master
EOF
	} &&
	{ cat >expect2 <<EOF
Note: Some branches outside the refs/remotes/ hierarchy were not removed;
to delete them, use:
  git branch -d foobranch
  git branch -d master
EOF
	} &&
	git tag footag &&
	git config --add remote.oops.fetch "+refs/*:refs/*" &&
	git remote rm oops 2>actual1 &&
	git branch foobranch &&
	git config --add remote.oops.fetch "+refs/*:refs/*" &&
	git remote rm oops 2>actual2 &&
	git branch -d foobranch &&
	git tag -d footag &&
	test_cmp expect1 actual1 &&
	test_cmp expect2 actual2
)
'

cat > test/expect << EOF
* remote origin
  Fetch URL: $(pwd)/one
  Push  URL: $(pwd)/one
  HEAD branch: master
  Remote branches:
    master new (next fetch will store in remotes/origin)
    side   tracked
  Local branches configured for 'git pull':
    ahead    merges with remote master
    master   merges with remote master
    octopus  merges with remote topic-a
                and with remote topic-b
                and with remote topic-c
    rebase  rebases onto remote master
  Local refs configured for 'git push':
    master pushes to master   (local out of date)
    master pushes to upstream (create)
* remote two
  Fetch URL: ../two
  Push  URL: ../three
  HEAD branch (remote HEAD is ambiguous, may be one of the following):
    another
    master
  Local refs configured for 'git push':
    ahead  forces to master  (fast-forwardable)
    master pushes to another (up to date)
EOF

test_expect_success 'show' '
	(cd test &&
	 git config --add remote.origin.fetch refs/heads/master:refs/heads/upstream &&
	 git fetch &&
	 git checkout -b ahead origin/master &&
	 echo 1 >> file &&
	 test_tick &&
	 git commit -m update file &&
	 git checkout master &&
	 git branch --track octopus origin/master &&
	 git branch --track rebase origin/master &&
	 git branch -d -r origin/master &&
	 git config --add remote.two.url ../two &&
	 git config --add remote.two.pushurl ../three &&
	 git config branch.rebase.rebase true &&
	 git config branch.octopus.merge "topic-a topic-b topic-c" &&
	 (cd ../one &&
	  echo 1 > file &&
	  test_tick &&
	  git commit -m update file) &&
	 git config --add remote.origin.push : &&
	 git config --add remote.origin.push refs/heads/master:refs/heads/upstream &&
	 git config --add remote.origin.push +refs/tags/lastbackup &&
	 git config --add remote.two.push +refs/heads/ahead:refs/heads/master &&
	 git config --add remote.two.push refs/heads/master:refs/heads/another &&
	 git remote show origin two > output &&
	 git branch -d rebase octopus &&
	 test_cmp expect output)
'

cat > test/expect << EOF
* remote origin
  Fetch URL: $(pwd)/one
  Push  URL: $(pwd)/one
  HEAD branch: (not queried)
  Remote branches: (status not queried)
    master
    side
  Local branches configured for 'git pull':
    ahead  merges with remote master
    master merges with remote master
  Local refs configured for 'git push' (status not queried):
    (matching)           pushes to (matching)
    refs/heads/master    pushes to refs/heads/upstream
    refs/tags/lastbackup forces to refs/tags/lastbackup
EOF

test_expect_success 'show -n' '
	(mv one one.unreachable &&
	 cd test &&
	 git remote show -n origin > output &&
	 mv ../one.unreachable ../one &&
	 test_cmp expect output)
'

test_expect_success 'prune' '
	(cd one &&
	 git branch -m side side2) &&
	(cd test &&
	 git fetch origin &&
	 git remote prune origin &&
	 git rev-parse refs/remotes/origin/side2 &&
	 test_must_fail git rev-parse refs/remotes/origin/side)
'

test_expect_success 'set-head --delete' '
	(cd test &&
	 git symbolic-ref refs/remotes/origin/HEAD &&
	 git remote set-head --delete origin &&
	 test_must_fail git symbolic-ref refs/remotes/origin/HEAD)
'

test_expect_success 'set-head --auto' '
	(cd test &&
	 git remote set-head --auto origin &&
	 echo refs/remotes/origin/master >expect &&
	 git symbolic-ref refs/remotes/origin/HEAD >output &&
	 test_cmp expect output
	)
'

cat >test/expect <<EOF
error: Multiple remote HEAD branches. Please choose one explicitly with:
  git remote set-head two another
  git remote set-head two master
EOF

test_expect_success 'set-head --auto fails w/multiple HEADs' '
	(cd test &&
	 test_must_fail git remote set-head --auto two >output 2>&1 &&
	test_cmp expect output)
'

cat >test/expect <<EOF
refs/remotes/origin/side2
EOF

test_expect_success 'set-head explicit' '
	(cd test &&
	 git remote set-head origin side2 &&
	 git symbolic-ref refs/remotes/origin/HEAD >output &&
	 git remote set-head origin master &&
	 test_cmp expect output)
'

cat > test/expect << EOF
Pruning origin
URL: $(pwd)/one
 * [would prune] origin/side2
EOF

test_expect_success 'prune --dry-run' '
	(cd one &&
	 git branch -m side2 side) &&
	(cd test &&
	 git remote prune --dry-run origin > output &&
	 git rev-parse refs/remotes/origin/side2 &&
	 test_must_fail git rev-parse refs/remotes/origin/side &&
	(cd ../one &&
	 git branch -m side side2) &&
	 test_cmp expect output)
'

test_expect_success 'add --mirror && prune' '
	(mkdir mirror &&
	 cd mirror &&
	 git init --bare &&
	 git remote add --mirror -f origin ../one) &&
	(cd one &&
	 git branch -m side2 side) &&
	(cd mirror &&
	 git rev-parse --verify refs/heads/side2 &&
	 test_must_fail git rev-parse --verify refs/heads/side &&
	 git fetch origin &&
	 git remote prune origin &&
	 test_must_fail git rev-parse --verify refs/heads/side2 &&
	 git rev-parse --verify refs/heads/side)
'

test_expect_success 'add --mirror=fetch' '
	mkdir mirror-fetch &&
	git init mirror-fetch/parent &&
	(cd mirror-fetch/parent &&
	 test_commit one) &&
	git init --bare mirror-fetch/child &&
	(cd mirror-fetch/child &&
	 git remote add --mirror=fetch -f parent ../parent)
'

test_expect_success 'fetch mirrors act as mirrors during fetch' '
	(cd mirror-fetch/parent &&
	 git branch new &&
	 git branch -m master renamed
	) &&
	(cd mirror-fetch/child &&
	 git fetch parent &&
	 git rev-parse --verify refs/heads/new &&
	 git rev-parse --verify refs/heads/renamed
	)
'

test_expect_success 'fetch mirrors can prune' '
	(cd mirror-fetch/child &&
	 git remote prune parent &&
	 test_must_fail git rev-parse --verify refs/heads/master
	)
'

test_expect_success 'fetch mirrors do not act as mirrors during push' '
	(cd mirror-fetch/parent &&
	 git checkout HEAD^0
	) &&
	(cd mirror-fetch/child &&
	 git branch -m renamed renamed2 &&
	 git push parent
	) &&
	(cd mirror-fetch/parent &&
	 git rev-parse --verify renamed &&
	 test_must_fail git rev-parse --verify refs/heads/renamed2
	)
'

test_expect_success 'add --mirror=push' '
	mkdir mirror-push &&
	git init --bare mirror-push/public &&
	git init mirror-push/private &&
	(cd mirror-push/private &&
	 test_commit one &&
	 git remote add --mirror=push public ../public
	)
'

test_expect_success 'push mirrors act as mirrors during push' '
	(cd mirror-push/private &&
	 git branch new &&
	 git branch -m master renamed &&
	 git push public
	) &&
	(cd mirror-push/private &&
	 git rev-parse --verify refs/heads/new &&
	 git rev-parse --verify refs/heads/renamed &&
	 test_must_fail git rev-parse --verify refs/heads/master
	)
'

test_expect_success 'push mirrors do not act as mirrors during fetch' '
	(cd mirror-push/public &&
	 git branch -m renamed renamed2 &&
	 git symbolic-ref HEAD refs/heads/renamed2
	) &&
	(cd mirror-push/private &&
	 git fetch public &&
	 git rev-parse --verify refs/heads/renamed &&
	 test_must_fail git rev-parse --verify refs/heads/renamed2
	)
'

test_expect_success 'add alt && prune' '
	(mkdir alttst &&
	 cd alttst &&
	 git init &&
	 git remote add -f origin ../one &&
	 git config remote.alt.url ../one &&
	 git config remote.alt.fetch "+refs/heads/*:refs/remotes/origin/*") &&
	(cd one &&
	 git branch -m side side2) &&
	(cd alttst &&
	 git rev-parse --verify refs/remotes/origin/side &&
	 test_must_fail git rev-parse --verify refs/remotes/origin/side2 &&
	 git fetch alt &&
	 git remote prune alt &&
	 test_must_fail git rev-parse --verify refs/remotes/origin/side &&
	 git rev-parse --verify refs/remotes/origin/side2)
'

cat >test/expect <<\EOF
some-tag
EOF

test_expect_success 'add with reachable tags (default)' '
	(cd one &&
	 >foobar &&
	 git add foobar &&
	 git commit -m "Foobar" &&
	 git tag -a -m "Foobar tag" foobar-tag &&
	 git reset --hard HEAD~1 &&
	 git tag -a -m "Some tag" some-tag) &&
	(mkdir add-tags &&
	 cd add-tags &&
	 git init &&
	 git remote add -f origin ../one &&
	 git tag -l some-tag >../test/output &&
	 git tag -l foobar-tag >>../test/output &&
	 test_must_fail git config remote.origin.tagopt) &&
	test_cmp test/expect test/output
'

cat >test/expect <<\EOF
some-tag
foobar-tag
--tags
EOF

test_expect_success 'add --tags' '
	(rm -rf add-tags &&
	 mkdir add-tags &&
	 cd add-tags &&
	 git init &&
	 git remote add -f --tags origin ../one &&
	 git tag -l some-tag >../test/output &&
	 git tag -l foobar-tag >>../test/output &&
	 git config remote.origin.tagopt >>../test/output) &&
	test_cmp test/expect test/output
'

cat >test/expect <<\EOF
--no-tags
EOF

test_expect_success 'add --no-tags' '
	(rm -rf add-tags &&
	 mkdir add-no-tags &&
	 cd add-no-tags &&
	 git init &&
	 git remote add -f --no-tags origin ../one &&
	 git tag -l some-tag >../test/output &&
	 git tag -l foobar-tag >../test/output &&
	 git config remote.origin.tagopt >>../test/output) &&
	(cd one &&
	 git tag -d some-tag foobar-tag) &&
	test_cmp test/expect test/output
'

test_expect_success 'reject --no-no-tags' '
	(cd add-no-tags &&
	 test_must_fail git remote add -f --no-no-tags neworigin ../one)
'

cat > one/expect << EOF
  apis/master
  apis/side
  drosophila/another
  drosophila/master
  drosophila/side
EOF

test_expect_success 'update' '

	(cd one &&
	 git remote add drosophila ../two &&
	 git remote add apis ../mirror &&
	 git remote update &&
	 git branch -r > output &&
	 test_cmp expect output)

'

cat > one/expect << EOF
  drosophila/another
  drosophila/master
  drosophila/side
  manduca/master
  manduca/side
  megaloprepus/master
  megaloprepus/side
EOF

test_expect_success 'update with arguments' '

	(cd one &&
	 for b in $(git branch -r)
	 do
		git branch -r -d $b || break
	 done &&
	 git remote add manduca ../mirror &&
	 git remote add megaloprepus ../mirror &&
	 git config remotes.phobaeticus "drosophila megaloprepus" &&
	 git config remotes.titanus manduca &&
	 git remote update phobaeticus titanus &&
	 git branch -r > output &&
	 test_cmp expect output)

'

test_expect_success 'update --prune' '

	(cd one &&
	 git branch -m side2 side3) &&
	(cd test &&
	 git remote update --prune &&
	 (cd ../one && git branch -m side3 side2) &&
	 git rev-parse refs/remotes/origin/side3 &&
	 test_must_fail git rev-parse refs/remotes/origin/side2)
'

cat > one/expect << EOF
  apis/master
  apis/side
  manduca/master
  manduca/side
  megaloprepus/master
  megaloprepus/side
EOF

test_expect_success 'update default' '

	(cd one &&
	 for b in $(git branch -r)
	 do
		git branch -r -d $b || break
	 done &&
	 git config remote.drosophila.skipDefaultUpdate true &&
	 git remote update default &&
	 git branch -r > output &&
	 test_cmp expect output)

'

cat > one/expect << EOF
  drosophila/another
  drosophila/master
  drosophila/side
EOF

test_expect_success 'update default (overridden, with funny whitespace)' '

	(cd one &&
	 for b in $(git branch -r)
	 do
		git branch -r -d $b || break
	 done &&
	 git config remotes.default "$(printf "\t drosophila  \n")" &&
	 git remote update default &&
	 git branch -r > output &&
	 test_cmp expect output)

'

test_expect_success 'update (with remotes.default defined)' '

	(cd one &&
	 for b in $(git branch -r)
	 do
		git branch -r -d $b || break
	 done &&
	 git config remotes.default "drosophila" &&
	 git remote update &&
	 git branch -r > output &&
	 test_cmp expect output)

'

test_expect_success '"remote show" does not show symbolic refs' '

	git clone one three &&
	(cd three &&
	 git remote show origin > output &&
	 ! grep "^ *HEAD$" < output &&
	 ! grep -i stale < output)

'

test_expect_success 'reject adding remote with an invalid name' '

	test_must_fail git remote add some:url desired-name

'

# The first three test if the tracking branches are properly renamed,
# the last two ones check if the config is updated.

test_expect_success 'rename a remote' '

	git clone one four &&
	(cd four &&
	 git remote rename origin upstream &&
	 rmdir .git/refs/remotes/origin &&
	 test "$(git symbolic-ref refs/remotes/upstream/HEAD)" = "refs/remotes/upstream/master" &&
	 test "$(git rev-parse upstream/master)" = "$(git rev-parse master)" &&
	 test "$(git config remote.upstream.fetch)" = "+refs/heads/*:refs/remotes/upstream/*" &&
	 test "$(git config branch.master.remote)" = "upstream")

'

cat > remotes_origin << EOF
URL: $(pwd)/one
Push: refs/heads/master:refs/heads/upstream
Pull: refs/heads/master:refs/heads/origin
EOF

test_expect_success 'migrate a remote from named file in $GIT_DIR/remotes' '
	git clone one five &&
	origin_url=$(pwd)/one &&
	(cd five &&
	 git remote rm origin &&
	 mkdir -p .git/remotes &&
	 cat ../remotes_origin > .git/remotes/origin &&
	 git remote rename origin origin &&
	 ! test -f .git/remotes/origin &&
	 test "$(git config remote.origin.url)" = "$origin_url" &&
	 test "$(git config remote.origin.push)" = "refs/heads/master:refs/heads/upstream" &&
	 test "$(git config remote.origin.fetch)" = "refs/heads/master:refs/heads/origin")
'

test_expect_success 'migrate a remote from named file in $GIT_DIR/branches' '
	git clone one six &&
	origin_url=$(pwd)/one &&
	(cd six &&
	 git remote rm origin &&
	 echo "$origin_url" > .git/branches/origin &&
	 git remote rename origin origin &&
	 ! test -f .git/branches/origin &&
	 test "$(git config remote.origin.url)" = "$origin_url" &&
	 test "$(git config remote.origin.fetch)" = "refs/heads/master:refs/heads/origin")
'

test_expect_success 'remote prune to cause a dangling symref' '
	git clone one seven &&
	(
		cd one &&
		git checkout side2 &&
		git branch -D master
	) &&
	(
		cd seven &&
		git remote prune origin
	) >err 2>&1 &&
	grep "has become dangling" err &&

	: And the dangling symref will not cause other annoying errors &&
	(
		cd seven &&
		git branch -a
	) 2>err &&
	! grep "points nowhere" err &&
	(
		cd seven &&
		test_must_fail git branch nomore origin
	) 2>err &&
	grep "dangling symref" err
'

test_expect_success 'show empty remote' '

	test_create_repo empty &&
	git clone empty empty-clone &&
	(
		cd empty-clone &&
		git remote show origin
	)
'

test_expect_success 'remote set-branches requires a remote' '
	test_must_fail git remote set-branches &&
	test_must_fail git remote set-branches --add
'

test_expect_success 'remote set-branches' '
	echo "+refs/heads/*:refs/remotes/scratch/*" >expect.initial &&
	sort <<-\EOF >expect.add &&
	+refs/heads/*:refs/remotes/scratch/*
	+refs/heads/other:refs/remotes/scratch/other
	EOF
	sort <<-\EOF >expect.replace &&
	+refs/heads/maint:refs/remotes/scratch/maint
	+refs/heads/master:refs/remotes/scratch/master
	+refs/heads/next:refs/remotes/scratch/next
	EOF
	sort <<-\EOF >expect.add-two &&
	+refs/heads/maint:refs/remotes/scratch/maint
	+refs/heads/master:refs/remotes/scratch/master
	+refs/heads/next:refs/remotes/scratch/next
	+refs/heads/pu:refs/remotes/scratch/pu
	+refs/heads/t/topic:refs/remotes/scratch/t/topic
	EOF
	sort <<-\EOF >expect.setup-ffonly &&
	refs/heads/master:refs/remotes/scratch/master
	+refs/heads/next:refs/remotes/scratch/next
	EOF
	sort <<-\EOF >expect.respect-ffonly &&
	refs/heads/master:refs/remotes/scratch/master
	+refs/heads/next:refs/remotes/scratch/next
	+refs/heads/pu:refs/remotes/scratch/pu
	EOF

	git clone .git/ setbranches &&
	(
		cd setbranches &&
		git remote rename origin scratch &&
		git config --get-all remote.scratch.fetch >config-result &&
		sort <config-result >../actual.initial &&

		git remote set-branches scratch --add other &&
		git config --get-all remote.scratch.fetch >config-result &&
		sort <config-result >../actual.add &&

		git remote set-branches scratch maint master next &&
		git config --get-all remote.scratch.fetch >config-result &&
		sort <config-result >../actual.replace &&

		git remote set-branches --add scratch pu t/topic &&
		git config --get-all remote.scratch.fetch >config-result &&
		sort <config-result >../actual.add-two &&

		git config --unset-all remote.scratch.fetch &&
		git config remote.scratch.fetch \
			refs/heads/master:refs/remotes/scratch/master &&
		git config --add remote.scratch.fetch \
			+refs/heads/next:refs/remotes/scratch/next &&
		git config --get-all remote.scratch.fetch >config-result &&
		sort <config-result >../actual.setup-ffonly &&

		git remote set-branches --add scratch pu &&
		git config --get-all remote.scratch.fetch >config-result &&
		sort <config-result >../actual.respect-ffonly
	) &&
	test_cmp expect.initial actual.initial &&
	test_cmp expect.add actual.add &&
	test_cmp expect.replace actual.replace &&
	test_cmp expect.add-two actual.add-two &&
	test_cmp expect.setup-ffonly actual.setup-ffonly &&
	test_cmp expect.respect-ffonly actual.respect-ffonly
'

test_expect_success 'remote set-branches with --mirror' '
	echo "+refs/*:refs/*" >expect.initial &&
	echo "+refs/heads/master:refs/heads/master" >expect.replace &&
	git clone --mirror .git/ setbranches-mirror &&
	(
		cd setbranches-mirror &&
		git remote rename origin scratch &&
		git config --get-all remote.scratch.fetch >../actual.initial &&

		git remote set-branches scratch heads/master &&
		git config --get-all remote.scratch.fetch >../actual.replace
	) &&
	test_cmp expect.initial actual.initial &&
	test_cmp expect.replace actual.replace
'

test_expect_success 'new remote' '
	git remote add someremote foo &&
	echo foo >expect &&
	git config --get-all remote.someremote.url >actual &&
	cmp expect actual
'

test_expect_success 'remote set-url bar' '
	git remote set-url someremote bar &&
	echo bar >expect &&
	git config --get-all remote.someremote.url >actual &&
	cmp expect actual
'

test_expect_success 'remote set-url baz bar' '
	git remote set-url someremote baz bar &&
	echo baz >expect &&
	git config --get-all remote.someremote.url >actual &&
	cmp expect actual
'

test_expect_success 'remote set-url zot bar' '
	test_must_fail git remote set-url someremote zot bar &&
	echo baz >expect &&
	git config --get-all remote.someremote.url >actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --push zot baz' '
	test_must_fail git remote set-url --push someremote zot baz &&
	echo "YYY" >expect &&
	echo baz >>expect &&
	test_must_fail git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --push zot' '
	git remote set-url --push someremote zot &&
	echo zot >expect &&
	echo "YYY" >>expect &&
	echo baz >>expect &&
	git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --push qux zot' '
	git remote set-url --push someremote qux zot &&
	echo qux >expect &&
	echo "YYY" >>expect &&
	echo baz >>expect &&
	git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --push foo qu+x' '
	git remote set-url --push someremote foo qu+x &&
	echo foo >expect &&
	echo "YYY" >>expect &&
	echo baz >>expect &&
	git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --push --add aaa' '
	git remote set-url --push --add someremote aaa &&
	echo foo >expect &&
	echo aaa >>expect &&
	echo "YYY" >>expect &&
	echo baz >>expect &&
	git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --push bar aaa' '
	git remote set-url --push someremote bar aaa &&
	echo foo >expect &&
	echo bar >>expect &&
	echo "YYY" >>expect &&
	echo baz >>expect &&
	git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --push --delete bar' '
	git remote set-url --push --delete someremote bar &&
	echo foo >expect &&
	echo "YYY" >>expect &&
	echo baz >>expect &&
	git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --push --delete foo' '
	git remote set-url --push --delete someremote foo &&
	echo "YYY" >expect &&
	echo baz >>expect &&
	test_must_fail git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --add bbb' '
	git remote set-url --add someremote bbb &&
	echo "YYY" >expect &&
	echo baz >>expect &&
	echo bbb >>expect &&
	test_must_fail git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --delete .*' '
	test_must_fail git remote set-url --delete someremote .\* &&
	echo "YYY" >expect &&
	echo baz >>expect &&
	echo bbb >>expect &&
	test_must_fail git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --delete bbb' '
	git remote set-url --delete someremote bbb &&
	echo "YYY" >expect &&
	echo baz >>expect &&
	test_must_fail git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --delete baz' '
	test_must_fail git remote set-url --delete someremote baz &&
	echo "YYY" >expect &&
	echo baz >>expect &&
	test_must_fail git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --add ccc' '
	git remote set-url --add someremote ccc &&
	echo "YYY" >expect &&
	echo baz >>expect &&
	echo ccc >>expect &&
	test_must_fail git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_expect_success 'remote set-url --delete baz' '
	git remote set-url --delete someremote baz &&
	echo "YYY" >expect &&
	echo ccc >>expect &&
	test_must_fail git config --get-all remote.someremote.pushurl >actual &&
	echo "YYY" >>actual &&
	git config --get-all remote.someremote.url >>actual &&
	cmp expect actual
'

test_done
