#!/bin/sh
#
# Copyright (c) 2007 Jakub Narebski
#

test_description='gitweb as standalone script (basic tests).

This test runs gitweb (git web interface) as CGI script from
commandline, and checks that it would not write any errors
or warnings to log.'


. ./gitweb-lib.sh

# ----------------------------------------------------------------------
# no commits (empty, just initialized repository)

test_expect_success \
	'no commits: projects_list (implicit)' \
	'gitweb_run'
test_debug 'cat gitweb.log'

test_expect_success \
	'no commits: projects_index' \
	'gitweb_run "a=project_index"'
test_debug 'cat gitweb.log'

test_expect_success \
	'no commits: .git summary (implicit)' \
	'gitweb_run "p=.git"'
test_debug 'cat gitweb.log'

test_expect_success \
	'no commits: .git commit (implicit HEAD)' \
	'gitweb_run "p=.git;a=commit"'
test_debug 'cat gitweb.log'

test_expect_success \
	'no commits: .git commitdiff (implicit HEAD)' \
	'gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'no commits: .git tree (implicit HEAD)' \
	'gitweb_run "p=.git;a=tree"'
test_debug 'cat gitweb.log'

test_expect_success \
	'no commits: .git heads' \
	'gitweb_run "p=.git;a=heads"'
test_debug 'cat gitweb.log'

test_expect_success \
	'no commits: .git tags' \
	'gitweb_run "p=.git;a=tags"'
test_debug 'cat gitweb.log'


# ----------------------------------------------------------------------
# initial commit

test_expect_success \
	'Make initial commit' \
	'echo "Not an empty file." > file &&
	 git add file &&
	 git commit -a -m "Initial commit." &&
	 git branch b'

test_expect_success \
	'projects_list (implicit)' \
	'gitweb_run'
test_debug 'cat gitweb.log'

test_expect_success \
	'projects_index' \
	'gitweb_run "a=project_index"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git summary (implicit)' \
	'gitweb_run "p=.git"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git commit (implicit HEAD)' \
	'gitweb_run "p=.git;a=commit"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git commitdiff (implicit HEAD, root commit)' \
	'gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git commitdiff_plain (implicit HEAD, root commit)' \
	'gitweb_run "p=.git;a=commitdiff_plain"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git commit (HEAD)' \
	'gitweb_run "p=.git;a=commit;h=HEAD"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git tree (implicit HEAD)' \
	'gitweb_run "p=.git;a=tree"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git blob (file)' \
	'gitweb_run "p=.git;a=blob;f=file"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git blob_plain (file)' \
	'gitweb_run "p=.git;a=blob_plain;f=file"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# nonexistent objects

test_expect_success \
	'.git commit (non-existent)' \
	'gitweb_run "p=.git;a=commit;h=non-existent"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git commitdiff (non-existent)' \
	'gitweb_run "p=.git;a=commitdiff;h=non-existent"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git commitdiff (non-existent vs HEAD)' \
	'gitweb_run "p=.git;a=commitdiff;hp=non-existent;h=HEAD"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git tree (0000000000000000000000000000000000000000)' \
	'gitweb_run "p=.git;a=tree;h=0000000000000000000000000000000000000000"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git tag (0000000000000000000000000000000000000000)' \
	'gitweb_run "p=.git;a=tag;h=0000000000000000000000000000000000000000"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git blob (non-existent)' \
	'gitweb_run "p=.git;a=blob;f=non-existent"'
test_debug 'cat gitweb.log'

test_expect_success \
	'.git blob_plain (non-existent)' \
	'gitweb_run "p=.git;a=blob_plain;f=non-existent"'
test_debug 'cat gitweb.log'


# ----------------------------------------------------------------------
# commitdiff testing (implicit, one implicit tree-ish)

