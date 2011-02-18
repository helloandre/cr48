# mq.py - patch queues for mercurial
#
# Copyright 2005, 2006 Chris Mason <mason@suse.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

'''manage a stack of patches

This extension lets you work with a stack of patches in a Mercurial
repository. It manages two stacks of patches - all known patches, and
applied patches (subset of known patches).

Known patches are represented as patch files in the .hg/patches
directory. Applied patches are both patch files and changesets.

Common tasks (use :hg:`help command` for more details)::

  create new patch                          qnew
  import existing patch                     qimport

  print patch series                        qseries
  print applied patches                     qapplied

  add known patch to applied stack          qpush
  remove patch from applied stack           qpop
  refresh contents of top applied patch     qrefresh

By default, mq will automatically use git patches when required to
avoid losing file mode changes, copy records, binary files or empty
files creations or deletions. This behaviour can be configured with::

  [mq]
  git = auto/keep/yes/no

If set to 'keep', mq will obey the [diff] section configuration while
preserving existing git patches upon qrefresh. If set to 'yes' or
'no', mq will override the [diff] section and always generate git or
regular patches, possibly losing data in the second case.

You will by default be managing a patch queue named "patches". You can
create other, independent patch queues with the :hg:`qqueue` command.
'''

from mercurial.i18n import _
from mercurial.node import bin, hex, short, nullid, nullrev
from mercurial.lock import release
from mercurial import commands, cmdutil, hg, patch, util
from mercurial import repair, extensions, url, error
import os, sys, re, errno, shutil

commands.norepo += " qclone"

# Patch names looks like unix-file names.
# They must be joinable with queue directory and result in the patch path.
normname = util.normpath

class statusentry(object):
    def __init__(self, node, name):
        self.node, self.name = node, name
    def __repr__(self):
        return hex(self.node) + ':' + self.name

class patchheader(object):
    def __init__(self, pf, plainmode=False):
        def eatdiff(lines):
            while lines:
                l = lines[-1]
                if (l.startswith("diff -") or
                    l.startswith("Index:") or
                    l.startswith("===========")):
                    del lines[-1]
                else:
                    break
        def eatempty(lines):
            while lines:
                if not lines[-1].strip():
                    del lines[-1]
                else:
                    break

        message = []
        comments = []
        user = None
        date = None
        parent = None
        format = None
        subject = None
        diffstart = 0

        for line in file(pf):
            line = line.rstrip()
            if (line.startswith('diff --git')
                or (diffstart and line.startswith('+++ '))):
                diffstart = 2
                break
            diffstart = 0 # reset
            if line.startswith("--- "):
                diffstart = 1
                continue
            elif format == "hgpatch":
                # parse values when importing the result of an hg export
                if line.startswith("# User "):
                    user = line[7:]
                elif line.startswith("# Date "):
                    date = line[7:]
                elif line.startswith("# Parent "):
                    parent = line[9:]
                elif not line.startswith("# ") and line:
                    message.append(line)
                    format = None
            elif line == '# HG changeset patch':
                message = []
                format = "hgpatch"
            elif (format != "tagdone" and (line.startswith("Subject: ") or
                                           line.startswith("subject: "))):
                subject = line[9:]
                format = "tag"
            elif (format != "tagdone" and (line.startswith("From: ") or
                                           line.startswith("from: "))):
                user = line[6:]
                format = "tag"
            elif (format != "tagdone" and (line.startswith("Date: ") or
                                           line.startswith("date: "))):
                date = line[6:]
                format = "tag"
            elif format == "tag" and line == "":
                # when looking for tags (subject: from: etc) they
                # end once you find a blank line in the source
                format = "tagdone"
            elif message or line:
                message.append(line)
            comments.append(line)

        eatdiff(message)
        eatdiff(comments)
        eatempty(message)
        eatempty(comments)

        # make sure message isn't empty
        if format and format.startswith("tag") and subject:
            message.insert(0, "")
            message.insert(0, subject)

        self.message = message
        self.comments = comments
        self.user = user
        self.date = date
        self.parent = parent
        self.haspatch = diffstart > 1
        self.plainmode = plainmode

    def setuser(self, user):
        if not self.updateheader(['From: ', '# User '], user):
            try:
                patchheaderat = self.comments.index('# HG changeset patch')
                self.comments.insert(patchheaderat + 1, '# User ' + user)
            except ValueError:
                if self.plainmode or self._hasheader(['Date: ']):
                    self.comments = ['From: ' + user] + self.comments
                else:
                    tmp = ['# HG changeset patch', '# User ' + user, '']
                    self.comments = tmp + self.comments
        self.user = user

    def setdate(self, date):
        if not self.updateheader(['Date: ', '# Date '], date):
            try:
                patchheaderat = self.comments.index('# HG changeset patch')
                self.comments.insert(patchheaderat + 1, '# Date ' + date)
            except ValueError:
                if self.plainmode or self._hasheader(['From: ']):
                    self.comments = ['Date: ' + date] + self.comments
                else:
                    tmp = ['# HG changeset patch', '# Date ' + date, '']
                    self.comments = tmp + self.comments
        self.date = date

    def setparent(self, parent):
        if not self.updateheader(['# Parent '], parent):
            try:
                patchheaderat = self.comments.index('# HG changeset patch')
                self.comments.insert(patchheaderat + 1, '# Parent ' + parent)
            except ValueError:
                pass
        self.parent = parent

    def setmessage(self, message):
        if self.comments:
            self._delmsg()
        self.message = [message]
        self.comments += self.message

    def updateheader(self, prefixes, new):
        '''Update all references to a field in the patch header.
        Return whether the field is present.'''
        res = False
        for prefix in prefixes:
            for i in xrange(len(self.comments)):
                if self.comments[i].startswith(prefix):
                    self.comments[i] = prefix + new
                    res = True
                    break
        return res

    def _hasheader(self, prefixes):
        '''Check if a header starts with any of the given prefixes.'''
        for prefix in prefixes:
            for comment in self.comments:
                if comment.startswith(prefix):
                    return True
        return False

    def __str__(self):
        if not self.comments:
            return ''
        return '\n'.join(self.comments) + '\n\n'

    def _delmsg(self):
        '''Remove existing message, keeping the rest of the comments fields.
        If comments contains 'subject: ', message will prepend
        the field and a blank line.'''
        if self.message:
            subj = 'subject: ' + self.message[0].lower()
            for i in xrange(len(self.comments)):
                if subj == self.comments[i].lower():
                    del self.comments[i]
                    self.message = self.message[2:]
                    break
        ci = 0
        for mi in self.message:
            while mi != self.comments[ci]:
                ci += 1
            del self.comments[ci]

