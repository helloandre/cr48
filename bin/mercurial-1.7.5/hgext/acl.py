# acl.py - changeset access control for mercurial
#
# Copyright 2006 Vadim Gelfer <vadim.gelfer@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

'''hooks for controlling repository access

This hook makes it possible to allow or deny write access to given
branches and paths of a repository when receiving incoming changesets
via pretxnchangegroup and pretxncommit.

The authorization is matched based on the local user name on the
system where the hook runs, and not the committer of the original
changeset (since the latter is merely informative).

The acl hook is best used along with a restricted shell like hgsh,
preventing authenticating users from doing anything other than pushing
or pulling. The hook is not safe to use if users have interactive
shell access, as they can then disable the hook. Nor is it safe if
remote users share an account, because then there is no way to
distinguish them.

The order in which access checks are performed is:

1) Deny  list for branches (section ``acl.deny.branches``)
2) Allow list for branches (section ``acl.allow.branches``)
3) Deny  list for paths    (section ``acl.deny``)
4) Allow list for paths    (section ``acl.allow``)

The allow and deny sections take key-value pairs.

Branch-based Access Control
...........................

Use the ``acl.deny.branches`` and ``acl.allow.branches`` sections to
have branch-based access control. Keys in these sections can be
either:

- a branch name, or
- an asterisk, to match any branch;

The corresponding values can be either:

- a comma-separated list containing users and groups, or
- an asterisk, to match anyone;

Path-based Access Control
.........................

Use the ``acl.deny`` and ``acl.allow`` sections to have path-based
access control. Keys in these sections accept a subtree pattern (with
a glob syntax by default). The corresponding values follow the same
syntax as the other sections above.

Groups
......

Group names must be prefixed with an ``@`` symbol. Specifying a group
name has the same effect as specifying all the users in that group.

You can define group members in the ``acl.groups`` section.
If a group name is not defined there, and Mercurial is running under
a Unix-like system, the list of users will be taken from the OS.
Otherwise, an exception will be raised.

Example Configuration
.....................

::

  [hooks]

  # Use this if you want to check access restrictions at commit time
  pretxncommit.acl = python:hgext.acl.hook

  # Use this if you want to check access restrictions for pull, push,
  # bundle and serve.
  pretxnchangegroup.acl = python:hgext.acl.hook

  [acl]
  # Allow or deny access for incoming changes only if their source is
  # listed here, let them pass otherwise. Source is "serve" for all
  # remote access (http or ssh), "push", "pull" or "bundle" when the
  # related commands are run locally.
  # Default: serve
  sources = serve

  [acl.deny.branches]

  # Everyone is denied to the frozen branch:
  frozen-branch = *

  # A bad user is denied on all branches:
  * = bad-user

  [acl.allow.branches]

  # A few users are allowed on branch-a:
  branch-a = user-1, user-2, user-3

  # Only one user is allowed on branch-b:
  branch-b = user-1

  # The super user is allowed on any branch:
  * = super-user

  # Everyone is allowed on branch-for-tests:
  branch-for-tests = *

  [acl.deny]
  # This list is checked first. If a match is found, acl.allow is not
  # checked. All users are granted access if acl.deny is not present.
  # Format for both lists: glob pattern = user, ..., @group, ...

  # To match everyone, use an asterisk for the user:
  # my/glob/pattern = *

  # user6 will not have write access to any file:
  ** = user6

  # Group "hg-denied" will not have write access to any file:
  ** = @hg-denied

  # Nobody will be able to change "DONT-TOUCH-THIS.txt", despite
  # everyone being able to change all other files. See below.
  src/main/resources/DONT-TOUCH-THIS.txt = *

  [acl.allow]
  # if acl.allow is not present, all users are allowed by default
  # empty acl.allow = no users allowed

  # User "doc_writer" has write access to any file under the "docs"
  # folder:
  docs/** = doc_writer

  # User "jack" and group "designers" have write access to any file
  # under the "images" folder:
  images/** = jack, @designers

  # Everyone (except for "user6" - see acl.deny above) will have write
  # access to any file under the "resources" folder (except for 1
  # file. See acl.deny):
  src/main/resources/** = *

  .hgtags = release_engineer

'''