test_expect_success \
	'commitdiff(0): root' \
	'gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): file added' \
	'echo "New file" > new_file &&
	 git add new_file &&
	 git commit -a -m "File added." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): mode change' \
	'test_chmod +x new_file &&
	 git commit -a -m "Mode changed." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): file renamed' \
	'git mv new_file renamed_file &&
	 git commit -a -m "File renamed." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success SYMLINKS \
	'commitdiff(0): file to symlink' \
	'rm renamed_file &&
	 ln -s file renamed_file &&
	 git commit -a -m "File to symlink." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): file deleted' \
	'git rm renamed_file &&
	 rm -f renamed_file &&
	 git commit -a -m "File removed." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): file copied / new file' \
	'cp file file2 &&
	 git add file2 &&
	 git commit -a -m "File copied." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): mode change and modified' \
	'echo "New line" >> file2 &&
	 test_chmod +x file2 &&
	 git commit -a -m "Mode change and modification." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): renamed and modified' \
	'cat >file2<<EOF &&
Dominus regit me,
et nihil mihi deerit.
In loco pascuae ibi me collocavit,
super aquam refectionis educavit me;
animam meam convertit,
deduxit me super semitas jusitiae,
propter nomen suum.
EOF
	 git commit -a -m "File added." &&
	 git mv file2 file3 &&
	 echo "Propter nomen suum." >> file3 &&
	 git commit -a -m "File rename and modification." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): renamed, mode change and modified' \
	'git mv file3 file2 &&
	 echo "Propter nomen suum." >> file2 &&
	 test_chmod +x file2 &&
	 git commit -a -m "File rename, mode change and modification." &&
	 gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# commitdiff testing (taken from t4114-apply-typechange.sh)

test_expect_success SYMLINKS 'setup typechange commits' '
	echo "hello world" > foo &&
	echo "hi planet" > bar &&
	git update-index --add foo bar &&
	git commit -m initial &&
	git branch initial &&
	rm -f foo &&
	ln -s bar foo &&
	git update-index foo &&
	git commit -m "foo symlinked to bar" &&
	git branch foo-symlinked-to-bar &&
	rm -f foo &&
	echo "how far is the sun?" > foo &&
	git update-index foo &&
	git commit -m "foo back to file" &&
	git branch foo-back-to-file &&
	rm -f foo &&
	git update-index --remove foo &&
	mkdir foo &&
	echo "if only I knew" > foo/baz &&
	git update-index --add foo/baz &&
	git commit -m "foo becomes a directory" &&
	git branch "foo-becomes-a-directory" &&
	echo "hello world" > foo/baz &&
	git update-index foo/baz &&
	git commit -m "foo/baz is the original foo" &&
	git branch foo-baz-renamed-from-foo
	'

test_expect_success \
	'commitdiff(2): file renamed from foo to foo/baz' \
	'gitweb_run "p=.git;a=commitdiff;hp=initial;h=foo-baz-renamed-from-foo"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(2): file renamed from foo/baz to foo' \
	'gitweb_run "p=.git;a=commitdiff;hp=foo-baz-renamed-from-foo;h=initial"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(2): directory becomes file' \
	'gitweb_run "p=.git;a=commitdiff;hp=foo-becomes-a-directory;h=initial"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(2): file becomes directory' \
	'gitweb_run "p=.git;a=commitdiff;hp=initial;h=foo-becomes-a-directory"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(2): file becomes symlink' \
	'gitweb_run "p=.git;a=commitdiff;hp=initial;h=foo-symlinked-to-bar"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(2): symlink becomes file' \
	'gitweb_run "p=.git;a=commitdiff;hp=foo-symlinked-to-bar;h=foo-back-to-file"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(2): symlink becomes directory' \
	'gitweb_run "p=.git;a=commitdiff;hp=foo-symlinked-to-bar;h=foo-becomes-a-directory"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(2): directory becomes symlink' \
	'gitweb_run "p=.git;a=commitdiff;hp=foo-becomes-a-directory;h=foo-symlinked-to-bar"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# commit, commitdiff: merge, large