class queue(object):
    def __init__(self, ui, path, patchdir=None):
        self.basepath = path
        try:
            fh = open(os.path.join(path, 'patches.queue'))
            cur = fh.read().rstrip()
            if not cur:
                curpath = os.path.join(path, 'patches')
            else:
                curpath = os.path.join(path, 'patches-' + cur)
        except IOError:
            curpath = os.path.join(path, 'patches')
        self.path = patchdir or curpath
        self.opener = util.opener(self.path)
        self.ui = ui
        self.applied_dirty = 0
        self.series_dirty = 0
        self.added = []
        self.series_path = "series"
        self.status_path = "status"
        self.guards_path = "guards"
        self.active_guards = None
        self.guards_dirty = False
        # Handle mq.git as a bool with extended values
        try:
            gitmode = ui.configbool('mq', 'git', None)
            if gitmode is None:
                raise error.ConfigError()
            self.gitmode = gitmode and 'yes' or 'no'
        except error.ConfigError:
            self.gitmode = ui.config('mq', 'git', 'auto').lower()
        self.plainmode = ui.configbool('mq', 'plain', False)

    @util.propertycache
    def applied(self):
        if os.path.exists(self.join(self.status_path)):
            def parse(l):
                n, name = l.split(':', 1)
                return statusentry(bin(n), name)
            lines = self.opener(self.status_path).read().splitlines()
            return [parse(l) for l in lines]
        return []

    @util.propertycache
    def full_series(self):
        if os.path.exists(self.join(self.series_path)):
            return self.opener(self.series_path).read().splitlines()
        return []

    @util.propertycache
    def series(self):
        self.parse_series()
        return self.series

    @util.propertycache
    def series_guards(self):
        self.parse_series()
        return self.series_guards

    def invalidate(self):
        for a in 'applied full_series series series_guards'.split():
            if a in self.__dict__:
                delattr(self, a)
        self.applied_dirty = 0
        self.series_dirty = 0
        self.guards_dirty = False
        self.active_guards = None

    def diffopts(self, opts={}, patchfn=None):
        diffopts = patch.diffopts(self.ui, opts)
        if self.gitmode == 'auto':
            diffopts.upgrade = True
        elif self.gitmode == 'keep':
            pass
        elif self.gitmode in ('yes', 'no'):
            diffopts.git = self.gitmode == 'yes'
        else:
            raise util.Abort(_('mq.git option can be auto/keep/yes/no'
                               ' got %s') % self.gitmode)
        if patchfn:
            diffopts = self.patchopts(diffopts, patchfn)
        return diffopts

    def patchopts(self, diffopts, *patches):
        """Return a copy of input diff options with git set to true if
        referenced patch is a git patch and should be preserved as such.
        """
        diffopts = diffopts.copy()
        if not diffopts.git and self.gitmode == 'keep':
            for patchfn in patches:
                patchf = self.opener(patchfn, 'r')
                # if the patch was a git patch, refresh it as a git patch
                for line in patchf:
                    if line.startswith('diff --git'):
                        diffopts.git = True
                        break
                patchf.close()
        return diffopts

    def join(self, *p):
        return os.path.join(self.path, *p)

    def find_series(self, patch):
        def matchpatch(l):
            l = l.split('#', 1)[0]
            return l.strip() == patch
        for index, l in enumerate(self.full_series):
            if matchpatch(l):
                return index
        return None

    guard_re = re.compile(r'\s?#([-+][^-+# \t\r\n\f][^# \t\r\n\f]*)')

    def parse_series(self):
        self.series = []
        self.series_guards = []
        for l in self.full_series:
            h = l.find('#')
            if h == -1:
                patch = l
                comment = ''
            elif h == 0:
                continue
            else:
                patch = l[:h]
                comment = l[h:]
            patch = patch.strip()
            if patch:
                if patch in self.series:
                    raise util.Abort(_('%s appears more than once in %s') %
                                     (patch, self.join(self.series_path)))
                self.series.append(patch)
                self.series_guards.append(self.guard_re.findall(comment))

    def check_guard(self, guard):
        if not guard:
            return _('guard cannot be an empty string')
        bad_chars = '# \t\r\n\f'
        first = guard[0]
        if first in '-+':
            return (_('guard %r starts with invalid character: %r') %
                      (guard, first))
        for c in bad_chars:
            if c in guard:
                return _('invalid character in guard %r: %r') % (guard, c)

    def set_active(self, guards):
        for guard in guards:
            bad = self.check_guard(guard)
            if bad:
                raise util.Abort(bad)
        guards = sorted(set(guards))
        self.ui.debug('active guards: %s\n' % ' '.join(guards))
        self.active_guards = guards
        self.guards_dirty = True

    def active(self):
        if self.active_guards is None:
            self.active_guards = []
            try:
                guards = self.opener(self.guards_path).read().split()
            except IOError, err:
                if err.errno != errno.ENOENT:
                    raise
                guards = []
            for i, guard in enumerate(guards):
                bad = self.check_guard(guard)
                if bad:
                    self.ui.warn('%s:%d: %s\n' %
                                 (self.join(self.guards_path), i + 1, bad))
                else:
                    self.active_guards.append(guard)
        return self.active_guards

    def set_guards(self, idx, guards):
        for g in guards:
            if len(g) < 2:
                raise util.Abort(_('guard %r too short') % g)
            if g[0] not in '-+':
                raise util.Abort(_('guard %r starts with invalid char') % g)
            bad = self.check_guard(g[1:])
            if bad:
                raise util.Abort(bad)
        drop = self.guard_re.sub('', self.full_series[idx])
        self.full_series[idx] = drop + ''.join([' #' + g for g in guards])
        self.parse_series()
        self.series_dirty = True

    def pushable(self, idx):
        if isinstance(idx, str):
            idx = self.series.index(idx)
        patchguards = self.series_guards[idx]
        if not patchguards:
            return True, None
        guards = self.active()
        exactneg = [g for g in patchguards if g[0] == '-' and g[1:] in guards]
        if exactneg:
            return False, exactneg[0]
        pos = [g for g in patchguards if g[0] == '+']
        exactpos = [g for g in pos if g[1:] in guards]
        if pos:
            if exactpos:
                return True, exactpos[0]
            return False, pos
        return True, ''

    def explain_pushable(self, idx, all_patches=False):
        write = all_patches and self.ui.write or self.ui.warn
        if all_patches or self.ui.verbose:
            if isinstance(idx, str):
                idx = self.series.index(idx)
            pushable, why = self.pushable(idx)
            if all_patches and pushable:
                if why is None:
                    write(_('allowing %s - no guards in effect\n') %
                          self.series[idx])
                else:
                    if not why:
                        write(_('allowing %s - no matching negative guards\n') %
                              self.series[idx])
                    else:
                        write(_('allowing %s - guarded by %r\n') %
                              (self.series[idx], why))
            if not pushable:
                if why:
                    write(_('skipping %s - guarded by %r\n') %
                          (self.series[idx], why))
                else:
                    write(_('skipping %s - no matching guards\n') %
                          self.series[idx])

    def save_dirty(self):
        def write_list(items, path):
            fp = self.opener(path, 'w')
            for i in items:
                fp.write("%s\n" % i)
            fp.close()
        if self.applied_dirty:
            write_list(map(str, self.applied), self.status_path)
        if self.series_dirty:
            write_list(self.full_series, self.series_path)
        if self.guards_dirty:
            write_list(self.active_guards, self.guards_path)
        if self.added:
            qrepo = self.qrepo()
            if qrepo:
                qrepo[None].add(f for f in self.added if f not in qrepo[None])
            self.added = []

    def removeundo(self, repo):
        undo = repo.sjoin('undo')
        if not os.path.exists(undo):
            return
        try:
            os.unlink(undo)
        except OSError, inst:
            self.ui.warn(_('error removing undo: %s\n') % str(inst))

    def printdiff(self, repo, diffopts, node1, node2=None, files=None,
                  fp=None, changes=None, opts={}):
        stat = opts.get('stat')
        m = cmdutil.match(repo, files, opts)
        cmdutil.diffordiffstat(self.ui, repo, diffopts, node1, node2,  m,
                               changes, stat, fp)

    def mergeone(self, repo, mergeq, head, patch, rev, diffopts):
        # first try just applying the patch
        (err, n) = self.apply(repo, [patch], update_status=False,
                              strict=True, merge=rev)

        if err == 0:
            return (err, n)

        if n is None:
            raise util.Abort(_("apply failed for patch %s") % patch)

        self.ui.warn(_("patch didn't work out, merging %s\n") % patch)

        # apply failed, strip away that rev and merge.
        hg.clean(repo, head)
        self.strip(repo, [n], update=False, backup='strip')

        ctx = repo[rev]
        ret = hg.merge(repo, rev)
        if ret:
            raise util.Abort(_("update returned %d") % ret)
        n = repo.commit(ctx.description(), ctx.user(), force=True)
        if n is None:
            raise util.Abort(_("repo commit failed"))
        try:
            ph = patchheader(mergeq.join(patch), self.plainmode)
        except:
            raise util.Abort(_("unable to read %s") % patch)

        diffopts = self.patchopts(diffopts, patch)
        patchf = self.opener(patch, "w")
        comments = str(ph)
        if comments:
            patchf.write(comments)
        self.printdiff(repo, diffopts, head, n, fp=patchf)
        patchf.close()
        self.removeundo(repo)
        return (0, n)

    def qparents(self, repo, rev=None):
        if rev is None:
            (p1, p2) = repo.dirstate.parents()
            if p2 == nullid:
                return p1
            if not self.applied:
                return None
            return self.applied[-1].node
        p1, p2 = repo.changelog.parents(rev)
        if p2 != nullid and p2 in [x.node for x in self.applied]:
            return p2
        return p1

    def mergepatch(self, repo, mergeq, series, diffopts):
        if not self.applied:
            # each of the patches merged in will have two parents.  This
            # can confuse the qrefresh, qdiff, and strip code because it
            # needs to know which parent is actually in the patch queue.
            # so, we insert a merge marker with only one parent.  This way
            # the first patch in the queue is never a merge patch
            #
            pname = ".hg.patches.merge.marker"
            n = repo.commit('[mq]: merge marker', force=True)
            self.removeundo(repo)
            self.applied.append(statusentry(n, pname))
            self.applied_dirty = 1

        head = self.qparents(repo)

        for patch in series:
            patch = mergeq.lookup(patch, strict=True)
            if not patch:
                self.ui.warn(_("patch %s does not exist\n") % patch)
                return (1, None)
            pushable, reason = self.pushable(patch)
            if not pushable:
                self.explain_pushable(patch, all_patches=True)
                continue
            info = mergeq.isapplied(patch)
            if not info:
                self.ui.warn(_("patch %s is not applied\n") % patch)
                return (1, None)
            rev = info[1]
            err, head = self.mergeone(repo, mergeq, head, patch, rev, diffopts)
            if head:
                self.applied.append(statusentry(head, patch))
                self.applied_dirty = 1
            if err:
                return (err, head)
        self.save_dirty()
        return (0, head)

    def patch(self, repo, patchfile):
        '''Apply patchfile  to the working directory.
        patchfile: name of patch file'''
        files = {}
        try:
            fuzz = patch.patch(patchfile, self.ui, strip=1, cwd=repo.root,
                               files=files, eolmode=None)
        except Exception, inst:
            self.ui.note(str(inst) + '\n')
            if not self.ui.verbose:
                self.ui.warn(_("patch failed, unable to continue (try -v)\n"))
            return (False, files, False)

        return (True, files, fuzz)

    def apply(self, repo, series, list=False, update_status=True,
              strict=False, patchdir=None, merge=None, all_files=None):
        wlock = lock = tr = None
        try:
            wlock = repo.wlock()
            lock = repo.lock()
            tr = repo.transaction("qpush")
            try:
                ret = self._apply(repo, series, list, update_status,
                                  strict, patchdir, merge, all_files=all_files)
                tr.close()
                self.save_dirty()
                return ret
            except:
                try:
                    tr.abort()
                finally:
                    repo.invalidate()
                    repo.dirstate.invalidate()
                raise
        finally:
            release(tr, lock, wlock)
            self.removeundo(repo)

    def _apply(self, repo, series, list=False, update_status=True,
               strict=False, patchdir=None, merge=None, all_files=None):
        '''returns (error, hash)
        error = 1 for unable to read, 2 for patch failed, 3 for patch fuzz'''
        # TODO unify with commands.py
        if not patchdir:
            patchdir = self.path
        err = 0
        n = None
        for patchname in series:
            pushable, reason = self.pushable(patchname)
            if not pushable:
                self.explain_pushable(patchname, all_patches=True)
                continue
            self.ui.status(_("applying %s\n") % patchname)
            pf = os.path.join(patchdir, patchname)

            try:
                ph = patchheader(self.join(patchname), self.plainmode)
            except:
                self.ui.warn(_("unable to read %s\n") % patchname)
                err = 1
                break

            message = ph.message
            if not message:
                # The commit message should not be translated
                message = "imported patch %s\n" % patchname
            else:
                if list:
                    # The commit message should not be translated
                    message.append("\nimported patch %s" % patchname)
                message = '\n'.join(message)

            if ph.haspatch:
                (patcherr, files, fuzz) = self.patch(repo, pf)
                if all_files is not None:
                    all_files.update(files)
                patcherr = not patcherr
            else:
                self.ui.warn(_("patch %s is empty\n") % patchname)
                patcherr, files, fuzz = 0, [], 0

            if merge and files:
                # Mark as removed/merged and update dirstate parent info
                removed = []
                merged = []
                for f in files:
                    if os.path.lexists(repo.wjoin(f)):
                        merged.append(f)
                    else:
                        removed.append(f)
                for f in removed:
                    repo.dirstate.remove(f)
                for f in merged:
                    repo.dirstate.merge(f)
                p1, p2 = repo.dirstate.parents()
                repo.dirstate.setparents(p1, merge)

            files = cmdutil.updatedir(self.ui, repo, files)
            match = cmdutil.matchfiles(repo, files or [])
            n = repo.commit(message, ph.user, ph.date, match=match, force=True)

            if n is None:
                raise util.Abort(_("repository commit failed"))

            if update_status:
                self.applied.append(statusentry(n, patchname))

            if patcherr:
                self.ui.warn(_("patch failed, rejects left in working dir\n"))
                err = 2
                break

            if fuzz and strict:
                self.ui.warn(_("fuzz found when applying patch, stopping\n"))
                err = 3
                break
        return (err, n)

    def _cleanup(self, patches, numrevs, keep=False):
        if not keep:
            r = self.qrepo()
            if r:
                r[None].remove(patches, True)
            else:
                for p in patches:
                    os.unlink(self.join(p))

        if numrevs:
            del self.applied[:numrevs]
            self.applied_dirty = 1

        for i in sorted([self.find_series(p) for p in patches], reverse=True):
            del self.full_series[i]
        self.parse_series()
        self.series_dirty = 1

    def _revpatches(self, repo, revs):
        firstrev = repo[self.applied[0].node].rev()
        patches = []
        for i, rev in enumerate(revs):

            if rev < firstrev:
                raise util.Abort(_('revision %d is not managed') % rev)

            ctx = repo[rev]
            base = self.applied[i].node
            if ctx.node() != base:
                msg = _('cannot delete revision %d above applied patches')
                raise util.Abort(msg % rev)

            patch = self.applied[i].name
            for fmt in ('[mq]: %s', 'imported patch %s'):
                if ctx.description() == fmt % patch:
                    msg = _('patch %s finalized without changeset message\n')
                    repo.ui.status(msg % patch)
                    break

            patches.append(patch)
        return patches

    def finish(self, repo, revs):
        patches = self._revpatches(repo, sorted(revs))
        self._cleanup(patches, len(patches))

    def delete(self, repo, patches, opts):
        if not patches and not opts.get('rev'):
            raise util.Abort(_('qdelete requires at least one revision or '
                               'patch name'))

        realpatches = []
        for patch in patches:
            patch = self.lookup(patch, strict=True)
            info = self.isapplied(patch)
            if info:
                raise util.Abort(_("cannot delete applied patch %s") % patch)
            if patch not in self.series:
                raise util.Abort(_("patch %s not in series file") % patch)
            if patch not in realpatches:
                realpatches.append(patch)

        numrevs = 0
        if opts.get('rev'):
            if not self.applied:
                raise util.Abort(_('no patches applied'))
            revs = cmdutil.revrange(repo, opts.get('rev'))
            if len(revs) > 1 and revs[0] > revs[1]:
                revs.reverse()
            revpatches = self._revpatches(repo, revs)
            realpatches += revpatches
            numrevs = len(revpatches)

        self._cleanup(realpatches, numrevs, opts.get('keep'))

    def check_toppatch(self, repo):
        if self.applied:
            top = self.applied[-1].node
            patch = self.applied[-1].name
            pp = repo.dirstate.parents()
            if top not in pp:
                raise util.Abort(_("working directory revision is not qtip"))
            return top, patch
        return None, None

    def check_localchanges(self, repo, force=False, refresh=True):
        m, a, r, d = repo.status()[:4]
        if (m or a or r or d) and not force:
            if refresh:
                raise util.Abort(_("local changes found, refresh first"))
            else:
                raise util.Abort(_("local changes found"))
        return m, a, r, d

    _reserved = ('series', 'status', 'guards')
    def check_reserved_name(self, name):
        if (name in self._reserved or name.startswith('.hg')
            or name.startswith('.mq') or '#' in name or ':' in name):
            raise util.Abort(_('"%s" cannot be used as the name of a patch')
                             % name)

    def new(self, repo, patchfn, *pats, **opts):
        """options:
           msg: a string or a no-argument function returning a string
        """
        msg = opts.get('msg')
        user = opts.get('user')
        date = opts.get('date')
        if date:
            date = util.parsedate(date)
        diffopts = self.diffopts({'git': opts.get('git')})
        self.check_reserved_name(patchfn)
        if os.path.exists(self.join(patchfn)):
            if os.path.isdir(self.join(patchfn)):
                raise util.Abort(_('"%s" already exists as a directory')
                                 % patchfn)
            else:
                raise util.Abort(_('patch "%s" already exists') % patchfn)
        if opts.get('include') or opts.get('exclude') or pats:
            match = cmdutil.match(repo, pats, opts)
            # detect missing files in pats
            def badfn(f, msg):
                raise util.Abort('%s: %s' % (f, msg))
            match.bad = badfn
            m, a, r, d = repo.status(match=match)[:4]
        else:
            m, a, r, d = self.check_localchanges(repo, force=True)
            match = cmdutil.matchfiles(repo, m + a + r)
        if len(repo[None].parents()) > 1:
            raise util.Abort(_('cannot manage merge changesets'))
        commitfiles = m + a + r
        self.check_toppatch(repo)
        insert = self.full_series_end()
        wlock = repo.wlock()
        try:
            try:
                # if patch file write fails, abort early
                p = self.opener(patchfn, "w")
            except IOError, e:
                raise util.Abort(_('cannot write patch "%s": %s')
                                 % (patchfn, e.strerror))
            try:
                if self.plainmode:
                    if user:
                        p.write("From: " + user + "\n")
                        if not date:
                            p.write("\n")
                    if date:
                        p.write("Date: %d %d\n\n" % date)
                else:
                    p.write("# HG changeset patch\n")
                    p.write("# Parent "
                            + hex(repo[None].parents()[0].node()) + "\n")
                    if user:
                        p.write("# User " + user + "\n")
                    if date:
                        p.write("# Date %s %s\n\n" % date)
                if hasattr(msg, '__call__'):
                    msg = msg()
                commitmsg = msg and msg or ("[mq]: %s" % patchfn)
                n = repo.commit(commitmsg, user, date, match=match, force=True)
                if n is None:
                    raise util.Abort(_("repo commit failed"))
                try:
                    self.full_series[insert:insert] = [patchfn]
                    self.applied.append(statusentry(n, patchfn))
                    self.parse_series()
                    self.series_dirty = 1
                    self.applied_dirty = 1
                    if msg:
                        msg = msg + "\n\n"
                        p.write(msg)
                    if commitfiles:
                        parent = self.qparents(repo, n)
                        chunks = patch.diff(repo, node1=parent, node2=n,
                                            match=match, opts=diffopts)
                        for chunk in chunks:
                            p.write(chunk)
                    p.close()
                    wlock.release()
                    wlock = None
                    r = self.qrepo()
                    if r:
                        r[None].add([patchfn])
                except:
                    repo.rollback()
                    raise
            except Exception:
                patchpath = self.join(patchfn)
                try:
                    os.unlink(patchpath)
                except:
                    self.ui.warn(_('error unlinking %s\n') % patchpath)
                raise
            self.removeundo(repo)
        finally:
            release(wlock)

    def strip(self, repo, revs, update=True, backup="all", force=None):
        wlock = lock = None
        try:
            wlock = repo.wlock()
            lock = repo.lock()

            if update:
                self.check_localchanges(repo, force=force, refresh=False)
                urev = self.qparents(repo, revs[0])
                hg.clean(repo, urev)
                repo.dirstate.write()

            self.removeundo(repo)
            for rev in revs:
                repair.strip(self.ui, repo, rev, backup)
            # strip may have unbundled a set of backed up revisions after
            # the actual strip
            self.removeundo(repo)
        finally:
            release(lock, wlock)

    def isapplied(self, patch):
        """returns (index, rev, patch)"""
        for i, a in enumerate(self.applied):
            if a.name == patch:
                return (i, a.node, a.name)
        return None

    # if the exact patch name does not exist, we try a few
    # variations.  If strict is passed, we try only #1
    #
    # 1) a number to indicate an offset in the series file
    # 2) a unique substring of the patch name was given
    # 3) patchname[-+]num to indicate an offset in the series file
    def lookup(self, patch, strict=False):
        patch = patch and str(patch)

        def partial_name(s):
            if s in self.series:
                return s
            matches = [x for x in self.series if s in x]
            if len(matches) > 1:
                self.ui.warn(_('patch name "%s" is ambiguous:\n') % s)
                for m in matches:
                    self.ui.warn('  %s\n' % m)
                return None
            if matches:
                return matches[0]
            if self.series and self.applied:
                if s == 'qtip':
                    return self.series[self.series_end(True)-1]
                if s == 'qbase':
                    return self.series[0]
            return None

        if patch is None:
            return None
        if patch in self.series:
            return patch

        if not os.path.isfile(self.join(patch)):
            try:
                sno = int(patch)
            except (ValueError, OverflowError):
                pass
            else:
                if -len(self.series) <= sno < len(self.series):
                    return self.series[sno]

            if not strict:
                res = partial_name(patch)
                if res:
                    return res
                minus = patch.rfind('-')
                if minus >= 0:
                    res = partial_name(patch[:minus])
                    if res:
                        i = self.series.index(res)
                        try:
                            off = int(patch[minus + 1:] or 1)
                        except (ValueError, OverflowError):
                            pass
                        else:
                            if i - off >= 0:
                                return self.series[i - off]
                plus = patch.rfind('+')
                if plus >= 0:
                    res = partial_name(patch[:plus])
                    if res:
                        i = self.series.index(res)
                        try:
                            off = int(patch[plus + 1:] or 1)
                        except (ValueError, OverflowError):
                            pass
                        else:
                            if i + off < len(self.series):
                                return self.series[i + off]
        raise util.Abort(_("patch %s not in series") % patch)

    def push(self, repo, patch=None, force=False, list=False,
             mergeq=None, all=False, move=False):
        diffopts = self.diffopts()
        wlock = repo.wlock()
        try:
            heads = []
            for b, ls in repo.branchmap().iteritems():
                heads += ls
            if not heads:
                heads = [nullid]
            if repo.dirstate.parents()[0] not in heads:
                self.ui.status(_("(working directory not at a head)\n"))

            if not self.series:
                self.ui.warn(_('no patches in series\n'))
                return 0

            patch = self.lookup(patch)
            # Suppose our series file is: A B C and the current 'top'
            # patch is B. qpush C should be performed (moving forward)
            # qpush B is a NOP (no change) qpush A is an error (can't
            # go backwards with qpush)
            if patch:
                info = self.isapplied(patch)
                if info:
                    if info[0] < len(self.applied) - 1:
                        raise util.Abort(
                            _("cannot push to a previous patch: %s") % patch)
                    self.ui.warn(
                        _('qpush: %s is already at the top\n') % patch)
                    return 0
                pushable, reason = self.pushable(patch)
                if not pushable:
                    if reason:
                        reason = _('guarded by %r') % reason
                    else:
                        reason = _('no matching guards')
                    self.ui.warn(_("cannot push '%s' - %s\n") % (patch, reason))
                    return 1
            elif all:
                patch = self.series[-1]
                if self.isapplied(patch):
                    self.ui.warn(_('all patches are currently applied\n'))
                    return 0

            # Following the above example, starting at 'top' of B:
            # qpush should be performed (pushes C), but a subsequent
            # qpush without an argument is an error (nothing to
            # apply). This allows a loop of "...while hg qpush..." to
            # work as it detects an error when done
            start = self.series_end()
            if start == len(self.series):
                self.ui.warn(_('patch series already fully applied\n'))
                return 1
            if not force:
                self.check_localchanges(repo)

            if move:
                if not patch:
                    raise  util.Abort(_("please specify the patch to move"))
                for i, rpn in enumerate(self.full_series[start:]):
                    # strip markers for patch guards
                    if self.guard_re.split(rpn, 1)[0] == patch:
                        break
                index = start + i
                assert index < len(self.full_series)
                fullpatch = self.full_series[index]
                del self.full_series[index]
                self.full_series.insert(start, fullpatch)
                self.parse_series()
                self.series_dirty = 1

            self.applied_dirty = 1
            if start > 0:
                self.check_toppatch(repo)
            if not patch:
                patch = self.series[start]
                end = start + 1
            else:
                end = self.series.index(patch, start) + 1

            s = self.series[start:end]
            all_files = set()
            try:
                if mergeq:
                    ret = self.mergepatch(repo, mergeq, s, diffopts)
                else:
                    ret = self.apply(repo, s, list, all_files=all_files)
            except:
                self.ui.warn(_('cleaning up working directory...'))
                node = repo.dirstate.parents()[0]
                hg.revert(repo, node, None)
                # only remove unknown files that we know we touched or
                # created while patching
                for f in all_files:
                    if f not in repo.dirstate:
                        try:
                            util.unlink(repo.wjoin(f))
                        except OSError, inst:
                            if inst.errno != errno.ENOENT:
                                raise
                self.ui.warn(_('done\n'))
                raise

            if not self.applied:
                return ret[0]
            top = self.applied[-1].name
            if ret[0] and ret[0] > 1:
                msg = _("errors during apply, please fix and refresh %s\n")
                self.ui.write(msg % top)
            else:
                self.ui.write(_("now at: %s\n") % top)
            return ret[0]

        finally:
            wlock.release()

    def pop(self, repo, patch=None, force=False, update=True, all=False):
        wlock = repo.wlock()
        try:
            if patch:
                # index, rev, patch
                info = self.isapplied(patch)
                if not info:
                    patch = self.lookup(patch)
                info = self.isapplied(patch)
                if not info:
                    raise util.Abort(_("patch %s is not applied") % patch)

            if not self.applied:
                # Allow qpop -a to work repeatedly,
                # but not qpop without an argument
                self.ui.warn(_("no patches applied\n"))
                return not all

            if all:
                start = 0
            elif patch:
                start = info[0] + 1
            else:
                start = len(self.applied) - 1

            if start >= len(self.applied):
                self.ui.warn(_("qpop: %s is already at the top\n") % patch)
                return

            if not update:
                parents = repo.dirstate.parents()
                rr = [x.node for x in self.applied]
                for p in parents:
                    if p in rr:
                        self.ui.warn(_("qpop: forcing dirstate update\n"))
                        update = True
            else:
                parents = [p.node() for p in repo[None].parents()]
                needupdate = False
                for entry in self.applied[start:]:
                    if entry.node in parents:
                        needupdate = True
                        break
                update = needupdate

            if not force and update:
                self.check_localchanges(repo)

            self.applied_dirty = 1
            end = len(self.applied)
            rev = self.applied[start].node
            if update:
                top = self.check_toppatch(repo)[0]

            try:
                heads = repo.changelog.heads(rev)
            except error.LookupError:
                node = short(rev)
                raise util.Abort(_('trying to pop unknown node %s') % node)

            if heads != [self.applied[-1].node]:
                raise util.Abort(_("popping would remove a revision not "
                                   "managed by this patch queue"))

            # we know there are no local changes, so we can make a simplified
            # form of hg.update.
            if update:
                qp = self.qparents(repo, rev)
                ctx = repo[qp]
                m, a, r, d = repo.status(qp, top)[:4]
                if d:
                    raise util.Abort(_("deletions found between repo revs"))
                for f in a:
                    try:
                        util.unlink(repo.wjoin(f))
                    except OSError, e:
                        if e.errno != errno.ENOENT:
                            raise
                    repo.dirstate.forget(f)
                for f in m + r:
                    fctx = ctx[f]
                    repo.wwrite(f, fctx.data(), fctx.flags())
                    repo.dirstate.normal(f)
                repo.dirstate.setparents(qp, nullid)
            for patch in reversed(self.applied[start:end]):
                self.ui.status(_("popping %s\n") % patch.name)
            del self.applied[start:end]
            self.strip(repo, [rev], update=False, backup='strip')
            if self.applied:
                self.ui.write(_("now at: %s\n") % self.applied[-1].name)
            else:
                self.ui.write(_("patch queue now empty\n"))
        finally:
            wlock.release()

    def diff(self, repo, pats, opts):
        top, patch = self.check_toppatch(repo)
        if not top:
            self.ui.write(_("no patches applied\n"))
            return
        qp = self.qparents(repo, top)
        if opts.get('reverse'):
            node1, node2 = None, qp
        else:
            node1, node2 = qp, None
        diffopts = self.diffopts(opts, patch)
        self.printdiff(repo, diffopts, node1, node2, files=pats, opts=opts)

    def refresh(self, repo, pats=None, **opts):
        if not self.applied:
            self.ui.write(_("no patches applied\n"))
            return 1
        msg = opts.get('msg', '').rstrip()
        newuser = opts.get('user')
        newdate = opts.get('date')
        if newdate:
            newdate = '%d %d' % util.parsedate(newdate)
        wlock = repo.wlock()

        try:
            self.check_toppatch(repo)
            (top, patchfn) = (self.applied[-1].node, self.applied[-1].name)
            if repo.changelog.heads(top) != [top]:
                raise util.Abort(_("cannot refresh a revision with children"))

            cparents = repo.changelog.parents(top)
            patchparent = self.qparents(repo, top)
            ph = patchheader(self.join(patchfn), self.plainmode)
            diffopts = self.diffopts({'git': opts.get('git')}, patchfn)
            if msg:
                ph.setmessage(msg)
            if newuser:
                ph.setuser(newuser)
            if newdate:
                ph.setdate(newdate)
            ph.setparent(hex(patchparent))

            # only commit new patch when write is complete
            patchf = self.opener(patchfn, 'w', atomictemp=True)

            comments = str(ph)
            if comments:
                patchf.write(comments)

            # update the dirstate in place, strip off the qtip commit
            # and then commit.
            #
            # this should really read:
            #   mm, dd, aa, aa2 = repo.status(tip, patchparent)[:4]
            # but we do it backwards to take advantage of manifest/chlog
            # caching against the next repo.status call
            mm, aa, dd, aa2 = repo.status(patchparent, top)[:4]
            changes = repo.changelog.read(top)
            man = repo.manifest.read(changes[0])
            aaa = aa[:]
            matchfn = cmdutil.match(repo, pats, opts)
            # in short mode, we only diff the files included in the
            # patch already plus specified files
            if opts.get('short'):
                # if amending a patch, we start with existing
                # files plus specified files - unfiltered
                match = cmdutil.matchfiles(repo, mm + aa + dd + matchfn.files())
                # filter with inc/exl options
                matchfn = cmdutil.match(repo, opts=opts)
            else:
                match = cmdutil.matchall(repo)
            m, a, r, d = repo.status(match=match)[:4]

            # we might end up with files that were added between
            # qtip and the dirstate parent, but then changed in the
            # local dirstate. in this case, we want them to only
            # show up in the added section
            for x in m:
                if x == '.hgsub' or x == '.hgsubstate':
                    self.ui.warn(_('warning: not refreshing %s\n') % x)
                    continue
                if x not in aa:
                    mm.append(x)
            # we might end up with files added by the local dirstate that
            # were deleted by the patch.  In this case, they should only
            # show up in the changed section.
            for x in a:
                if x == '.hgsub' or x == '.hgsubstate':
                    self.ui.warn(_('warning: not adding %s\n') % x)
                    continue
                if x in dd:
                    del dd[dd.index(x)]
                    mm.append(x)
                else:
                    aa.append(x)
            # make sure any files deleted in the local dirstate
            # are not in the add or change column of the patch
            forget = []
            for x in d + r:
                if x == '.hgsub' or x == '.hgsubstate':
                    self.ui.warn(_('warning: not removing %s\n') % x)
                    continue
                if x in aa:
                    del aa[aa.index(x)]
                    forget.append(x)
                    continue
                elif x in mm:
                    del mm[mm.index(x)]
                dd.append(x)

            m = list(set(mm))
            r = list(set(dd))
            a = list(set(aa))
            c = [filter(matchfn, l) for l in (m, a, r)]
            match = cmdutil.matchfiles(repo, set(c[0] + c[1] + c[2]))
            chunks = patch.diff(repo, patchparent, match=match,
                                changes=c, opts=diffopts)
            for chunk in chunks:
                patchf.write(chunk)

            try:
                if diffopts.git or diffopts.upgrade:
                    copies = {}
                    for dst in a:
                        src = repo.dirstate.copied(dst)
                        # during qfold, the source file for copies may
                        # be removed. Treat this as a simple add.
                        if src is not None and src in repo.dirstate:
                            copies.setdefault(src, []).append(dst)
                        repo.dirstate.add(dst)
                    # remember the copies between patchparent and qtip
                    for dst in aaa:
                        f = repo.file(dst)
                        src = f.renamed(man[dst])
                        if src:
                            copies.setdefault(src[0], []).extend(
                                copies.get(dst, []))
                            if dst in a:
                                copies[src[0]].append(dst)
                        # we can't copy a file created by the patch itself
                        if dst in copies:
                            del copies[dst]
                    for src, dsts in copies.iteritems():
                        for dst in dsts:
                            repo.dirstate.copy(src, dst)
                else:
                    for dst in a:
                        repo.dirstate.add(dst)
                    # Drop useless copy information
                    for f in list(repo.dirstate.copies()):
                        repo.dirstate.copy(None, f)
                for f in r:
                    repo.dirstate.remove(f)
                # if the patch excludes a modified file, mark that
                # file with mtime=0 so status can see it.
                mm = []
                for i in xrange(len(m)-1, -1, -1):
                    if not matchfn(m[i]):
                        mm.append(m[i])
                        del m[i]
                for f in m:
                    repo.dirstate.normal(f)
                for f in mm:
                    repo.dirstate.normallookup(f)
                for f in forget:
                    repo.dirstate.forget(f)

                if not msg:
                    if not ph.message:
                        message = "[mq]: %s\n" % patchfn
                    else:
                        message = "\n".join(ph.message)
                else:
                    message = msg

                user = ph.user or changes[1]

                # assumes strip can roll itself back if interrupted
                repo.dirstate.setparents(*cparents)
                self.applied.pop()
                self.applied_dirty = 1
                self.strip(repo, [top], update=False,
                           backup='strip')
            except:
                repo.dirstate.invalidate()
                raise

            try:
                # might be nice to attempt to roll back strip after this
                patchf.rename()
                n = repo.commit(message, user, ph.date, match=match,
                                force=True)
                self.applied.append(statusentry(n, patchfn))
            except:
                ctx = repo[cparents[0]]
                repo.dirstate.rebuild(ctx.node(), ctx.manifest())
                self.save_dirty()
                self.ui.warn(_('refresh interrupted while patch was popped! '
                               '(revert --all, qpush to recover)\n'))
                raise
        finally:
            wlock.release()
            self.removeundo(repo)

    def init(self, repo, create=False):
        if not create and os.path.isdir(self.path):
            raise util.Abort(_("patch queue directory already exists"))
        try:
            os.mkdir(self.path)
        except OSError, inst:
            if inst.errno != errno.EEXIST or not create:
                raise
        if create:
            return self.qrepo(create=True)

    def unapplied(self, repo, patch=None):
        if patch and patch not in self.series:
            raise util.Abort(_("patch %s is not in series file") % patch)
        if not patch:
            start = self.series_end()
        else:
            start = self.series.index(patch) + 1
        unapplied = []
        for i in xrange(start, len(self.series)):
            pushable, reason = self.pushable(i)
            if pushable:
                unapplied.append((i, self.series[i]))
            self.explain_pushable(i)
        return unapplied

    def qseries(self, repo, missing=None, start=0, length=None, status=None,
                summary=False):
        def displayname(pfx, patchname, state):
            if pfx:
                self.ui.write(pfx)
            if summary:
                ph = patchheader(self.join(patchname), self.plainmode)
                msg = ph.message and ph.message[0] or ''
                if self.ui.formatted():
                    width = self.ui.termwidth() - len(pfx) - len(patchname) - 2
                    if width > 0:
                        msg = util.ellipsis(msg, width)
                    else:
                        msg = ''
                self.ui.write(patchname, label='qseries.' + state)
                self.ui.write(': ')
                self.ui.write(msg, label='qseries.message.' + state)
            else:
                self.ui.write(patchname, label='qseries.' + state)
            self.ui.write('\n')

        applied = set([p.name for p in self.applied])
        if length is None:
            length = len(self.series) - start
        if not missing:
            if self.ui.verbose:
                idxwidth = len(str(start + length - 1))
            for i in xrange(start, start + length):
                patch = self.series[i]
                if patch in applied:
                    char, state = 'A', 'applied'
                elif self.pushable(i)[0]:
                    char, state = 'U', 'unapplied'
                else:
                    char, state = 'G', 'guarded'
                pfx = ''
                if self.ui.verbose:
                    pfx = '%*d %s ' % (idxwidth, i, char)
                elif status and status != char:
                    continue
                displayname(pfx, patch, state)
        else:
            msng_list = []
            for root, dirs, files in os.walk(self.path):
                d = root[len(self.path) + 1:]
                for f in files:
                    fl = os.path.join(d, f)
                    if (fl not in self.series and
                        fl not in (self.status_path, self.series_path,
                                   self.guards_path)
                        and not fl.startswith('.')):
                        msng_list.append(fl)
            for x in sorted(msng_list):
                pfx = self.ui.verbose and ('D ') or ''
                displayname(pfx, x, 'missing')

    def issaveline(self, l):
        if l.name == '.hg.patches.save.line':
            return True

    def qrepo(self, create=False):
        ui = self.ui.copy()
        ui.setconfig('paths', 'default', '', overlay=False)
        ui.setconfig('paths', 'default-push', '', overlay=False)
        if create or os.path.isdir(self.join(".hg")):
            return hg.repository(ui, path=self.path, create=create)

    def restore(self, repo, rev, delete=None, qupdate=None):
        desc = repo[rev].description().strip()
        lines = desc.splitlines()
        i = 0
        datastart = None
        series = []
        applied = []
        qpp = None
        for i, line in enumerate(lines):
            if line == 'Patch Data:':
                datastart = i + 1
            elif line.startswith('Dirstate:'):
                l = line.rstrip()
                l = l[10:].split(' ')
                qpp = [bin(x) for x in l]
            elif datastart != None:
                l = line.rstrip()
                n, name = l.split(':', 1)
                if n:
                    applied.append(statusentry(bin(n), name))
                else:
                    series.append(l)
        if datastart is None:
            self.ui.warn(_("No saved patch data found\n"))
            return 1
        self.ui.warn(_("restoring status: %s\n") % lines[0])
        self.full_series = series
        self.applied = applied
        self.parse_series()
        self.series_dirty = 1
        self.applied_dirty = 1
        heads = repo.changelog.heads()
        if delete:
            if rev not in heads:
                self.ui.warn(_("save entry has children, leaving it alone\n"))
            else:
                self.ui.warn(_("removing save entry %s\n") % short(rev))
                pp = repo.dirstate.parents()
                if rev in pp:
                    update = True
                else:
                    update = False
                self.strip(repo, [rev], update=update, backup='strip')
        if qpp:
            self.ui.warn(_("saved queue repository parents: %s %s\n") %
                         (short(qpp[0]), short(qpp[1])))
            if qupdate:
                self.ui.status(_("updating queue directory\n"))
                r = self.qrepo()
                if not r:
                    self.ui.warn(_("Unable to load queue repository\n"))
                    return 1
                hg.clean(r, qpp[0])

    def save(self, repo, msg=None):
        if not self.applied:
            self.ui.warn(_("save: no patches applied, exiting\n"))
            return 1
        if self.issaveline(self.applied[-1]):
            self.ui.warn(_("status is already saved\n"))
            return 1

        if not msg:
            msg = _("hg patches saved state")
        else:
            msg = "hg patches: " + msg.rstrip('\r\n')
        r = self.qrepo()
        if r:
            pp = r.dirstate.parents()
            msg += "\nDirstate: %s %s" % (hex(pp[0]), hex(pp[1]))
        msg += "\n\nPatch Data:\n"
        msg += ''.join('%s\n' % x for x in self.applied)
        msg += ''.join(':%s\n' % x for x in self.full_series)
        n = repo.commit(msg, force=True)
        if not n:
            self.ui.warn(_("repo commit failed\n"))
            return 1
        self.applied.append(statusentry(n, '.hg.patches.save.line'))
        self.applied_dirty = 1
        self.removeundo(repo)

    def full_series_end(self):
        if self.applied:
            p = self.applied[-1].name
            end = self.find_series(p)
            if end is None:
                return len(self.full_series)
            return end + 1
        return 0

    def series_end(self, all_patches=False):
        """If all_patches is False, return the index of the next pushable patch
        in the series, or the series length. If all_patches is True, return the
        index of the first patch past the last applied one.
        """
        end = 0
        def next(start):
            if all_patches or start >= len(self.series):
                return start
            for i in xrange(start, len(self.series)):
                p, reason = self.pushable(i)
                if p:
                    break
                self.explain_pushable(i)
            return i
        if self.applied:
            p = self.applied[-1].name
            try:
                end = self.series.index(p)
            except ValueError:
                return 0
            return next(end + 1)
        return next(end)

    def appliedname(self, index):
        pname = self.applied[index].name
        if not self.ui.verbose:
            p = pname
        else:
            p = str(self.series.index(pname)) + " " + pname
        return p

    def qimport(self, repo, files, patchname=None, rev=None, existing=None,
                force=None, git=False):
        def checkseries(patchname):
            if patchname in self.series:
                raise util.Abort(_('patch %s is already in the series file')
                                 % patchname)
        def checkfile(patchname):
            if not force and os.path.exists(self.join(patchname)):
                raise util.Abort(_('patch "%s" already exists')
                                 % patchname)

        if rev:
            if files:
                raise util.Abort(_('option "-r" not valid when importing '
                                   'files'))
            rev = cmdutil.revrange(repo, rev)
            rev.sort(reverse=True)
        if (len(files) > 1 or len(rev) > 1) and patchname:
            raise util.Abort(_('option "-n" not valid when importing multiple '
                               'patches'))
        if rev:
            # If mq patches are applied, we can only import revisions
            # that form a linear path to qbase.
            # Otherwise, they should form a linear path to a head.
            heads = repo.changelog.heads(repo.changelog.node(rev[-1]))
            if len(heads) > 1:
                raise util.Abort(_('revision %d is the root of more than one '
                                   'branch') % rev[-1])
            if self.applied:
                base = repo.changelog.node(rev[0])
                if base in [n.node for n in self.applied]:
                    raise util.Abort(_('revision %d is already managed')
                                     % rev[0])
                if heads != [self.applied[-1].node]:
                    raise util.Abort(_('revision %d is not the parent of '
                                       'the queue') % rev[0])
                base = repo.changelog.rev(self.applied[0].node)
                lastparent = repo.changelog.parentrevs(base)[0]
            else:
                if heads != [repo.changelog.node(rev[0])]:
                    raise util.Abort(_('revision %d has unmanaged children')
                                     % rev[0])
                lastparent = None

            diffopts = self.diffopts({'git': git})
            for r in rev:
                p1, p2 = repo.changelog.parentrevs(r)
                n = repo.changelog.node(r)
                if p2 != nullrev:
                    raise util.Abort(_('cannot import merge revision %d') % r)
                if lastparent and lastparent != r:
                    raise util.Abort(_('revision %d is not the parent of %d')
                                     % (r, lastparent))
                lastparent = p1

                if not patchname:
                    patchname = normname('%d.diff' % r)
                self.check_reserved_name(patchname)
                checkseries(patchname)
                checkfile(patchname)
                self.full_series.insert(0, patchname)

                patchf = self.opener(patchname, "w")
                cmdutil.export(repo, [n], fp=patchf, opts=diffopts)
                patchf.close()

                se = statusentry(n, patchname)
                self.applied.insert(0, se)

                self.added.append(patchname)
                patchname = None
            self.parse_series()
            self.applied_dirty = 1
            self.series_dirty = True

        for i, filename in enumerate(files):
            if existing:
                if filename == '-':
                    raise util.Abort(_('-e is incompatible with import from -'))
                filename = normname(filename)
                self.check_reserved_name(filename)
                originpath = self.join(filename)
                if not os.path.isfile(originpath):
                    raise util.Abort(_("patch %s does not exist") % filename)

                if patchname:
                    self.check_reserved_name(patchname)
                    checkfile(patchname)

                    self.ui.write(_('renaming %s to %s\n')
                                        % (filename, patchname))
                    util.rename(originpath, self.join(patchname))
                else:
                    patchname = filename

            else:
                try:
                    if filename == '-':
                        if not patchname:
                            raise util.Abort(
                                _('need --name to import a patch from -'))
                        text = sys.stdin.read()
                    else:
                        text = url.open(self.ui, filename).read()
                except (OSError, IOError):
                    raise util.Abort(_("unable to read file %s") % filename)
                if not patchname:
                    patchname = normname(os.path.basename(filename))
                self.check_reserved_name(patchname)
                checkfile(patchname)
                patchf = self.opener(patchname, "w")
                patchf.write(text)
            if not force:
                checkseries(patchname)
            if patchname not in self.series:
                index = self.full_series_end() + i
                self.full_series[index:index] = [patchname]
            self.parse_series()
            self.series_dirty = True
            self.ui.warn(_("adding %s to series file\n") % patchname)
            self.added.append(patchname)
            patchname = None

