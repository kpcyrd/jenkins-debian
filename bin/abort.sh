#!/bin/bash

TMPFILE=$(mktemp)
curl https://jenkins.debian.net/jnlpJars/jenkins-cli.jar -o $TMPFILE
java -jar $TMPFILE -s http://localhost:8080/ set-build-result aborted
rm $TMPFILE
exit