test_expect_success \
	'Create a merge' \
	'git checkout b &&
	 echo "Branch" >> b &&
	 git add b &&
	 git commit -a -m "On branch" &&
	 git checkout master &&
	 git pull . b'

test_expect_success \
	'commit(0): merge commit' \
	'gitweb_run "p=.git;a=commit"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(0): merge commit' \
	'gitweb_run "p=.git;a=commitdiff"'
test_debug 'cat gitweb.log'

test_expect_success \
	'Prepare large commit' \
	'git checkout b &&
	 echo "To be changed" > 01-change &&
	 echo "To be renamed" > 02-pure-rename-from &&
	 echo "To be deleted" > 03-delete &&
	 echo "To be renamed and changed" > 04-rename-from &&
	 echo "To have mode changed" > 05-mode-change &&
	 echo "File to symlink" > 06-file-or-symlink &&
	 echo "To be changed and have mode changed" > 07-change-mode-change	&&
	 git add 0* &&
	 git commit -a -m "Prepare large commit" &&
	 echo "Changed" > 01-change &&
	 git mv 02-pure-rename-from 02-pure-rename-to &&
	 git rm 03-delete && rm -f 03-delete &&
	 echo "A new file" > 03-new &&
	 git add 03-new &&
	 git mv 04-rename-from 04-rename-to &&
	 echo "Changed" >> 04-rename-to &&
	 test_chmod +x 05-mode-change &&
	 rm -f 06-file-or-symlink &&
	 if test_have_prereq SYMLINKS; then
		ln -s 01-change 06-file-or-symlink
	 else
		printf %s 01-change > 06-file-or-symlink
	 fi &&
	 echo "Changed and have mode changed" > 07-change-mode-change	&&
	 test_chmod +x 07-change-mode-change &&
	 git commit -a -m "Large commit" &&
	 git checkout master'

test_expect_success \
	'commit(1): large commit' \
	'gitweb_run "p=.git;a=commit;h=b"'
test_debug 'cat gitweb.log'

test_expect_success \
	'commitdiff(1): large commit' \
	'gitweb_run "p=.git;a=commitdiff;h=b"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# tags testing

test_expect_success \
	'tags: list of different types of tags' \
	'git checkout master &&
	 git tag -a -m "Tag commit object" tag-commit HEAD &&
	 git tag -a -m "" tag-commit-nomessage HEAD &&
	 git tag -a -m "Tag tag object" tag-tag tag-commit &&
	 git tag -a -m "Tag tree object" tag-tree HEAD^{tree} &&
	 git tag -a -m "Tag blob object" tag-blob HEAD:file &&
	 git tag lightweight/tag-commit HEAD &&
	 git tag lightweight/tag-tag tag-commit &&
	 git tag lightweight/tag-tree HEAD^{tree} &&
	 git tag lightweight/tag-blob HEAD:file &&
	 gitweb_run "p=.git;a=tags"'
test_debug 'cat gitweb.log'

test_expect_success \
	'tag: Tag to commit object' \
	'gitweb_run "p=.git;a=tag;h=tag-commit"'
test_debug 'cat gitweb.log'

test_expect_success \
	'tag: on lightweight tag (invalid)' \
	'gitweb_run "p=.git;a=tag;h=lightweight/tag-commit"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# logs

test_expect_success \
	'logs: log (implicit HEAD)' \
	'gitweb_run "p=.git;a=log"'
test_debug 'cat gitweb.log'

test_expect_success \
	'logs: shortlog (implicit HEAD)' \
	'gitweb_run "p=.git;a=shortlog"'
test_debug 'cat gitweb.log'

test_expect_success \
	'logs: history (implicit HEAD, file)' \
	'gitweb_run "p=.git;a=history;f=file"'
test_debug 'cat gitweb.log'

test_expect_success \
	'logs: history (implicit HEAD, non-existent file)' \
	'gitweb_run "p=.git;a=history;f=non-existent"'