def delete(ui, repo, *patches, **opts):
    """remove patches from queue

    The patches must not be applied, and at least one patch is required. With
    -k/--keep, the patch files are preserved in the patch directory.

    To stop managing a patch and move it into permanent history,
    use the :hg:`qfinish` command."""
    q = repo.mq
    q.delete(repo, patches, opts)
    q.save_dirty()
    return 0

def applied(ui, repo, patch=None, **opts):
    """print the patches already applied

    Returns 0 on success."""

    q = repo.mq

    if patch:
        if patch not in q.series:
            raise util.Abort(_("patch %s is not in series file") % patch)
        end = q.series.index(patch) + 1
    else:
        end = q.series_end(True)

    if opts.get('last') and not end:
        ui.write(_("no patches applied\n"))
        return 1
    elif opts.get('last') and end == 1:
        ui.write(_("only one patch applied\n"))
        return 1
    elif opts.get('last'):
        start = end - 2
        end = 1
    else:
        start = 0

    q.qseries(repo, length=end, start=start, status='A',
              summary=opts.get('summary'))


def unapplied(ui, repo, patch=None, **opts):
    """print the patches not yet applied

    Returns 0 on success."""

    q = repo.mq
    if patch:
        if patch not in q.series:
            raise util.Abort(_("patch %s is not in series file") % patch)
        start = q.series.index(patch) + 1
    else:
        start = q.series_end(True)

    if start == len(q.series) and opts.get('first'):
        ui.write(_("all patches applied\n"))
        return 1

    length = opts.get('first') and 1 or None
    q.qseries(repo, start=start, length=length, status='U',
              summary=opts.get('summary'))

