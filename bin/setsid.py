#!/usr/bin/python
"""backport of util-linux' setsid -w to Debian stable"""

import os
import sys

if __name__ == "__main__":
    assert len(sys.argv) > 1
    pid = os.fork()
    if pid == 0:
        os.setsid()
        os.execvp(sys.argv[1], sys.argv[1:])
    else:
        cpid, status = os.wait()
        assert cpid == pid
        sys.exit(os.WEXITSTATUS(status))