test_debug 'cat gitweb.log'

test_expect_success \
	'logs: history (implicit HEAD, deleted file)' \
	'git checkout master &&
	 echo "to be deleted" > deleted_file &&
	 git add deleted_file &&
	 git commit -m "Add file to be deleted" &&
	 git rm deleted_file &&
	 git commit -m "Delete file" &&
	 gitweb_run "p=.git;a=history;f=deleted_file"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# path_info links
test_expect_success \
	'path_info: project' \
	'gitweb_run "" "/.git"'
test_debug 'cat gitweb.log'

test_expect_success \
	'path_info: project/branch' \
	'gitweb_run "" "/.git/b"'
test_debug 'cat gitweb.log'

test_expect_success \
	'path_info: project/branch:file' \
	'gitweb_run "" "/.git/master:file"'
test_debug 'cat gitweb.log'

test_expect_success \
	'path_info: project/branch:dir/' \
	'gitweb_run "" "/.git/master:foo/"'
test_debug 'cat gitweb.log'

test_expect_success \
	'path_info: project/branch:file (non-existent)' \
	'gitweb_run "" "/.git/master:non-existent"'
test_debug 'cat gitweb.log'

test_expect_success \
	'path_info: project/branch:dir/ (non-existent)' \
	'gitweb_run "" "/.git/master:non-existent/"'
test_debug 'cat gitweb.log'


test_expect_success \
	'path_info: project/branch:/file' \
	'gitweb_run "" "/.git/master:/file"'
test_debug 'cat gitweb.log'

test_expect_success \
	'path_info: project/:/file (implicit HEAD)' \
	'gitweb_run "" "/.git/:/file"'
test_debug 'cat gitweb.log'

test_expect_success \
	'path_info: project/:/ (implicit HEAD, top tree)' \
	'gitweb_run "" "/.git/:/"'
test_debug 'cat gitweb.log'


# ----------------------------------------------------------------------
# feed generation

test_expect_success \
	'feeds: OPML' \
	'gitweb_run "a=opml"'
test_debug 'cat gitweb.log'

test_expect_success \
	'feed: RSS' \
	'gitweb_run "p=.git;a=rss"'
test_debug 'cat gitweb.log'

test_expect_success \
	'feed: Atom' \
	'gitweb_run "p=.git;a=atom"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# encoding/decoding

test_expect_success \
	'encode(commit): utf8' \
	'. "$TEST_DIRECTORY"/t3901-utf8.txt &&
	 echo "UTF-8" >> file &&
	 git add file &&
	 git commit -F "$TEST_DIRECTORY"/t3900/1-UTF-8.txt &&
	 gitweb_run "p=.git;a=commit"'
test_debug 'cat gitweb.log'

test_expect_success \
	'encode(commit): iso-8859-1' \
	'. "$TEST_DIRECTORY"/t3901-8859-1.txt &&
	 echo "ISO-8859-1" >> file &&
	 git add file &&
	 git config i18n.commitencoding ISO-8859-1 &&
	 git commit -F "$TEST_DIRECTORY"/t3900/ISO8859-1.txt &&
	 git config --unset i18n.commitencoding &&
	 gitweb_run "p=.git;a=commit"'
test_debug 'cat gitweb.log'

test_expect_success \
	'encode(log): utf-8 and iso-8859-1' \
	'gitweb_run "p=.git;a=log"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# extra options

test_expect_success \
	'opt: log --no-merges' \
	'gitweb_run "p=.git;a=log;opt=--no-merges"'
test_debug 'cat gitweb.log'

test_expect_success \
	'opt: atom --no-merges' \
	'gitweb_run "p=.git;a=log;opt=--no-merges"'
test_debug 'cat gitweb.log'

test_expect_success \
	'opt: "file" history --no-merges' \
	'gitweb_run "p=.git;a=history;f=file;opt=--no-merges"'
test_debug 'cat gitweb.log'

