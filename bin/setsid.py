#!/usr/bin/python
"""backport of util-linux' setsid -w to Debian wheezy"""
# replace with setsid from the util-linux package from jessie (stable) or wheezy-bpo

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