def qimport(ui, repo, *filename, **opts):
    """import a patch

    The patch is inserted into the series after the last applied
    patch. If no patches have been applied, qimport prepends the patch
    to the series.

    The patch will have the same name as its source file unless you
    give it a new one with -n/--name.

    You can register an existing patch inside the patch directory with
    the -e/--existing flag.

    With -f/--force, an existing patch of the same name will be
    overwritten.

    An existing changeset may be placed under mq control with -r/--rev
    (e.g. qimport --rev tip -n patch will place tip under mq control).
    With -g/--git, patches imported with --rev will use the git diff
    format. See the diffs help topic for information on why this is
    important for preserving rename/copy information and permission
    changes.

    To import a patch from standard input, pass - as the patch file.
    When importing from standard input, a patch name must be specified
    using the --name flag.

    To import an existing patch while renaming it::

      hg qimport -e existing-patch -n new-name

    Returns 0 if import succeeded.
    """
    q = repo.mq
    try:
        q.qimport(repo, filename, patchname=opts.get('name'),
              existing=opts.get('existing'), force=opts.get('force'),
              rev=opts.get('rev'), git=opts.get('git'))
    finally:
        q.save_dirty()

    if opts.get('push') and not opts.get('rev'):
        return q.push(repo, None)
    return 0

