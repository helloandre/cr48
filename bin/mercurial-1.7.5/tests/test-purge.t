  $ cat <<EOF >> $HGRCPATH
  > [extensions]
  > purge =
  > EOF

init

  $ hg init t
  $ cd t

setup

  $ echo r1 > r1
  $ hg ci -qAmr1 -d'0 0'
  $ mkdir directory
  $ echo r2 > directory/r2
  $ hg ci -qAmr2 -d'1 0'
  $ echo 'ignored' > .hgignore
  $ hg ci -qAmr3 -d'2 0'

delete an empty directory

  $ mkdir empty_dir
  $ hg purge -p
  empty_dir
  $ hg purge -v
  Removing directory empty_dir
  $ ls
  directory
  r1

delete an untracked directory

  $ mkdir untracked_dir
  $ touch untracked_dir/untracked_file1
  $ touch untracked_dir/untracked_file2
  $ hg purge -p
  untracked_dir/untracked_file1
  untracked_dir/untracked_file2
  $ hg purge -v
  Removing file untracked_dir/untracked_file1
  Removing file untracked_dir/untracked_file2
  Removing directory untracked_dir
  $ ls
  directory
  r1

delete an untracked file

  $ touch untracked_file
  $ touch untracked_file_readonly
  $ python <<EOF
  > import os, stat
  > f= 'untracked_file_readonly'
  > os.chmod(f, stat.S_IMODE(os.stat(f).st_mode) & ~stat.S_IWRITE)
  > EOF
  $ hg purge -p
  untracked_file
  untracked_file_readonly
  $ hg purge -v
  Removing file untracked_file
  Removing file untracked_file_readonly
  $ ls
  directory
  r1

delete an untracked file in a tracked directory

  $ touch directory/untracked_file
  $ hg purge -p
  directory/untracked_file
  $ hg purge -v
  Removing file directory/untracked_file
  $ ls
  directory
  r1

delete nested directories

  $ mkdir -p untracked_directory/nested_directory
  $ hg purge -p
  untracked_directory/nested_directory
  $ hg purge -v
  Removing directory untracked_directory/nested_directory
  Removing directory untracked_directory
  $ ls
  directory
  r1

delete nested directories from a subdir

  $ mkdir -p untracked_directory/nested_directory
  $ cd directory
  $ hg purge -p
  untracked_directory/nested_directory
  $ hg purge -v
  Removing directory untracked_directory/nested_directory
  Removing directory untracked_directory
  $ cd ..
  $ ls
  directory
  r1

delete only part of the tree

  $ mkdir -p untracked_directory/nested_directory
  $ touch directory/untracked_file
  $ cd directory
  $ hg purge -p ../untracked_directory
  untracked_directory/nested_directory
  $ hg purge -v ../untracked_directory
  Removing directory untracked_directory/nested_directory
  Removing directory untracked_directory
  $ cd ..
  $ ls
  directory
  r1
  $ ls directory/untracked_file
  directory/untracked_file
  $ rm directory/untracked_file

skip ignored files if --all not specified

  $ touch ignored
  $ hg purge -p
  $ hg purge -v
  $ ls
  directory
  ignored
  r1
  $ hg purge -p --all
  ignored
  $ hg purge -v --all
  Removing file ignored
  $ ls
  directory
  r1

abort with missing files until we support name mangling filesystems

  $ touch untracked_file
  $ rm r1

hide error messages to avoid changing the output when the text changes

  $ hg purge -p 2> /dev/null
  untracked_file
  $ hg st
  ! r1
  ? untracked_file

  $ hg purge -p
  untracked_file
  $ hg purge -v 2> /dev/null
  Removing file untracked_file
  $ hg st
  ! r1

  $ hg purge -v
  $ hg revert --all --quiet
  $ hg st -a

tracked file in ignored directory (issue621)

  $ echo directory >> .hgignore
  $ hg ci -m 'ignore directory'
  $ touch untracked_file
  $ hg purge -p
  untracked_file
  $ hg purge -v
  Removing file untracked_file

skip excluded files

  $ touch excluded_file
  $ hg purge -p -X excluded_file
  $ hg purge -v -X excluded_file
  $ ls
  directory
  excluded_file
  r1
  $ rm excluded_file

skip files in excluded dirs

  $ mkdir excluded_dir
  $ touch excluded_dir/file
  $ hg purge -p -X excluded_dir
  $ hg purge -v -X excluded_dir
  $ ls
  directory
  excluded_dir
  r1
  $ ls excluded_dir
  file
  $ rm -R excluded_dir

skip excluded empty dirs

  $ mkdir excluded_dir
  $ hg purge -p -X excluded_dir
  $ hg purge -v -X excluded_dir
  $ ls
  directory
  excluded_dir
  r1
  $ rmdir excluded_dir

skip patterns

  $ mkdir .svn
  $ touch .svn/foo
  $ mkdir directory/.svn
  $ touch directory/.svn/foo
  $ hg purge -p -X .svn -X '*/.svn'
  $ hg purge -p -X re:.*.svn
