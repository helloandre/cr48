import os, sys, textwrap
# import from the live mercurial repo
sys.path.insert(0, "..")
# fall back to pure modules if required C extensions are not available
sys.path.append(os.path.join('..', 'mercurial', 'pure'))
from mercurial import demandimport; demandimport.enable()
from mercurial import encoding
from mercurial.commands import table, globalopts
from mercurial.i18n import _
from mercurial.help import helptable
from mercurial import extensions

def get_desc(docstr):
    if not docstr:
        return "", ""
    # sanitize
    docstr = docstr.strip("\n")
    docstr = docstr.rstrip()
    shortdesc = docstr.splitlines()[0].strip()

    i = docstr.find("\n")
    if i != -1:
        desc = docstr[i + 2:]
    else:
        desc = shortdesc

    desc = textwrap.dedent(desc)

    return (shortdesc, desc)

def get_opts(opts):
    for opt in opts:
        if len(opt) == 5:
            shortopt, longopt, default, desc, optlabel = opt
        else:
            shortopt, longopt, default, desc = opt
        allopts = []
        if shortopt:
            allopts.append("-%s" % shortopt)
        if longopt:
            allopts.append("--%s" % longopt)
        desc += default and _(" (default: %s)") % default or ""
        yield(", ".join(allopts), desc)

def get_cmd(cmd, cmdtable):
    d = {}
    attr = cmdtable[cmd]
    cmds = cmd.lstrip("^").split("|")

    d['cmd'] = cmds[0]
    d['aliases'] = cmd.split("|")[1:]
    d['desc'] = get_desc(attr[0].__doc__)
    d['opts'] = list(get_opts(attr[1]))

    s = 'hg ' + cmds[0]
    if len(attr) > 2:
        if not attr[2].startswith('hg'):
            s += ' ' + attr[2]
        else:
            s = attr[2]
    d['synopsis'] = s.strip()

    return d

def section(ui, s):
    ui.write("%s\n%s\n\n" % (s, "-" * encoding.colwidth(s)))

def subsection(ui, s):
    ui.write("%s\n%s\n\n" % (s, '"' * encoding.colwidth(s)))

def subsubsection(ui, s):
    ui.write("%s\n%s\n\n" % (s, "." * encoding.colwidth(s)))

def subsubsubsection(ui, s):
    ui.write("%s\n%s\n\n" % (s, "#" * encoding.colwidth(s)))


def show_doc(ui):
    # print options
    section(ui, _("Options"))
    for optstr, desc in get_opts(globalopts):
        ui.write("%s\n    %s\n\n" % (optstr, desc))

    # print cmds
    section(ui, _("Commands"))
    commandprinter(ui, table, subsection)

    # print topics
    for names, sec, doc in helptable:
        for name in names:
            ui.write(".. _%s:\n" % name)
        ui.write("\n")
        section(ui, sec)
        if hasattr(doc, '__call__'):
            doc = doc()
        ui.write(doc)
        ui.write("\n")

    section(ui, _("Extensions"))
    ui.write(_("This section contains help for extensions that are distributed "
               "together with Mercurial. Help for other extensions is available "
               "in the help system."))
    ui.write("\n\n"
             ".. contents::\n"
             "   :class: htmlonly\n"
             "   :local:\n"
             "   :depth: 1\n\n")

    for extensionname in sorted(allextensionnames()):
        mod = extensions.load(None, extensionname, None)
        subsection(ui, extensionname)
        ui.write("%s\n\n" % mod.__doc__)
        cmdtable = getattr(mod, 'cmdtable', None)
        if cmdtable:
            subsubsection(ui, _('Commands'))
            commandprinter(ui, cmdtable, subsubsubsection)

def commandprinter(ui, cmdtable, sectionfunc):
    h = {}
    for c, attr in cmdtable.items():
        f = c.split("|")[0]
        f = f.lstrip("^")
        h[f] = c
    cmds = h.keys()
    cmds.sort()

    for f in cmds:
        if f.startswith("debug"):
            continue
        d = get_cmd(h[f], cmdtable)
        sectionfunc(ui, d['cmd'])
        # synopsis
        ui.write("::\n\n")
        synopsislines = d['synopsis'].splitlines()
        for line in synopsislines:
            # some commands (such as rebase) have a multi-line
            # synopsis
            ui.write("   %s\n" % line)
        ui.write('\n')
        # description
        ui.write("%s\n\n" % d['desc'][1])
        # options
        opt_output = list(d['opts'])
        if opt_output:
            opts_len = max([len(line[0]) for line in opt_output])
            ui.write(_("options:\n\n"))
            for optstr, desc in opt_output:
                if desc:
                    s = "%-*s  %s" % (opts_len, optstr, desc)
                else:
                    s = optstr
                ui.write("%s\n" % s)
            ui.write("\n")
        # aliases
        if d['aliases']:
            ui.write(_("    aliases: %s\n\n") % " ".join(d['aliases']))


def allextensionnames():
    extensionnames = []

    extensionsdictionary = extensions.enabled()[0]
    extensionnames.extend(extensionsdictionary.keys())

    extensionsdictionary = extensions.disabled()[0]
    extensionnames.extend(extensionsdictionary.keys())

    return extensionnames


if __name__ == "__main__":
    show_doc(sys.stdout)
