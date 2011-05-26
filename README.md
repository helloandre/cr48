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
 * vim 7.3.206 (with no gui and some nice .vimrc tweaks)
 * python 2.6.6 (currently throwing a libz.so and libcrypto.so errors, but nothing serious)
 * perl 5.12.2
 * mercurial 1.7.5
 * git 1.7.5.2
 * Subversion 1.6.16
 * GNU diffutils 3.0
 * rsync 3.0.8
 * Info-ZIP unzip 6.0 and zip 3.0
 * GNU less 443
 * an install script
 * dropbox support

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

Libcurl does not work with git (i haven't tried with hg). So you cannot use http or https with those.

### Things To Look Out For
ssh (and scp) are really wonky. known_hosts is in /home/chronos/user/.ssh/known_hosts, but any ssh keys need to be in /home/chronos/.ssh.
