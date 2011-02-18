# dispatch.py - command dispatching for mercurial
#
# Copyright 2005-2007 Matt Mackall <mpm@selenic.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from i18n import _
import os, sys, atexit, signal, pdb, socket, errno, shlex, time, traceback, re
import util, commands, hg, fancyopts, extensions, hook, error
import cmdutil, encoding
import ui as uimod

def run():
    "run the command in sys.argv"
    sys.exit(dispatch(sys.argv[1:]))

def dispatch(args):
    "run the command specified in args"
    try:
        u = uimod.ui()
        if '--traceback' in args:
            u.setconfig('ui', 'traceback', 'on')
    except util.Abort, inst:
        sys.stderr.write(_("abort: %s\n") % inst)
        if inst.hint:
            sys.stderr.write(_("(%s)\n") % inst.hint)
        return -1
    except error.ParseError, inst:
        if len(inst.args) > 1:
            sys.stderr.write(_("hg: parse error at %s: %s\n") %
                             (inst.args[1], inst.args[0]))
        else:
            sys.stderr.write(_("hg: parse error: %s\n") % inst.args[0])
        return -1
    return _runcatch(u, args)

def _runcatch(ui, args):
    def catchterm(*args):
        raise error.SignalInterrupt

    try:
        for name in 'SIGBREAK', 'SIGHUP', 'SIGTERM':
            num = getattr(signal, name, None)
            if num:
                signal.signal(num, catchterm)
    except ValueError:
        pass # happens if called in a thread

    try:
        try:
            # enter the debugger before command execution
            if '--debugger' in args:
                ui.warn(_("entering debugger - "
                        "type c to continue starting hg or h for help\n"))
                pdb.set_trace()
            try:
                return _dispatch(ui, args)
            finally:
                ui.flush()
        except:
            # enter the debugger when we hit an exception
            if '--debugger' in args:
                traceback.print_exc()
                pdb.post_mortem(sys.exc_info()[2])
            ui.traceback()
            raise

    # Global exception handling, alphabetically
    # Mercurial-specific first, followed by built-in and library exceptions
    except error.AmbiguousCommand, inst:
        ui.warn(_("hg: command '%s' is ambiguous:\n    %s\n") %
                (inst.args[0], " ".join(inst.args[1])))
    except error.ParseError, inst:
        if len(inst.args) > 1:
            ui.warn(_("hg: parse error at %s: %s\n") %
                             (inst.args[1], inst.args[0]))
        else:
            ui.warn(_("hg: parse error: %s\n") % inst.args[0])
        return -1
    except error.LockHeld, inst:
        if inst.errno == errno.ETIMEDOUT:
            reason = _('timed out waiting for lock held by %s') % inst.locker
        else:
            reason = _('lock held by %s') % inst.locker
        ui.warn(_("abort: %s: %s\n") % (inst.desc or inst.filename, reason))
    except error.LockUnavailable, inst:
        ui.warn(_("abort: could not lock %s: %s\n") %
               (inst.desc or inst.filename, inst.strerror))
    except error.CommandError, inst:
        if inst.args[0]:
            ui.warn(_("hg %s: %s\n") % (inst.args[0], inst.args[1]))
            commands.help_(ui, inst.args[0])
        else:
            ui.warn(_("hg: %s\n") % inst.args[1])
            commands.help_(ui, 'shortlist')
    except error.RepoError, inst:
        ui.warn(_("abort: %s!\n") % inst)
    except error.ResponseError, inst:
        ui.warn(_("abort: %s") % inst.args[0])
        if not isinstance(inst.args[1], basestring):
            ui.warn(" %r\n" % (inst.args[1],))
        elif not inst.args[1]:
            ui.warn(_(" empty string\n"))
        else:
            ui.warn("\n%r\n" % util.ellipsis(inst.args[1]))
    except error.RevlogError, inst:
        ui.warn(_("abort: %s!\n") % inst)
    except error.SignalInterrupt:
        ui.warn(_("killed!\n"))
    except error.UnknownCommand, inst:
        ui.warn(_("hg: unknown command '%s'\n") % inst.args[0])
        try:
            # check if the command is in a disabled extension
            # (but don't check for extensions themselves)
            commands.help_(ui, inst.args[0], unknowncmd=True)
        except error.UnknownCommand:
            commands.help_(ui, 'shortlist')
    except util.Abort, inst:
        ui.warn(_("abort: %s\n") % inst)
        if inst.hint:
            ui.warn(_("(%s)\n") % inst.hint)
    except ImportError, inst:
        ui.warn(_("abort: %s!\n") % inst)
        m = str(inst).split()[-1]
        if m in "mpatch bdiff".split():
            ui.warn(_("(did you forget to compile extensions?)\n"))
        elif m in "zlib".split():
            ui.warn(_("(is your Python install correct?)\n"))
    except IOError, inst:
        if hasattr(inst, "code"):
            ui.warn(_("abort: %s\n") % inst)
        elif hasattr(inst, "reason"):
            try: # usually it is in the form (errno, strerror)
                reason = inst.reason.args[1]
            except: # it might be anything, for example a string
                reason = inst.reason
            ui.warn(_("abort: error: %s\n") % reason)
        elif hasattr(inst, "args") and inst.args[0] == errno.EPIPE:
            if ui.debugflag:
                ui.warn(_("broken pipe\n"))
        elif getattr(inst, "strerror", None):
            if getattr(inst, "filename", None):
                ui.warn(_("abort: %s: %s\n") % (inst.strerror, inst.filename))
            else:
                ui.warn(_("abort: %s\n") % inst.strerror)
        else:
            raise
    except OSError, inst:
        if getattr(inst, "filename", None):
            ui.warn(_("abort: %s: %s\n") % (inst.strerror, inst.filename))
        else:
            ui.warn(_("abort: %s\n") % inst.strerror)
    except KeyboardInterrupt:
        try:
            ui.warn(_("interrupted!\n"))
        except IOError, inst:
            if inst.errno == errno.EPIPE:
                if ui.debugflag:
                    ui.warn(_("\nbroken pipe\n"))
            else:
                raise
    except MemoryError:
        ui.warn(_("abort: out of memory\n"))
    except SystemExit, inst:
        # Commands shouldn't sys.exit directly, but give a return code.
        # Just in case catch this and and pass exit code to caller.
        return inst.code
    except socket.error, inst:
        ui.warn(_("abort: %s\n") % inst.args[-1])
    except:
        ui.warn(_("** unknown exception encountered,"
                  " please report by visiting\n"))
        ui.warn(_("**  http://mercurial.selenic.com/wiki/BugTracker\n"))
        ui.warn(_("** Python %s\n") % sys.version.replace('\n', ''))
        ui.warn(_("** Mercurial Distributed SCM (version %s)\n")
               % util.version())
        ui.warn(_("** Extensions loaded: %s\n")
               % ", ".join([x[0] for x in extensions.extensions()]))
        raise

    return -1

