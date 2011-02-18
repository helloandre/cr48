# simple script to be used in hooks
# copy it to the current directory when the test starts:
#
#     cp "$TESTDIR"/printenv.py .
#
# put something like this in the repo .hg/hgrc:
#
#     [hooks]
#     changegroup = python ../printenv.py <hookname> [exit] [output]
#
#   - <hookname> is a mandatory argument (e.g. "changegroup")
#   - [exit] is the exit code of the hook (default: 0)
#   - [output] is the name of the output file (default: use sys.stdout)
#              the file will be opened in append mode.
#
import os
import sys

try:
    import msvcrt
    msvcrt.setmode(sys.stdin.fileno(), os.O_BINARY)
    msvcrt.setmode(sys.stdout.fileno(), os.O_BINARY)
    msvcrt.setmode(sys.stderr.fileno(), os.O_BINARY)
except ImportError:
    pass

exitcode = 0
out = sys.stdout

name = sys.argv[1]
if len(sys.argv) > 2:
    exitcode = int(sys.argv[2])
    if len(sys.argv) > 3:
        out = open(sys.argv[3], "ab")

# variables with empty values may not exist on all platforms, filter
# them now for portability sake.
env = [k for k, v in os.environ.iteritems()
       if k.startswith("HG_") and v]
env.sort()

# edit the variable part of the variable
url = os.environ.get("HG_URL", "")
if url.startswith("file:"):
    os.environ["HG_URL"] = "file:"
elif url.startswith("remote:http"):
    os.environ["HG_URL"] = "remote:http"

out.write("%s hook: " % name)
for v in env:
    out.write("%s=%s " % (v, os.environ[v]))
out.write("\n")
out.close()

sys.exit(exitcode)
