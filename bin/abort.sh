#!/bin/bash

# generally interesting: BUILD_* JENKINS_* JOB_* but most is in BUILD_URL, so:
export | egrep "(BUILD_URL=)"
TMPFILE=$(mktemp)

curl https://jenkins.debian.net/jnlpJars/jenkins-cli.jar -o $TMPFILE
java -jar $TMPFILE -s http://localhost:8080/ set-build-result aborted
rm $TMPFILE
exit