def aliasargs(fn):
    if hasattr(fn, 'args'):
        return fn.args
    return []

class cmdalias(object):
    def __init__(self, name, definition, cmdtable):
        self.name = self.cmd = name
        self.cmdname = ''
        self.definition = definition
        self.args = []
        self.opts = []
        self.help = ''
        self.norepo = True
        self.badalias = False

        try:
            aliases, entry = cmdutil.findcmd(self.name, cmdtable)
            for alias, e in cmdtable.iteritems():
                if e is entry:
                    self.cmd = alias
                    break
            self.shadows = True
        except error.UnknownCommand:
            self.shadows = False

        if not self.definition:
            def fn(ui, *args):
                ui.warn(_("no definition for alias '%s'\n") % self.name)
                return 1
            self.fn = fn
            self.badalias = True

            return

        if self.definition.startswith('!'):
            self.shell = True
            def fn(ui, *args):
                env = {'HG_ARGS': ' '.join((self.name,) + args)}
                def _checkvar(m):
                    if int(m.groups()[0]) <= len(args):
                        return m.group()
                    else:
                        return ''
                cmd = re.sub(r'\$(\d+)', _checkvar, self.definition[1:])
                replace = dict((str(i + 1), arg) for i, arg in enumerate(args))
                replace['0'] = self.name
                replace['@'] = ' '.join(args)
                cmd = util.interpolate(r'\$', replace, cmd)
                return util.system(cmd, environ=env)
            self.fn = fn
            return

        args = shlex.split(self.definition)
        self.cmdname = cmd = args.pop(0)
        args = map(util.expandpath, args)

        for invalidarg in ("--cwd", "-R", "--repository", "--repo"):
            if _earlygetopt([invalidarg], args):
                def fn(ui, *args):
                    ui.warn(_("error in definition for alias '%s': %s may only "
                              "be given on the command line\n")
                            % (self.name, invalidarg))
                    return 1

                self.fn = fn
                self.badalias = True
                return

        try:
            tableentry = cmdutil.findcmd(cmd, cmdtable, False)[1]
            if len(tableentry) > 2:
                self.fn, self.opts, self.help = tableentry
            else:
                self.fn, self.opts = tableentry

            self.args = aliasargs(self.fn) + args
            if cmd not in commands.norepo.split(' '):
                self.norepo = False
            if self.help.startswith("hg " + cmd):
                # drop prefix in old-style help lines so hg shows the alias
                self.help = self.help[4 + len(cmd):]
            self.__doc__ = self.fn.__doc__

        except error.UnknownCommand:
            def fn(ui, *args):
                ui.warn(_("alias '%s' resolves to unknown command '%s'\n") \
                            % (self.name, cmd))
                try:
                    # check if the command is in a disabled extension
                    commands.help_(ui, cmd, unknowncmd=True)
                except error.UnknownCommand:
                    pass
                return 1
            self.fn = fn
            self.badalias = True
        except error.AmbiguousCommand:
            def fn(ui, *args):
                ui.warn(_("alias '%s' resolves to ambiguous command '%s'\n") \
                            % (self.name, cmd))
                return 1
            self.fn = fn
            self.badalias = True

    def __call__(self, ui, *args, **opts):
        if self.shadows:
            ui.debug("alias '%s' shadows command '%s'\n" %
                     (self.name, self.cmdname))

        if self.definition.startswith('!'):
            return self.fn(ui, *args, **opts)
        else:
            try:
                util.checksignature(self.fn)(ui, *args, **opts)
            except error.SignatureError:
                args = ' '.join([self.cmdname] + self.args)
                ui.debug("alias '%s' expands to '%s'\n" % (self.name, args))
                raise