def qinit(ui, repo, create):
    """initialize a new queue repository

    This command also creates a series file for ordering patches, and
    an mq-specific .hgignore file in the queue repository, to exclude
    the status and guards files (these contain mostly transient state).

    Returns 0 if initialization succeeded."""
    q = repo.mq
    r = q.init(repo, create)
    q.save_dirty()
    if r:
        if not os.path.exists(r.wjoin('.hgignore')):
            fp = r.wopener('.hgignore', 'w')
            fp.write('^\\.hg\n')
            fp.write('^\\.mq\n')
            fp.write('syntax: glob\n')
            fp.write('status\n')
            fp.write('guards\n')
            fp.close()
        if not os.path.exists(r.wjoin('series')):
            r.wopener('series', 'w').close()
        r[None].add(['.hgignore', 'series'])
        commands.add(ui, r)
    return 0

def init(ui, repo, **opts):
    """init a new queue repository (DEPRECATED)

    The queue repository is unversioned by default. If
    -c/--create-repo is specified, qinit will create a separate nested
    repository for patches (qinit -c may also be run later to convert
    an unversioned patch repository into a versioned one). You can use
    qcommit to commit changes to this queue repository.

    This command is deprecated. Without -c, it's implied by other relevant
    commands. With -c, use :hg:`init --mq` instead."""
    return qinit(ui, repo, create=opts.get('create_repo'))

def clone(ui, source, dest=None, **opts):
    '''clone main and patch repository at same time

    If source is local, destination will have no patches applied. If
    source is remote, this command can not check if patches are
    applied in source, so cannot guarantee that patches are not
    applied in destination. If you clone remote repository, be sure
    before that it has no patches applied.

    Source patch repository is looked for in <src>/.hg/patches by
    default. Use -p <url> to change.

    The patch directory must be a nested Mercurial repository, as
    would be created by :hg:`init --mq`.

    Return 0 on success.
    '''
    def patchdir(repo):
        url = repo.url()
        if url.endswith('/'):
            url = url[:-1]
        return url + '/.hg/patches'
    if dest is None:
        dest = hg.defaultdest(source)
    sr = hg.repository(hg.remoteui(ui, opts), ui.expandpath(source))
    if opts.get('patches'):
        patchespath = ui.expandpath(opts.get('patches'))
    else:
        patchespath = patchdir(sr)
    try:
        hg.repository(ui, patchespath)
    except error.RepoError:
        raise util.Abort(_('versioned patch repository not found'
                           ' (see init --mq)'))
    qbase, destrev = None, None
    if sr.local():
        if sr.mq.applied:
            qbase = sr.mq.applied[0].node
            if not hg.islocal(dest):
                heads = set(sr.heads())
                destrev = list(heads.difference(sr.heads(qbase)))
                destrev.append(sr.changelog.parents(qbase)[0])
    elif sr.capable('lookup'):
        try:
            qbase = sr.lookup('qbase')
        except error.RepoError:
            pass
    ui.note(_('cloning main repository\n'))
    sr, dr = hg.clone(ui, sr.url(), dest,
                      pull=opts.get('pull'),
                      rev=destrev,
                      update=False,
                      stream=opts.get('uncompressed'))
    ui.note(_('cloning patch repository\n'))
    hg.clone(ui, opts.get('patches') or patchdir(sr), patchdir(dr),
             pull=opts.get('pull'), update=not opts.get('noupdate'),
             stream=opts.get('uncompressed'))
    if dr.local():
        if qbase:
            ui.note(_('stripping applied patches from destination '
                      'repository\n'))
            dr.mq.strip(dr, [qbase], update=False, backup=None)
        if not opts.get('noupdate'):
            ui.note(_('updating destination repository\n'))
            hg.update(dr, dr.changelog.tip())

def commit(ui, repo, *pats, **opts):
    """commit changes in the queue repository (DEPRECATED)

    This command is deprecated; use :hg:`commit --mq` instead."""
    q = repo.mq
    r = q.qrepo()
    if not r:
        raise util.Abort('no queue repository')
    commands.commit(r.ui, r, *pats, **opts)

def series(ui, repo, **opts):
    """print the entire series file

    Returns 0 on success."""
    repo.mq.qseries(repo, missing=opts.get('missing'), summary=opts.get('summary'))
    return 0

def top(ui, repo, **opts):
    """print the name of the current patch

    Returns 0 on success."""
    q = repo.mq
    t = q.applied and q.series_end(True) or 0
    if t:
        q.qseries(repo, start=t - 1, length=1, status='A',
                  summary=opts.get('summary'))
    else:
        ui.write(_("no patches applied\n"))
        return 1

def next(ui, repo, **opts):
    """print the name of the next patch

    Returns 0 on success."""
    q = repo.mq
    end = q.series_end()
    if end == len(q.series):
        ui.write(_("all patches applied\n"))
        return 1
    q.qseries(repo, start=end, length=1, summary=opts.get('summary'))

def prev(ui, repo, **opts):
    """print the name of the previous patch

    Returns 0 on success."""
    q = repo.mq
    l = len(q.applied)
    if l == 1:
        ui.write(_("only one patch applied\n"))
        return 1
    if not l:
        ui.write(_("no patches applied\n"))
        return 1
    q.qseries(repo, start=l - 2, length=1, status='A',
              summary=opts.get('summary'))

def setupheaderopts(ui, opts):
    if not opts.get('user') and opts.get('currentuser'):
        opts['user'] = ui.username()
    if not opts.get('date') and opts.get('currentdate'):
        opts['date'] = "%d %d" % util.makedate()

def new(ui, repo, patch, *args, **opts):
    """create a new patch

    qnew creates a new patch on top of the currently-applied patch (if
    any). The patch will be initialized with any outstanding changes
    in the working directory. You may also use -I/--include,
    -X/--exclude, and/or a list of files after the patch name to add
    only changes to matching files to the new patch, leaving the rest
    as uncommitted modifications.

    -u/--user and -d/--date can be used to set the (given) user and
    date, respectively. -U/--currentuser and -D/--currentdate set user
    to current user and date to current date.

    -e/--edit, -m/--message or -l/--logfile set the patch header as
    well as the commit message. If none is specified, the header is
    empty and the commit message is '[mq]: PATCH'.

    Use the -g/--git option to keep the patch in the git extended diff
    format. Read the diffs help topic for more information on why this
    is important for preserving permission changes and copy/rename
    information.

    Returns 0 on successful creation of a new patch.
    """
    msg = cmdutil.logmessage(opts)
    def getmsg():
        return ui.edit(msg, opts.get('user') or ui.username())
    q = repo.mq
    opts['msg'] = msg
    if opts.get('edit'):
        opts['msg'] = getmsg
    else:
        opts['msg'] = msg
    setupheaderopts(ui, opts)
    q.new(repo, patch, *args, **opts)
    q.save_dirty()
    return 0

