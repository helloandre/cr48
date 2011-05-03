# /etc/skel/.bashrc
#
# This file is sourced by all *interactive* bash shells on startup,
# including some apparently interactive shells such as scp and rcp
# that can't tolerate any output.  So make sure this doesn't display
# anything or bad things will happen !


# Test for an interactive shell.  There is no need to set anything
# past this point for scp and rcp, and it's important to refrain from
# outputting anything in those cases.
if [[ $- != *i* ]] ; then
	# Shell is non-interactive.  Be done now!
	return
fi

# Let's go to the home dir
cd ~

# Put your fun stuff here.
alias ls='ls --color --group-directories-first'
alias ll='ls -lh'

#need to make sure things are where they should be
export PATH=$PATH:~/bin
export VIMRUNTIME=/home/chronos/user/.vim/vim
export PYTHONPATH=/home/chronos/user/lib/python2.6
export PYTHONHOME=/home/chronos/user
export TERM=screen

#make sure we can write to this bitch
if mount | grep '/home/chronos/user.*noexec' > /dev/null
then
    sudo mount -i -o remount,exec /home/chronos/user
fi

#start dropbox if it's not running
#for info on how to get dropbox running on ChromeOS go here: 
#http://gabeortiz.net/2011/how-to-get-dropbox-working-on-a-cr48-google-chrome-netbook/
if [ -z "$(pgrep dropbox)" ] && [ -d ~/.dropbox-dist ]
  then
   echo "Starting Dropbox.."
   ~/.dropbox-dist/dropboxd &
fi