def addaliases(ui, cmdtable):
    # aliases are processed after extensions have been loaded, so they
    # may use extension commands. Aliases can also use other alias definitions,
    # but only if they have been defined prior to the current definition.
    for alias, definition in ui.configitems('alias'):
        aliasdef = cmdalias(alias, definition, cmdtable)
        cmdtable[aliasdef.cmd] = (aliasdef, aliasdef.opts, aliasdef.help)
        if aliasdef.norepo:
            commands.norepo += ' %s' % alias

def _parse(ui, args):
    options = {}
    cmdoptions = {}

    try:
        args = fancyopts.fancyopts(args, commands.globalopts, options)
    except fancyopts.getopt.GetoptError, inst:
        raise error.CommandError(None, inst)

    if args:
        cmd, args = args[0], args[1:]
        aliases, entry = cmdutil.findcmd(cmd, commands.table,
                                     ui.config("ui", "strict"))
        cmd = aliases[0]
        args = aliasargs(entry[0]) + args
        defaults = ui.config("defaults", cmd)
        if defaults:
            args = map(util.expandpath, shlex.split(defaults)) + args
        c = list(entry[1])
    else:
        cmd = None
        c = []

    # combine global options into local
    for o in commands.globalopts:
        c.append((o[0], o[1], options[o[1]], o[3]))

    try:
        args = fancyopts.fancyopts(args, c, cmdoptions, True)
    except fancyopts.getopt.GetoptError, inst:
        raise error.CommandError(cmd, inst)

    # separate global options back out
    for o in commands.globalopts:
        n = o[1]
        options[n] = cmdoptions[n]
        del cmdoptions[n]

    return (cmd, cmd and entry[0] or None, args, options, cmdoptions)

def _parseconfig(ui, config):
    """parse the --config options from the command line"""
    for cfg in config:
        try:
            name, value = cfg.split('=', 1)
            section, name = name.split('.', 1)
            if not section or not name:
                raise IndexError
            ui.setconfig(section, name, value)
        except (IndexError, ValueError):
            raise util.Abort(_('malformed --config option: %r '
                               '(use --config section.name=value)') % cfg)

def _earlygetopt(aliases, args):
    """Return list of values for an option (or aliases).

    The values are listed in the order they appear in args.
    The options and values are removed from args.
    """
    try:
        argcount = args.index("--")
    except ValueError:
        argcount = len(args)
    shortopts = [opt for opt in aliases if len(opt) == 2]
    values = []
    pos = 0
    while pos < argcount:
        if args[pos] in aliases:
            if pos + 1 >= argcount:
                # ignore and let getopt report an error if there is no value
                break
            del args[pos]
            values.append(args.pop(pos))
            argcount -= 2
        elif args[pos][:2] in shortopts:
            # short option can have no following space, e.g. hg log -Rfoo
            values.append(args.pop(pos)[2:])
            argcount -= 1
        else:
            pos += 1
    return values

