import os
from mercurial import hg, ui

u = ui.ui()

repo = hg.repository(u, 'test1', create=1)
os.chdir('test1')

# create 'foo' with fixed time stamp
f = open('foo', 'w')
f.write('foo\n')
f.close()
os.utime('foo', (1000, 1000))

# add+commit 'foo'
repo[None].add(['foo'])
repo.commit(text='commit1', date="0 0")

print "workingfilectx.date =", repo[None]['foo'].date()