def refresh(ui, repo, *pats, **opts):
    """update the current patch

    If any file patterns are provided, the refreshed patch will
    contain only the modifications that match those patterns; the
    remaining modifications will remain in the working directory.

    If -s/--short is specified, files currently included in the patch
    will be refreshed just like matched files and remain in the patch.

    If -e/--edit is specified, Mercurial will start your configured editor for
    you to enter a message. In case qrefresh fails, you will find a backup of
    your message in ``.hg/last-message.txt``.

    hg add/remove/copy/rename work as usual, though you might want to
    use git-style patches (-g/--git or [diff] git=1) to track copies
    and renames. See the diffs help topic for more information on the
    git diff format.

    Returns 0 on success.
    """
    q = repo.mq
    message = cmdutil.logmessage(opts)
    if opts.get('edit'):
        if not q.applied:
            ui.write(_("no patches applied\n"))
            return 1
        if message:
            raise util.Abort(_('option "-e" incompatible with "-m" or "-l"'))
        patch = q.applied[-1].name
        ph = patchheader(q.join(patch), q.plainmode)
        message = ui.edit('\n'.join(ph.message), ph.user or ui.username())
        # We don't want to lose the patch message if qrefresh fails (issue2062)
        msgfile = repo.opener('last-message.txt', 'wb')
        msgfile.write(message)
        msgfile.close()
    setupheaderopts(ui, opts)
    ret = q.refresh(repo, pats, msg=message, **opts)
    q.save_dirty()
    return ret

def diff(ui, repo, *pats, **opts):
    """diff of the current patch and subsequent modifications

    Shows a diff which includes the current patch as well as any
    changes which have been made in the working directory since the
    last refresh (thus showing what the current patch would become
    after a qrefresh).

    Use :hg:`diff` if you only want to see the changes made since the
    last qrefresh, or :hg:`export qtip` if you want to see changes
    made by the current patch without including changes made since the
    qrefresh.

    Returns 0 on success.
    """
    repo.mq.diff(repo, pats, opts)
    return 0

def fold(ui, repo, *files, **opts):
    """fold the named patches into the current patch

    Patches must not yet be applied. Each patch will be successively
    applied to the current patch in the order given. If all the
    patches apply successfully, the current patch will be refreshed
    with the new cumulative patch, and the folded patches will be
    deleted. With -k/--keep, the folded patch files will not be
    removed afterwards.

    The header for each folded patch will be concatenated with the
    current patch header, separated by a line of ``* * *``.

    Returns 0 on success."""

    q = repo.mq

    if not files:
        raise util.Abort(_('qfold requires at least one patch name'))
    if not q.check_toppatch(repo)[0]:
        raise util.Abort(_('no patches applied'))
    q.check_localchanges(repo)

    message = cmdutil.logmessage(opts)
    if opts.get('edit'):
        if message:
            raise util.Abort(_('option "-e" incompatible with "-m" or "-l"'))

    parent = q.lookup('qtip')
    patches = []
    messages = []
    for f in files:
        p = q.lookup(f)
        if p in patches or p == parent:
            ui.warn(_('Skipping already folded patch %s\n') % p)
        if q.isapplied(p):
            raise util.Abort(_('qfold cannot fold already applied patch %s') % p)
        patches.append(p)

    for p in patches:
        if not message:
            ph = patchheader(q.join(p), q.plainmode)
            if ph.message:
                messages.append(ph.message)
        pf = q.join(p)
        (patchsuccess, files, fuzz) = q.patch(repo, pf)
        if not patchsuccess:
            raise util.Abort(_('error folding patch %s') % p)
        cmdutil.updatedir(ui, repo, files)

    if not message:
        ph = patchheader(q.join(parent), q.plainmode)
        message, user = ph.message, ph.user
        for msg in messages:
            message.append('* * *')
            message.extend(msg)
        message = '\n'.join(message)

    if opts.get('edit'):
        message = ui.edit(message, user or ui.username())

    diffopts = q.patchopts(q.diffopts(), *patches)
    q.refresh(repo, msg=message, git=diffopts.git)
    q.delete(repo, patches, opts)
    q.save_dirty()

def goto(ui, repo, patch, **opts):
    '''push or pop patches until named patch is at top of stack

    Returns 0 on success.'''
    q = repo.mq
    patch = q.lookup(patch)
    if q.isapplied(patch):
        ret = q.pop(repo, patch, force=opts.get('force'))
    else:
        ret = q.push(repo, patch, force=opts.get('force'))
    q.save_dirty()
    return ret

def guard(ui, repo, *args, **opts):
    '''set or print guards for a patch

    Guards control whether a patch can be pushed. A patch with no
    guards is always pushed. A patch with a positive guard ("+foo") is
    pushed only if the :hg:`qselect` command has activated it. A patch with
    a negative guard ("-foo") is never pushed if the :hg:`qselect` command
    has activated it.

    With no arguments, print the currently active guards.
    With arguments, set guards for the named patch.

    .. note::
       Specifying negative guards now requires '--'.

    To set guards on another patch::

      hg qguard other.patch -- +2.6.17 -stable

    Returns 0 on success.
    '''
    def status(idx):
        guards = q.series_guards[idx] or ['unguarded']
        if q.series[idx] in applied:
            state = 'applied'
        elif q.pushable(idx)[0]:
            state = 'unapplied'
        else:
            state = 'guarded'
        label = 'qguard.patch qguard.%s qseries.%s' % (state, state)
        ui.write('%s: ' % ui.label(q.series[idx], label))

        for i, guard in enumerate(guards):
            if guard.startswith('+'):
                ui.write(guard, label='qguard.positive')
            elif guard.startswith('-'):
                ui.write(guard, label='qguard.negative')
            else:
                ui.write(guard, label='qguard.unguarded')
            if i != len(guards) - 1:
                ui.write(' ')
        ui.write('\n')
    q = repo.mq
    applied = set(p.name for p in q.applied)
    patch = None
    args = list(args)
    if opts.get('list'):
        if args or opts.get('none'):
            raise util.Abort(_('cannot mix -l/--list with options or arguments'))
        for i in xrange(len(q.series)):
            status(i)
        return
    if not args or args[0][0:1] in '-+':
        if not q.applied:
            raise util.Abort(_('no patches applied'))
        patch = q.applied[-1].name
    if patch is None and args[0][0:1] not in '-+':
        patch = args.pop(0)
    if patch is None:
        raise util.Abort(_('no patch to work with'))
    if args or opts.get('none'):
        idx = q.find_series(patch)
        if idx is None:
            raise util.Abort(_('no patch named %s') % patch)
        q.set_guards(idx, args)
        q.save_dirty()
    else:
        status(q.series.index(q.lookup(patch)))

def header(ui, repo, patch=None):
    """print the header of the topmost or specified patch

    Returns 0 on success."""
    q = repo.mq

    if patch:
        patch = q.lookup(patch)
    else:
        if not q.applied:
            ui.write(_('no patches applied\n'))
            return 1
        patch = q.lookup('qtip')
    ph = patchheader(q.join(patch), q.plainmode)

    ui.write('\n'.join(ph.message) + '\n')

def lastsavename(path):
    (directory, base) = os.path.split(path)
    names = os.listdir(directory)
    namere = re.compile("%s.([0-9]+)" % base)
    maxindex = None
    maxname = None
    for f in names:
        m = namere.match(f)
        if m:
            index = int(m.group(1))
            if maxindex is None or index > maxindex:
                maxindex = index
                maxname = f
    if maxname:
        return (os.path.join(directory, maxname), maxindex)
    return (None, None)

def savename(path):
    (last, index) = lastsavename(path)
    if last is None:
        index = 0
    newpath = path + ".%d" % (index + 1)
    return newpath

def push(ui, repo, patch=None, **opts):
    """push the next patch onto the stack

    When -f/--force is applied, all local changes in patched files
    will be lost.

    Return 0 on succces.
    """
    q = repo.mq
    mergeq = None

    if opts.get('merge'):
        if opts.get('name'):
            newpath = repo.join(opts.get('name'))
        else:
            newpath, i = lastsavename(q.path)
        if not newpath:
            ui.warn(_("no saved queues found, please use -n\n"))
            return 1
        mergeq = queue(ui, repo.join(""), newpath)
        ui.warn(_("merging with queue at: %s\n") % mergeq.path)
    ret = q.push(repo, patch, force=opts.get('force'), list=opts.get('list'),
                 mergeq=mergeq, all=opts.get('all'), move=opts.get('move'))
    return ret

def pop(ui, repo, patch=None, **opts):
    """pop the current patch off the stack

    By default, pops off the top of the patch stack. If given a patch
    name, keeps popping off patches until the named patch is at the
    top of the stack.

    Return 0 on success.
    """
    localupdate = True
    if opts.get('name'):
        q = queue(ui, repo.join(""), repo.join(opts.get('name')))
        ui.warn(_('using patch queue: %s\n') % q.path)
        localupdate = False
    else:
        q = repo.mq
    ret = q.pop(repo, patch, force=opts.get('force'), update=localupdate,
                all=opts.get('all'))
    q.save_dirty()
    return ret

def rename(ui, repo, patch, name=None, **opts):
    """rename a patch

    With one argument, renames the current patch to PATCH1.
    With two arguments, renames PATCH1 to PATCH2.

    Returns 0 on success."""

    q = repo.mq

    if not name:
        name = patch
        patch = None

    if patch:
        patch = q.lookup(patch)
    else:
        if not q.applied:
            ui.write(_('no patches applied\n'))
            return
        patch = q.lookup('qtip')
    absdest = q.join(name)
    if os.path.isdir(absdest):
        name = normname(os.path.join(name, os.path.basename(patch)))
        absdest = q.join(name)
    if os.path.exists(absdest):
        raise util.Abort(_('%s already exists') % absdest)

    if name in q.series:
        raise util.Abort(
            _('A patch named %s already exists in the series file') % name)

    ui.note(_('renaming %s to %s\n') % (patch, name))
    i = q.find_series(patch)
    guards = q.guard_re.findall(q.full_series[i])
    q.full_series[i] = name + ''.join([' #' + g for g in guards])
    q.parse_series()
    q.series_dirty = 1

    info = q.isapplied(patch)
    if info:
        q.applied[info[0]] = statusentry(info[1], name)
    q.applied_dirty = 1

    destdir = os.path.dirname(absdest)
    if not os.path.isdir(destdir):
        os.makedirs(destdir)
    util.rename(q.join(patch), absdest)
    r = q.qrepo()
    if r and patch in r.dirstate:
        wctx = r[None]
        wlock = r.wlock()
        try:
            if r.dirstate[patch] == 'a':
                r.dirstate.forget(patch)
                r.dirstate.add(name)
            else:
                if r.dirstate[name] == 'r':
                    wctx.undelete([name])
                wctx.copy(patch, name)
                wctx.remove([patch], False)
        finally:
            wlock.release()

    q.save_dirty()

def restore(ui, repo, rev, **opts):
    """restore the queue state saved by a revision (DEPRECATED)

    This command is deprecated, use :hg:`rebase` instead."""
    rev = repo.lookup(rev)
    q = repo.mq
    q.restore(repo, rev, delete=opts.get('delete'),
              qupdate=opts.get('update'))
    q.save_dirty()
    return 0

def save(ui, repo, **opts):
    """save current queue state (DEPRECATED)

    This command is deprecated, use :hg:`rebase` instead."""
    q = repo.mq
    message = cmdutil.logmessage(opts)
    ret = q.save(repo, msg=message)
    if ret:
        return ret
    q.save_dirty()
    if opts.get('copy'):
        path = q.path
        if opts.get('name'):
            newpath = os.path.join(q.basepath, opts.get('name'))
            if os.path.exists(newpath):
                if not os.path.isdir(newpath):
                    raise util.Abort(_('destination %s exists and is not '
                                       'a directory') % newpath)
                if not opts.get('force'):
                    raise util.Abort(_('destination %s exists, '
                                       'use -f to force') % newpath)
        else:
            newpath = savename(path)
        ui.warn(_("copy %s to %s\n") % (path, newpath))
        util.copyfiles(path, newpath)
    if opts.get('empty'):
        try:
            os.unlink(q.join(q.status_path))
        except:
            pass
    return 0