def runcommand(lui, repo, cmd, fullargs, ui, options, d, cmdpats, cmdoptions):
    # run pre-hook, and abort if it fails
    ret = hook.hook(lui, repo, "pre-%s" % cmd, False, args=" ".join(fullargs),
                    pats=cmdpats, opts=cmdoptions)
    if ret:
        return ret
    ret = _runcommand(ui, options, cmd, d)
    # run post-hook, passing command result
    hook.hook(lui, repo, "post-%s" % cmd, False, args=" ".join(fullargs),
              result=ret, pats=cmdpats, opts=cmdoptions)
    return ret

def _getlocal(ui, rpath):
    """Return (path, local ui object) for the given target path.

    Takes paths in [cwd]/.hg/hgrc into account."
    """
    try:
        wd = os.getcwd()
    except OSError, e:
        raise util.Abort(_("error getting current working directory: %s") %
                         e.strerror)
    path = cmdutil.findrepo(wd) or ""
    if not path:
        lui = ui
    else:
        lui = ui.copy()
        lui.readconfig(os.path.join(path, ".hg", "hgrc"), path)

    if rpath:
        path = lui.expandpath(rpath[-1])
        lui = ui.copy()
        lui.readconfig(os.path.join(path, ".hg", "hgrc"), path)

    return path, lui

def _checkshellalias(ui, args):
    cwd = os.getcwd()
    norepo = commands.norepo
    options = {}

    try:
        args = fancyopts.fancyopts(args, commands.globalopts, options)
    except fancyopts.getopt.GetoptError:
        return

    if not args:
        return

    _parseconfig(ui, options['config'])
    if options['cwd']:
        os.chdir(options['cwd'])

    path, lui = _getlocal(ui, [options['repository']])

    cmdtable = commands.table.copy()
    addaliases(lui, cmdtable)

    cmd = args[0]
    try:
        aliases, entry = cmdutil.findcmd(cmd, cmdtable, lui.config("ui", "strict"))
    except (error.AmbiguousCommand, error.UnknownCommand):
        commands.norepo = norepo
        os.chdir(cwd)
        return

    cmd = aliases[0]
    fn = entry[0]

    if cmd and hasattr(fn, 'shell'):
        d = lambda: fn(ui, *args[1:])
        return lambda: runcommand(lui, None, cmd, args[:1], ui, options, d, [], {})

    commands.norepo = norepo
    os.chdir(cwd)

