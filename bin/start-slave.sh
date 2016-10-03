#!/bin/bash

# slave.jar has to be downloaded from http://localhost/jnlpJars/slave.jar

echo "This jenkins slave.jar will run as PID $$."
exec java -jar /var/lib/jenkins/slave.jar