def strip(ui, repo, *revs, **opts):
    """strip changesets and all their descendants from the repository

    The strip command removes the specified changesets and all their
    descendants. If the working directory has uncommitted changes,
    the operation is aborted unless the --force flag is supplied.

    If a parent of the working directory is stripped, then the working
    directory will automatically be updated to the most recent
    available ancestor of the stripped parent after the operation
    completes.

    Any stripped changesets are stored in ``.hg/strip-backup`` as a
    bundle (see :hg:`help bundle` and :hg:`help unbundle`). They can
    be restored by running :hg:`unbundle .hg/strip-backup/BUNDLE`,
    where BUNDLE is the bundle file created by the strip. Note that
    the local revision numbers will in general be different after the
    restore.

    Use the --no-backup option to discard the backup bundle once the
    operation completes.

    Return 0 on success.
    """
    backup = 'all'
    if opts.get('backup'):
        backup = 'strip'
    elif opts.get('no_backup') or opts.get('nobackup'):
        backup = 'none'

    cl = repo.changelog
    revs = set(cmdutil.revrange(repo, revs))
    if not revs:
        raise util.Abort(_('empty revision set'))

    descendants = set(cl.descendants(*revs))
    strippedrevs = revs.union(descendants)
    roots = revs.difference(descendants)

    update = False
    # if one of the wdir parent is stripped we'll need
    # to update away to an earlier revision
    for p in repo.dirstate.parents():
        if p != nullid and cl.rev(p) in strippedrevs:
            update = True
            break

    rootnodes = set(cl.node(r) for r in roots)

    q = repo.mq
    if q.applied:
        # refresh queue state if we're about to strip
        # applied patches
        if cl.rev(repo.lookup('qtip')) in strippedrevs:
            q.applied_dirty = True
            start = 0
            end = len(q.applied)
            for i, statusentry in enumerate(q.applied):
                if statusentry.node in rootnodes:
                    # if one of the stripped roots is an applied
                    # patch, only part of the queue is stripped
                    start = i
                    break
            del q.applied[start:end]
            q.save_dirty()

    revs = list(rootnodes)
    if update and opts.get('keep'):
        wlock = repo.wlock()
        try:
            urev = repo.mq.qparents(repo, revs[0])
            repo.dirstate.rebuild(urev, repo[urev].manifest())
            repo.dirstate.write()
            update = False
        finally:
            wlock.release()

    repo.mq.strip(repo, revs, backup=backup, update=update,
                  force=opts.get('force'))
    return 0

def select(ui, repo, *args, **opts):
    '''set or print guarded patches to push

    Use the :hg:`qguard` command to set or print guards on patch, then use
    qselect to tell mq which guards to use. A patch will be pushed if
    it has no guards or any positive guards match the currently
    selected guard, but will not be pushed if any negative guards
    match the current guard. For example::

        qguard foo.patch -stable    (negative guard)
        qguard bar.patch +stable    (positive guard)
        qselect stable

    This activates the "stable" guard. mq will skip foo.patch (because
    it has a negative match) but push bar.patch (because it has a
    positive match).

    With no arguments, prints the currently active guards.
    With one argument, sets the active guard.

    Use -n/--none to deactivate guards (no other arguments needed).
    When no guards are active, patches with positive guards are
    skipped and patches with negative guards are pushed.

    qselect can change the guards on applied patches. It does not pop
    guarded patches by default. Use --pop to pop back to the last
    applied patch that is not guarded. Use --reapply (which implies
    --pop) to push back to the current patch afterwards, but skip
    guarded patches.

    Use -s/--series to print a list of all guards in the series file
    (no other arguments needed). Use -v for more information.

    Returns 0 on success.'''

    q = repo.mq
    guards = q.active()
    if args or opts.get('none'):
        old_unapplied = q.unapplied(repo)
        old_guarded = [i for i in xrange(len(q.applied)) if
                       not q.pushable(i)[0]]
        q.set_active(args)
        q.save_dirty()
        if not args:
            ui.status(_('guards deactivated\n'))
        if not opts.get('pop') and not opts.get('reapply'):
            unapplied = q.unapplied(repo)
            guarded = [i for i in xrange(len(q.applied))
                       if not q.pushable(i)[0]]
            if len(unapplied) != len(old_unapplied):
                ui.status(_('number of unguarded, unapplied patches has '
                            'changed from %d to %d\n') %
                          (len(old_unapplied), len(unapplied)))
            if len(guarded) != len(old_guarded):
                ui.status(_('number of guarded, applied patches has changed '
                            'from %d to %d\n') %
                          (len(old_guarded), len(guarded)))
    elif opts.get('series'):
        guards = {}
        noguards = 0
        for gs in q.series_guards:
            if not gs:
                noguards += 1
            for g in gs:
                guards.setdefault(g, 0)
                guards[g] += 1
        if ui.verbose:
            guards['NONE'] = noguards
        guards = guards.items()
        guards.sort(key=lambda x: x[0][1:])
        if guards:
            ui.note(_('guards in series file:\n'))
            for guard, count in guards:
                ui.note('%2d  ' % count)
                ui.write(guard, '\n')
        else:
            ui.note(_('no guards in series file\n'))
    else:
        if guards:
            ui.note(_('active guards:\n'))
            for g in guards:
                ui.write(g, '\n')
        else:
            ui.write(_('no active guards\n'))
    reapply = opts.get('reapply') and q.applied and q.appliedname(-1)
    popped = False
    if opts.get('pop') or opts.get('reapply'):
        for i in xrange(len(q.applied)):
            pushable, reason = q.pushable(i)
            if not pushable:
                ui.status(_('popping guarded patches\n'))
                popped = True
                if i == 0:
                    q.pop(repo, all=True)
                else:
                    q.pop(repo, i - 1)
                break
    if popped:
        try:
            if reapply:
                ui.status(_('reapplying unguarded patches\n'))
                q.push(repo, reapply)
        finally:
            q.save_dirty()

def finish(ui, repo, *revrange, **opts):
    """move applied patches into repository history

    Finishes the specified revisions (corresponding to applied
    patches) by moving them out of mq control into regular repository
    history.

    Accepts a revision range or the -a/--applied option. If --applied
    is specified, all applied mq revisions are removed from mq
    control. Otherwise, the given revisions must be at the base of the
    stack of applied patches.

    This can be especially useful if your changes have been applied to
    an upstream repository, or if you are about to push your changes
    to upstream.

    Returns 0 on success.
    """
    if not opts.get('applied') and not revrange:
        raise util.Abort(_('no revisions specified'))
    elif opts.get('applied'):
        revrange = ('qbase::qtip',) + revrange

    q = repo.mq
    if not q.applied:
        ui.status(_('no patches applied\n'))
        return 0

    revs = cmdutil.revrange(repo, revrange)
    q.finish(repo, revs)
    q.save_dirty()
    return 0

def qqueue(ui, repo, name=None, **opts):
    '''manage multiple patch queues

    Supports switching between different patch queues, as well as creating
    new patch queues and deleting existing ones.

    Omitting a queue name or specifying -l/--list will show you the registered
    queues - by default the "normal" patches queue is registered. The currently
    active queue will be marked with "(active)".

    To create a new queue, use -c/--create. The queue is automatically made
    active, except in the case where there are applied patches from the
    currently active queue in the repository. Then the queue will only be
    created and switching will fail.

    To delete an existing queue, use --delete. You cannot delete the currently
    active queue.

    Returns 0 on success.
    '''

    q = repo.mq

    _defaultqueue = 'patches'
    _allqueues = 'patches.queues'
    _activequeue = 'patches.queue'

    def _getcurrent():
        cur = os.path.basename(q.path)
        if cur.startswith('patches-'):
            cur = cur[8:]
        return cur

    def _noqueues():
        try:
            fh = repo.opener(_allqueues, 'r')
            fh.close()
        except IOError:
            return True

        return False

    def _getqueues():
        current = _getcurrent()

        try:
            fh = repo.opener(_allqueues, 'r')
            queues = [queue.strip() for queue in fh if queue.strip()]
            if current not in queues:
                queues.append(current)
        except IOError:
            queues = [_defaultqueue]

        return sorted(queues)

    def _setactive(name):
        if q.applied:
            raise util.Abort(_('patches applied - cannot set new queue active'))
        _setactivenocheck(name)

    def _setactivenocheck(name):
        fh = repo.opener(_activequeue, 'w')
        if name != 'patches':
            fh.write(name)
        fh.close()

    def _addqueue(name):
        fh = repo.opener(_allqueues, 'a')
        fh.write('%s\n' % (name,))
        fh.close()

    def _queuedir(name):
        if name == 'patches':
            return repo.join('patches')
        else:
            return repo.join('patches-' + name)

    def _validname(name):
        for n in name:
            if n in ':\\/.':
                return False
        return True

    def _delete(name):
        if name not in existing:
            raise util.Abort(_('cannot delete queue that does not exist'))

        current = _getcurrent()

        if name == current:
            raise util.Abort(_('cannot delete currently active queue'))

        fh = repo.opener('patches.queues.new', 'w')
        for queue in existing:
            if queue == name:
                continue
            fh.write('%s\n' % (queue,))
        fh.close()
        util.rename(repo.join('patches.queues.new'), repo.join(_allqueues))

    if not name or opts.get('list'):
        current = _getcurrent()
        for queue in _getqueues():
            ui.write('%s' % (queue,))
            if queue == current and not ui.quiet:
                ui.write(_(' (active)\n'))
            else:
                ui.write('\n')
        return

    if not _validname(name):
        raise util.Abort(
                _('invalid queue name, may not contain the characters ":\\/."'))

    existing = _getqueues()

    if opts.get('create'):
        if name in existing:
            raise util.Abort(_('queue "%s" already exists') % name)
        if _noqueues():
            _addqueue(_defaultqueue)
        _addqueue(name)
        _setactive(name)
    elif opts.get('rename'):
        current = _getcurrent()
        if name == current:
            raise util.Abort(_('can\'t rename "%s" to its current name') % name)
        if name in existing:
            raise util.Abort(_('queue "%s" already exists') % name)

        olddir = _queuedir(current)
        newdir = _queuedir(name)

        if os.path.exists(newdir):
            raise util.Abort(_('non-queue directory "%s" already exists') %
                    newdir)

        fh = repo.opener('patches.queues.new', 'w')
        for queue in existing:
            if queue == current:
                fh.write('%s\n' % (name,))
                if os.path.exists(olddir):
                    util.rename(olddir, newdir)
            else:
                fh.write('%s\n' % (queue,))
        fh.close()
        util.rename(repo.join('patches.queues.new'), repo.join(_allqueues))
        _setactivenocheck(name)
    elif opts.get('delete'):
        _delete(name)
    elif opts.get('purge'):
        if name in existing:
            _delete(name)
        qdir = _queuedir(name)
        if os.path.exists(qdir):
            shutil.rmtree(qdir)
    else:
        if name not in existing:
            raise util.Abort(_('use --create to create a new queue'))
        _setactive(name)