_loaded = set()
def _dispatch(ui, args):
    shellaliasfn = _checkshellalias(ui, args)
    if shellaliasfn:
        return shellaliasfn()

    # read --config before doing anything else
    # (e.g. to change trust settings for reading .hg/hgrc)
    _parseconfig(ui, _earlygetopt(['--config'], args))

    # check for cwd
    cwd = _earlygetopt(['--cwd'], args)
    if cwd:
        os.chdir(cwd[-1])

    rpath = _earlygetopt(["-R", "--repository", "--repo"], args)
    path, lui = _getlocal(ui, rpath)

    # Configure extensions in phases: uisetup, extsetup, cmdtable, and
    # reposetup. Programs like TortoiseHg will call _dispatch several
    # times so we keep track of configured extensions in _loaded.
    extensions.loadall(lui)
    exts = [ext for ext in extensions.extensions() if ext[0] not in _loaded]
    # Propagate any changes to lui.__class__ by extensions
    ui.__class__ = lui.__class__

    # (uisetup and extsetup are handled in extensions.loadall)

    for name, module in exts:
        cmdtable = getattr(module, 'cmdtable', {})
        overrides = [cmd for cmd in cmdtable if cmd in commands.table]
        if overrides:
            ui.warn(_("extension '%s' overrides commands: %s\n")
                    % (name, " ".join(overrides)))
        commands.table.update(cmdtable)
        _loaded.add(name)

    # (reposetup is handled in hg.repository)

    addaliases(lui, commands.table)

    # check for fallback encoding
    fallback = lui.config('ui', 'fallbackencoding')
    if fallback:
        encoding.fallbackencoding = fallback

    fullargs = args
    cmd, func, args, options, cmdoptions = _parse(lui, args)

    if options["config"]:
        raise util.Abort(_("option --config may not be abbreviated!"))
    if options["cwd"]:
        raise util.Abort(_("option --cwd may not be abbreviated!"))
    if options["repository"]:
        raise util.Abort(_(
            "Option -R has to be separated from other options (e.g. not -qR) "
            "and --repository may only be abbreviated as --repo!"))

    if options["encoding"]:
        encoding.encoding = options["encoding"]
    if options["encodingmode"]:
        encoding.encodingmode = options["encodingmode"]
    if options["time"]:
        def get_times():
            t = os.times()
            if t[4] == 0.0: # Windows leaves this as zero, so use time.clock()
                t = (t[0], t[1], t[2], t[3], time.clock())
            return t
        s = get_times()
        def print_time():
            t = get_times()
            ui.warn(_("Time: real %.3f secs (user %.3f+%.3f sys %.3f+%.3f)\n") %
                (t[4]-s[4], t[0]-s[0], t[2]-s[2], t[1]-s[1], t[3]-s[3]))
        atexit.register(print_time)

    if options['verbose'] or options['debug'] or options['quiet']:
        ui.setconfig('ui', 'verbose', str(bool(options['verbose'])))
        ui.setconfig('ui', 'debug', str(bool(options['debug'])))
        ui.setconfig('ui', 'quiet', str(bool(options['quiet'])))
    if options['traceback']:
        ui.setconfig('ui', 'traceback', 'on')
    if options['noninteractive']:
        ui.setconfig('ui', 'interactive', 'off')

    if cmdoptions.get('insecure', False):
        ui.setconfig('web', 'cacerts', '')

    if options['help']:
        return commands.help_(ui, cmd, options['version'])
    elif options['version']:
        return commands.version_(ui)
    elif not cmd:
        return commands.help_(ui, 'shortlist')

    repo = None
    cmdpats = args[:]
    if cmd not in commands.norepo.split():
        try:
            repo = hg.repository(ui, path=path)
            ui = repo.ui
            if not repo.local():
                raise util.Abort(_("repository '%s' is not local") % path)
            ui.setconfig("bundle", "mainreporoot", repo.root)
        except error.RepoError:
            if cmd not in commands.optionalrepo.split():
                if args and not path: # try to infer -R from command args
                    repos = map(cmdutil.findrepo, args)
                    guess = repos[0]
                    if guess and repos.count(guess) == len(repos):
                        return _dispatch(ui, ['--repository', guess] + fullargs)
                if not path:
                    raise error.RepoError(_("There is no Mercurial repository"
                                      " here (.hg not found)"))
                raise
        args.insert(0, repo)
    elif rpath:
        ui.warn(_("warning: --repository ignored\n"))

    msg = ' '.join(' ' in a and repr(a) or a for a in fullargs)
    ui.log("command", msg + "\n")
    d = lambda: util.checksignature(func)(ui, *args, **cmdoptions)
    return runcommand(lui, repo, cmd, fullargs, ui, options, d,
                      cmdpats, cmdoptions)

def _runcommand(ui, options, cmd, cmdfunc):
    def checkargs():
        try:
            return cmdfunc()
        except error.SignatureError:
            raise error.CommandError(cmd, _("invalid arguments"))

    if options['profile']:
        format = ui.config('profiling', 'format', default='text')

        if not format in ['text', 'kcachegrind']:
            ui.warn(_("unrecognized profiling format '%s'"
                        " - Ignored\n") % format)
            format = 'text'

        output = ui.config('profiling', 'output')

        if output:
            path = ui.expandpath(output)
            ostream = open(path, 'wb')
        else:
            ostream = sys.stderr

        try:
            from mercurial import lsprof
        except ImportError:
            raise util.Abort(_(
                'lsprof not available - install from '
                'http://codespeak.net/svn/user/arigo/hack/misc/lsprof/'))
        p = lsprof.Profiler()
        p.enable(subcalls=True)
        try:
            return checkargs()
        finally:
            p.disable()

            if format == 'kcachegrind':
                import lsprofcalltree
                calltree = lsprofcalltree.KCacheGrind(p)
                calltree.output(ostream)
            else:
                # format == 'text'
                stats = lsprof.Stats(p.getstats())
                stats.sort()
                stats.pprint(top=10, file=ostream, climit=5)

            if output:
                ostream.close()
    else:
        return checkargs()
