#!/bin/sh
#
# Copyright (c) 2010 Matthieu Moy
#

test_description='Test repository with default ACL'

# Create the test repo with restrictive umask
# => this must come before . ./test-lib.sh
umask 077

. ./test-lib.sh

# We need an arbitrary other user give permission to using ACLs. root
# is a good candidate: exists on all unices, and it has permission
# anyway, so we don't create a security hole running the testsuite.

setfacl_out="$(setfacl -m u:root:rwx . 2>&1)"
setfacl_ret=$?

if test $setfacl_ret != 0
then
	say "Unable to use setfacl (output: '$setfacl_out'; return code: '$setfacl_ret')"
else
	test_set_prereq SETFACL
fi

check_perms_and_acl () {
	test -r "$1" &&
	getfacl "$1" > actual &&
	grep -q "user:root:rwx" actual &&
	grep -q "user:${LOGNAME}:rwx" actual &&
	egrep "mask::?r--" actual > /dev/null 2>&1 &&
	grep -q "group::---" actual || false
}

dirs_to_set="./ .git/ .git/objects/ .git/objects/pack/"

test_expect_success SETFACL 'Setup test repo' '
	setfacl -m d:u::rwx,d:g::---,d:o:---,d:m:rwx $dirs_to_set &&
	setfacl -m m:rwx               $dirs_to_set &&
	setfacl -m u:root:rwx          $dirs_to_set &&
	setfacl -m d:u:"$LOGNAME":rwx  $dirs_to_set &&
	setfacl -m d:u:root:rwx        $dirs_to_set &&

	touch file.txt &&
	git add file.txt &&
	git commit -m "init"
'

test_expect_success SETFACL 'Objects creation does not break ACLs with restrictive umask' '
	# SHA1 for empty blob
	check_perms_and_acl .git/objects/e6/9de29bb2d1d6434b8b29ae775ad8c2e48c5391
'

test_expect_success SETFACL 'git gc does not break ACLs with restrictive umask' '
	git gc &&
	check_perms_and_acl .git/objects/pack/*.pack
'

test_done
