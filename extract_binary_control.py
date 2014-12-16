#!/usr/bin/env python3

import arpy
import sys

ar=arpy.Archive(fileobj=sys.stdin.buffer)

for f in ar:
    if f.header.name == b"control.tar.gz":
        sys.stdout.buffer.write(f.read())
        break
