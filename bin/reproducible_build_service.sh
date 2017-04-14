#!/bin/sh

# Copyright © 2017 Holger Levsen (holger@layer-acht.org)

#
echo $0
echo $1
export

echo sleeping 5min now
sleep 5m

#script translates "arm64 builder12" to "arm64 builder12 sled3 sled 4"
# <      h01ger> | but then its really simple: have a script, jenkins_build_cron_runner.sh or such, and start this with 4 params, eg, arm64, builder_12, codethink_sled11, codethink_sled14. the cron_runner script simple needs to set some variables like jenkins would do, redirect output 
#   to a directory which is accessable to the webserver and run reproducible_build.sh. voila.
# <      h01ger> | we could still make the logs accessable to browsers
# <      h01ger> | and we need maintenance to cleanup the log files eventually
# <      h01ger> | and translate that yaml to crontab entries