test_expect_success \
	'opt: log --no-such-option (invalid option)' \
	'gitweb_run "p=.git;a=log;opt=--no-such-option"'
test_debug 'cat gitweb.log'

test_expect_success \
	'opt: tree --no-merges (invalid option for action)' \
	'gitweb_run "p=.git;a=tree;opt=--no-merges"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# testing config_to_multi / cloneurl

test_expect_success \
       'URL: no project URLs, no base URL' \
       'gitweb_run "p=.git;a=summary"'
test_debug 'cat gitweb.log'

test_expect_success \
       'URL: project URLs via gitweb.url' \
       'git config --add gitweb.url git://example.com/git/trash.git &&
        git config --add gitweb.url http://example.com/git/trash.git &&
        gitweb_run "p=.git;a=summary"'
test_debug 'cat gitweb.log'

cat >.git/cloneurl <<\EOF
git://example.com/git/trash.git
http://example.com/git/trash.git
EOF

test_expect_success \
       'URL: project URLs via cloneurl file' \
       'gitweb_run "p=.git;a=summary"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# gitweb config and repo config

cat >>gitweb_config.perl <<\EOF

# turn on override for each overridable feature
foreach my $key (keys %feature) {
	if ($feature{$key}{'sub'}) {
		$feature{$key}{'override'} = 1;
	}
}
EOF

test_expect_success \
	'config override: projects list (implicit)' \
	'gitweb_run'
test_debug 'cat gitweb.log'

test_expect_success \
	'config override: tree view, features not overridden in repo config' \
	'gitweb_run "p=.git;a=tree"'
test_debug 'cat gitweb.log'

test_expect_success \
	'config override: tree view, features disabled in repo config' \
	'git config gitweb.blame no &&
	 git config gitweb.snapshot none &&
	 git config gitweb.avatar gravatar &&
	 gitweb_run "p=.git;a=tree"'
test_debug 'cat gitweb.log'

test_expect_success \
	'config override: tree view, features enabled in repo config (1)' \
	'git config gitweb.blame yes &&
	 git config gitweb.snapshot "zip,tgz, tbz2" &&
	 gitweb_run "p=.git;a=tree"'
test_debug 'cat gitweb.log'

cat >.git/config <<\EOF
# testing noval and alternate separator
[gitweb]
	blame
	snapshot = zip tgz
EOF
test_expect_success \
	'config override: tree view, features enabled in repo config (2)' \
	'gitweb_run "p=.git;a=tree"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# non-ASCII in README.html

test_expect_success \
	'README.html with non-ASCII characters (utf-8)' \
	'echo "<b>UTF-8 example:</b><br />" > .git/README.html &&
	 cat "$TEST_DIRECTORY"/t3900/1-UTF-8.txt >> .git/README.html &&
	 gitweb_run "p=.git;a=summary"'
test_debug 'cat gitweb.log'

# ----------------------------------------------------------------------
# syntax highlighting


highlight --version >/dev/null 2>&1
if [ $? -eq 127 ]; then
	say "Skipping syntax highlighting test, because 'highlight' was not found"
else
	test_set_prereq HIGHLIGHT
	cat >>gitweb_config.perl <<-\EOF
	our $highlight_bin = "highlight";
	$feature{'highlight'}{'override'} = 1;
	EOF
fi

test_expect_success HIGHLIGHT \
	'syntax highlighting (no highlight, unknown syntax)' \
	'git config gitweb.highlight yes &&
	 gitweb_run "p=.git;a=blob;f=file"'
test_debug 'cat gitweb.log'

test_expect_success HIGHLIGHT \
	'syntax highlighting (highlighted, shell script)' \
	'git config gitweb.highlight yes &&
	 echo "#!/usr/bin/sh" > test.sh &&
	 git add test.sh &&
	 git commit -m "Add test.sh" &&
	 gitweb_run "p=.git;a=blob;f=test.sh"'
test_debug 'cat gitweb.log'

test_done
