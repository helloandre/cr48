# CR-48 Hacks
The purpose of this is to make the CR-48 more useful and conducive to coding. The CR-48 is a fantastic little netbook, but it lacks a bit for power users.

### What this is
 * A way to use programs in Developer Mode without touching the rootfs
 * A way to be productive by writing code and checking it in on the CR-48
 

### What this is not
 * A way to disrupt the normal operation of the CR-48

### How it works
I took a standard install of Ubuntu 10.10 32 bit and staticly compiled a bunch of programs with it. Some programs need special paths set (see .bashrc). It's really that simple.

### What is included
 * vim 7.3 (with no gui and some nice .vimrc tweaks)
 * python 2.6.6 (currently throwing a libz.so and libcrypto.so errors, but nothing serious)
 * mercurial 1.7.5
 * git 1.7.4.1
 * an install script

If you want anything else on here, let me know. Or add it yourself and pull request.

### How to install
 * put your CR-48 in [developer mode](http://ablu.us/av)
 * drop into a shell (Ctrl+Alt+t, then `shell`)
 * make your main partition executable with `sudo mount -i -o remount,exec /home/chronos/user` (don't worry, this will not damage anything
 * download this repo to a different computer, then use `scp` to put it to /home/chronos/user/cr48
 * `cd /home/chronos/user/cr48 && chmod +x install && ./install`

The install script will move everything into the correct place. It may or may not make everything executable, so you may have to `chmod +x /home/chronos/user/bin/*` NOTE: I have not tested the install script, so it may or may not run correctly. If anything is wrong, send me and email at hi@ablu.us.

### Known Bugs
For some reason libz.so and libcrypto.so do not work with python. This is not an issue as I have not run into any problems (including cloning/pushing with hg/git). If you find a fix for this, please fork this and pull request.

Vim acts strange sometimes. The main thing i've noticed is that you can only backspace things that you have enterd int he current INSERT session. If you exit vim, or exit then reenter INSERT mode, you cannot backspace anything, you must :d the entire line and start again. Is this something with the .vimrc? I have this same one on two other boxes with no problems. If you find a fix, let me know.