from mercurial.i18n import _
from mercurial import util, match
import getpass, urllib

def _getusers(ui, group):

    # First, try to use group definition from section [acl.groups]
    hgrcusers = ui.configlist('acl.groups', group)
    if hgrcusers:
        return hgrcusers

    ui.debug('acl: "%s" not defined in [acl.groups]\n' % group)
    # If no users found in group definition, get users from OS-level group
    try:
        return util.groupmembers(group)
    except KeyError:
        raise util.Abort(_("group '%s' is undefined") % group)

def _usermatch(ui, user, usersorgroups):

    if usersorgroups == '*':
        return True

    for ug in usersorgroups.replace(',', ' ').split():
        if user == ug or ug.find('@') == 0 and user in _getusers(ui, ug[1:]):
            return True

    return False

def buildmatch(ui, repo, user, key):
    '''return tuple of (match function, list enabled).'''
    if not ui.has_section(key):
        ui.debug('acl: %s not enabled\n' % key)
        return None

    pats = [pat for pat, users in ui.configitems(key)
            if _usermatch(ui, user, users)]
    ui.debug('acl: %s enabled, %d entries for user %s\n' %
             (key, len(pats), user))

    if not repo:
        if pats:
            return lambda b: '*' in pats or b in pats
        return lambda b: False

    if pats:
        return match.match(repo.root, '', pats)
    return match.exact(repo.root, '', [])


def hook(ui, repo, hooktype, node=None, source=None, **kwargs):
    if hooktype not in ['pretxnchangegroup', 'pretxncommit']:
        raise util.Abort(_('config error - hook type "%s" cannot stop '
                           'incoming changesets nor commits') % hooktype)
    if (hooktype == 'pretxnchangegroup' and
        source not in ui.config('acl', 'sources', 'serve').split()):
        ui.debug('acl: changes have source "%s" - skipping\n' % source)
        return

    user = None
    if source == 'serve' and 'url' in kwargs:
        url = kwargs['url'].split(':')
        if url[0] == 'remote' and url[1].startswith('http'):
            user = urllib.unquote(url[3])

    if user is None:
        user = getpass.getuser()

    cfg = ui.config('acl', 'config')
    if cfg:
        ui.readconfig(cfg, sections = ['acl.groups', 'acl.allow.branches',
        'acl.deny.branches', 'acl.allow', 'acl.deny'])

    allowbranches = buildmatch(ui, None, user, 'acl.allow.branches')
    denybranches = buildmatch(ui, None, user, 'acl.deny.branches')
    allow = buildmatch(ui, repo, user, 'acl.allow')
    deny = buildmatch(ui, repo, user, 'acl.deny')

    for rev in xrange(repo[node], len(repo)):
        ctx = repo[rev]
        branch = ctx.branch()
        if denybranches and denybranches(branch):
            raise util.Abort(_('acl: user "%s" denied on branch "%s"'
                               ' (changeset "%s")')
                               % (user, branch, ctx))
        if allowbranches and not allowbranches(branch):
            raise util.Abort(_('acl: user "%s" not allowed on branch "%s"'
                               ' (changeset "%s")')
                               % (user, branch, ctx))
        ui.debug('acl: branch access granted: "%s" on branch "%s"\n'
        % (ctx, branch))

        for f in ctx.files():
            if deny and deny(f):
                ui.debug('acl: user %s denied on %s\n' % (user, f))
                raise util.Abort(_('acl: access denied for changeset %s') % ctx)
            if allow and not allow(f):
                ui.debug('acl: user %s not allowed on %s\n' % (user, f))
                raise util.Abort(_('acl: access denied for changeset %s') % ctx)
        ui.debug('acl: allowing changeset %s\n' % ctx)
