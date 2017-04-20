#!/bin/sh

echo "HTTP/1.0 200 OK"
echo "Connection: close"
echo "Content-type: text/plain"
echo ""
tail -F /var/log/xymon/*.log