def reposetup(ui, repo):
    class mqrepo(repo.__class__):
        @util.propertycache
        def mq(self):
            return queue(self.ui, self.join(""))

        def abort_if_wdir_patched(self, errmsg, force=False):
            if self.mq.applied and not force:
                parent = self.dirstate.parents()[0]
                if parent in [s.node for s in self.mq.applied]:
                    raise util.Abort(errmsg)

        def commit(self, text="", user=None, date=None, match=None,
                   force=False, editor=False, extra={}):
            self.abort_if_wdir_patched(
                _('cannot commit over an applied mq patch'),
                force)

            return super(mqrepo, self).commit(text, user, date, match, force,
                                              editor, extra)

        def push(self, remote, force=False, revs=None, newbranch=False):
            if self.mq.applied and not force:
                haspatches = True
                if revs:
                    # Assume applied patches have no non-patch descendants
                    # and are not on remote already. If they appear in the
                    # set of resolved 'revs', bail out.
                    applied = set(e.node for e in self.mq.applied)
                    haspatches = bool([n for n in revs if n in applied])
                if haspatches:
                    raise util.Abort(_('source has mq patches applied'))
            return super(mqrepo, self).push(remote, force, revs, newbranch)

        def _findtags(self):
            '''augment tags from base class with patch tags'''
            result = super(mqrepo, self)._findtags()

            q = self.mq
            if not q.applied:
                return result

            mqtags = [(patch.node, patch.name) for patch in q.applied]

            if mqtags[-1][0] not in self.changelog.nodemap:
                self.ui.warn(_('mq status file refers to unknown node %s\n')
                             % short(mqtags[-1][0]))
                return result

            mqtags.append((mqtags[-1][0], 'qtip'))
            mqtags.append((mqtags[0][0], 'qbase'))
            mqtags.append((self.changelog.parents(mqtags[0][0])[0], 'qparent'))
            tags = result[0]
            for patch in mqtags:
                if patch[1] in tags:
                    self.ui.warn(_('Tag %s overrides mq patch of the same name\n')
                                 % patch[1])
                else:
                    tags[patch[1]] = patch[0]

            return result

        def _branchtags(self, partial, lrev):
            q = self.mq
            if not q.applied:
                return super(mqrepo, self)._branchtags(partial, lrev)

            cl = self.changelog
            qbasenode = q.applied[0].node
            if qbasenode not in cl.nodemap:
                self.ui.warn(_('mq status file refers to unknown node %s\n')
                             % short(qbasenode))
                return super(mqrepo, self)._branchtags(partial, lrev)

            qbase = cl.rev(qbasenode)
            start = lrev + 1
            if start < qbase:
                # update the cache (excluding the patches) and save it
                ctxgen = (self[r] for r in xrange(lrev + 1, qbase))
                self._updatebranchcache(partial, ctxgen)
                self._writebranchcache(partial, cl.node(qbase - 1), qbase - 1)
                start = qbase
            # if start = qbase, the cache is as updated as it should be.
            # if start > qbase, the cache includes (part of) the patches.
            # we might as well use it, but we won't save it.

            # update the cache up to the tip
            ctxgen = (self[r] for r in xrange(start, len(cl)))
            self._updatebranchcache(partial, ctxgen)

            return partial

    if repo.local():
        repo.__class__ = mqrepo

def mqimport(orig, ui, repo, *args, **kwargs):
    if (hasattr(repo, 'abort_if_wdir_patched')
        and not kwargs.get('no_commit', False)):
        repo.abort_if_wdir_patched(_('cannot import over an applied patch'),
                                   kwargs.get('force'))
    return orig(ui, repo, *args, **kwargs)

def mqinit(orig, ui, *args, **kwargs):
    mq = kwargs.pop('mq', None)

    if not mq:
        return orig(ui, *args, **kwargs)

    if args:
        repopath = args[0]
        if not hg.islocal(repopath):
            raise util.Abort(_('only a local queue repository '
                               'may be initialized'))
    else:
        repopath = cmdutil.findrepo(os.getcwd())
        if not repopath:
            raise util.Abort(_('there is no Mercurial repository here '
                               '(.hg not found)'))
    repo = hg.repository(ui, repopath)
    return qinit(ui, repo, True)

def mqcommand(orig, ui, repo, *args, **kwargs):
    """Add --mq option to operate on patch repository instead of main"""

    # some commands do not like getting unknown options
    mq = kwargs.pop('mq', None)

    if not mq:
        return orig(ui, repo, *args, **kwargs)

    q = repo.mq
    r = q.qrepo()
    if not r:
        raise util.Abort(_('no queue repository'))
    return orig(r.ui, r, *args, **kwargs)

def summary(orig, ui, repo, *args, **kwargs):
    r = orig(ui, repo, *args, **kwargs)
    q = repo.mq
    m = []
    a, u = len(q.applied), len(q.unapplied(repo))
    if a:
        m.append(ui.label(_("%d applied"), 'qseries.applied') % a)
    if u:
        m.append(ui.label(_("%d unapplied"), 'qseries.unapplied') % u)
    if m:
        ui.write("mq:     %s\n" % ', '.join(m))
    else:
        ui.note(_("mq:     (empty queue)\n"))
    return r

def uisetup(ui):
    mqopt = [('', 'mq', None, _("operate on patch repository"))]

    extensions.wrapcommand(commands.table, 'import', mqimport)
    extensions.wrapcommand(commands.table, 'summary', summary)

    entry = extensions.wrapcommand(commands.table, 'init', mqinit)
    entry[1].extend(mqopt)

    nowrap = set(commands.norepo.split(" ") + ['qrecord'])

    def dotable(cmdtable):
        for cmd in cmdtable.keys():
            cmd = cmdutil.parsealiases(cmd)[0]
            if cmd in nowrap:
                continue
            entry = extensions.wrapcommand(cmdtable, cmd, mqcommand)
            entry[1].extend(mqopt)

    dotable(commands.table)

    for extname, extmodule in extensions.extensions():
        if extmodule.__file__ != __file__:
            dotable(getattr(extmodule, 'cmdtable', {}))

seriesopts = [('s', 'summary', None, _('print first line of patch header'))]

cmdtable = {
    "qapplied":
        (applied,
         [('1', 'last', None, _('show only the last patch'))] + seriesopts,
         _('hg qapplied [-1] [-s] [PATCH]')),
    "qclone":
        (clone,
         [('', 'pull', None, _('use pull protocol to copy metadata')),
          ('U', 'noupdate', None, _('do not update the new working directories')),
          ('', 'uncompressed', None,
           _('use uncompressed transfer (fast over LAN)')),
          ('p', 'patches', '',
           _('location of source patch repository'), _('REPO')),
         ] + commands.remoteopts,
         _('hg qclone [OPTION]... SOURCE [DEST]')),
    "qcommit|qci":
        (commit,
         commands.table["^commit|ci"][1],
         _('hg qcommit [OPTION]... [FILE]...')),
    "^qdiff":
        (diff,
         commands.diffopts + commands.diffopts2 + commands.walkopts,
         _('hg qdiff [OPTION]... [FILE]...')),
    "qdelete|qremove|qrm":
        (delete,
         [('k', 'keep', None, _('keep patch file')),
          ('r', 'rev', [],
           _('stop managing a revision (DEPRECATED)'), _('REV'))],
         _('hg qdelete [-k] [PATCH]...')),
    'qfold':
        (fold,
         [('e', 'edit', None, _('edit patch header')),
          ('k', 'keep', None, _('keep folded patch files')),
         ] + commands.commitopts,
         _('hg qfold [-e] [-k] [-m TEXT] [-l FILE] PATCH...')),
    'qgoto':
        (goto,
         [('f', 'force', None, _('overwrite any local changes'))],
         _('hg qgoto [OPTION]... PATCH')),
    'qguard':
        (guard,
         [('l', 'list', None, _('list all patches and guards')),
          ('n', 'none', None, _('drop all guards'))],
         _('hg qguard [-l] [-n] [PATCH] [-- [+GUARD]... [-GUARD]...]')),
    'qheader': (header, [], _('hg qheader [PATCH]')),
    "qimport":
        (qimport,
         [('e', 'existing', None, _('import file in patch directory')),
          ('n', 'name', '',
           _('name of patch file'), _('NAME')),
          ('f', 'force', None, _('overwrite existing files')),
          ('r', 'rev', [],
           _('place existing revisions under mq control'), _('REV')),
          ('g', 'git', None, _('use git extended diff format')),
          ('P', 'push', None, _('qpush after importing'))],
         _('hg qimport [-e] [-n NAME] [-f] [-g] [-P] [-r REV]... FILE...')),
    "^qinit":
        (init,
         [('c', 'create-repo', None, _('create queue repository'))],
         _('hg qinit [-c]')),
    "^qnew":
        (new,
         [('e', 'edit', None, _('edit commit message')),
          ('f', 'force', None, _('import uncommitted changes (DEPRECATED)')),
          ('g', 'git', None, _('use git extended diff format')),
          ('U', 'currentuser', None, _('add "From: <current user>" to patch')),
          ('u', 'user', '',
           _('add "From: <USER>" to patch'), _('USER')),
          ('D', 'currentdate', None, _('add "Date: <current date>" to patch')),
          ('d', 'date', '',
           _('add "Date: <DATE>" to patch'), _('DATE'))
          ] + commands.walkopts + commands.commitopts,
         _('hg qnew [-e] [-m TEXT] [-l FILE] PATCH [FILE]...')),
    "qnext": (next, [] + seriesopts, _('hg qnext [-s]')),
    "qprev": (prev, [] + seriesopts, _('hg qprev [-s]')),
    "^qpop":
        (pop,
         [('a', 'all', None, _('pop all patches')),
          ('n', 'name', '',
           _('queue name to pop (DEPRECATED)'), _('NAME')),
          ('f', 'force', None, _('forget any local changes to patched files'))],
         _('hg qpop [-a] [-f] [PATCH | INDEX]')),
    "^qpush":
        (push,
         [('f', 'force', None, _('apply on top of local changes')),
          ('l', 'list', None, _('list patch name in commit text')),
          ('a', 'all', None, _('apply all patches')),
          ('m', 'merge', None, _('merge from another queue (DEPRECATED)')),
          ('n', 'name', '',
           _('merge queue name (DEPRECATED)'), _('NAME')),
          ('', 'move', None, _('reorder patch series and apply only the patch'))],
         _('hg qpush [-f] [-l] [-a] [--move] [PATCH | INDEX]')),
    "^qrefresh":
        (refresh,
         [('e', 'edit', None, _('edit commit message')),
          ('g', 'git', None, _('use git extended diff format')),
          ('s', 'short', None,
           _('refresh only files already in the patch and specified files')),
          ('U', 'currentuser', None,
           _('add/update author field in patch with current user')),
          ('u', 'user', '',
           _('add/update author field in patch with given user'), _('USER')),
          ('D', 'currentdate', None,
           _('add/update date field in patch with current date')),
          ('d', 'date', '',
           _('add/update date field in patch with given date'), _('DATE'))
          ] + commands.walkopts + commands.commitopts,
         _('hg qrefresh [-I] [-X] [-e] [-m TEXT] [-l FILE] [-s] [FILE]...')),
    'qrename|qmv':
        (rename, [], _('hg qrename PATCH1 [PATCH2]')),
    "qrestore":
        (restore,
         [('d', 'delete', None, _('delete save entry')),
          ('u', 'update', None, _('update queue working directory'))],
         _('hg qrestore [-d] [-u] REV')),
    "qsave":
        (save,
         [('c', 'copy', None, _('copy patch directory')),
          ('n', 'name', '',
           _('copy directory name'), _('NAME')),
          ('e', 'empty', None, _('clear queue status file')),
          ('f', 'force', None, _('force copy'))] + commands.commitopts,
         _('hg qsave [-m TEXT] [-l FILE] [-c] [-n NAME] [-e] [-f]')),
    "qselect":
        (select,
         [('n', 'none', None, _('disable all guards')),
          ('s', 'series', None, _('list all guards in series file')),
          ('', 'pop', None, _('pop to before first guarded applied patch')),
          ('', 'reapply', None, _('pop, then reapply patches'))],
         _('hg qselect [OPTION]... [GUARD]...')),
    "qseries":
        (series,
         [('m', 'missing', None, _('print patches not in series')),
         ] + seriesopts,
          _('hg qseries [-ms]')),
     "strip":
         (strip,
         [('f', 'force', None, _('force removal of changesets even if the '
                                 'working directory has uncommitted changes')),
          ('b', 'backup', None, _('bundle only changesets with local revision'
                                  ' number greater than REV which are not'
                                  ' descendants of REV (DEPRECATED)')),
          ('n', 'no-backup', None, _('no backups')),
          ('', 'nobackup', None, _('no backups (DEPRECATED)')),
          ('k', 'keep', None, _("do not modify working copy during strip"))],
          _('hg strip [-k] [-f] [-n] REV...')),
     "qtop": (top, [] + seriesopts, _('hg qtop [-s]')),
    "qunapplied":
        (unapplied,
         [('1', 'first', None, _('show only the first patch'))] + seriesopts,
         _('hg qunapplied [-1] [-s] [PATCH]')),
    "qfinish":
        (finish,
         [('a', 'applied', None, _('finish all applied changesets'))],
         _('hg qfinish [-a] [REV]...')),
    'qqueue':
        (qqueue,
         [
             ('l', 'list', False, _('list all available queues')),
             ('c', 'create', False, _('create new queue')),
             ('', 'rename', False, _('rename active queue')),
             ('', 'delete', False, _('delete reference to queue')),
             ('', 'purge', False, _('delete queue, and remove patch dir')),
         ],
         _('[OPTION] [QUEUE]')),
}

colortable = {'qguard.negative': 'red',
              'qguard.positive': 'yellow',
              'qguard.unguarded': 'green',
              'qseries.applied': 'blue bold underline',
              'qseries.guarded': 'black bold',
              'qseries.missing': 'red bold',
              'qseries.unapplied': 'black bold'}
