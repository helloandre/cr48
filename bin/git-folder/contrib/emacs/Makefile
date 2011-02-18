## Build and install stuff

EMACS = emacs

ELC = git.elc git-blame.elc
INSTALL ?= install
INSTALL_ELC = $(INSTALL) -m 644
prefix ?= $(HOME)
emacsdir = $(prefix)/share/emacs/site-lisp
RM ?= rm -f

all: $(ELC)

install: all
	$(INSTALL) -d $(DESTDIR)$(emacsdir)
	$(INSTALL_ELC) $(ELC:.elc=.el) $(ELC) $(DESTDIR)$(emacsdir)

%.elc: %.el
	$(EMACS) -batch -f batch-byte-compile $<

clean:; $(RM) $(ELC)
