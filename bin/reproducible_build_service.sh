#!/bin/bash

# Copyright © 2017 Holger Levsen (holger@layer-acht.org)
# released under the GPLv=2

set -e
set -x


choose_node() {
	case $1 in
		i386_1)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
		i386_2)		NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
		i386_3)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
		i386_4)		NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
		i386_5)		NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
		i386_6)		NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
		i386_7)		NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
		i386_8)		NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;
		i386_9)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
		i386_10)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
		i386_11)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
		i386_12)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
		i386_13)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
		i386_14)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
		i386_15)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
		i386_16)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;
		i386_17)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
		i386_18)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
		i386_19)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
		i386_20)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
		i386_21)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
		i386_22)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
		i386_23)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
		i386_24)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;
                arm64_1)        NODE1=codethink-sled9-arm64     NODE2=codethink-sled10-arm64 ;;
                arm64_2)        NODE1=codethink-sled9-arm64     NODE2=codethink-sled12-arm64 ;;
                arm64_3)        NODE1=codethink-sled9-arm64     NODE2=codethink-sled14-arm64 ;;
                arm64_4)        NODE1=codethink-sled10-arm64    NODE2=codethink-sled9-arm64 ;;
                arm64_5)        NODE1=codethink-sled12-arm64    NODE2=codethink-sled9-arm64 ;;
                arm64_6)        NODE1=codethink-sled14-arm64    NODE2=codethink-sled9-arm64 ;;
                arm64_7)        NODE1=codethink-sled10-arm64    NODE2=codethink-sled11-arm64 ;;
                arm64_8)        NODE1=codethink-sled10-arm64    NODE2=codethink-sled13-arm64 ;;
                arm64_9)        NODE1=codethink-sled13-arm64    NODE2=codethink-sled10-arm64 ;;
                arm64_10)       NODE1=codethink-sled15-arm64    NODE2=codethink-sled10-arm64 ;;
                arm64_11)       NODE1=codethink-sled12-arm64    NODE2=codethink-sled11-arm64 ;;
                arm64_12)       NODE1=codethink-sled11-arm64    NODE2=codethink-sled14-arm64 ;;
                arm64_13)       NODE1=codethink-sled11-arm64    NODE2=codethink-sled16-arm64 ;;
                arm64_14)       NODE1=codethink-sled11-arm64    NODE2=codethink-sled12-arm64 ;;
                arm64_15)       NODE1=codethink-sled12-arm64    NODE2=codethink-sled15-arm64 ;;
                arm64_16)       NODE1=codethink-sled15-arm64    NODE2=codethink-sled16-arm64 ;;
                arm64_17)       NODE1=codethink-sled13-arm64    NODE2=codethink-sled12-arm64 ;;
                arm64_18)       NODE1=codethink-sled13-arm64    NODE2=codethink-sled14-arm64 ;;
                arm64_19)       NODE1=codethink-sled14-arm64    NODE2=codethink-sled13-arm64 ;;
                arm64_20)       NODE1=codethink-sled16-arm64    NODE2=codethink-sled13-arm64 ;;
                arm64_21)       NODE1=codethink-sled14-arm64    NODE2=codethink-sled15-arm64 ;;
                arm64_22)       NODE1=codethink-sled16-arm64    NODE2=codethink-sled15-arm64 ;;
                arm64_23)       NODE1=codethink-sled16-arm64    NODE2=codethink-sled11-arm64 ;;
                arm64_24)       NODE1=codethink-sled15-arm64    NODE2=codethink-sled16-arm64 ;;
                arm64_25)       NODE1=codethink-sled9-arm64     NODE2=codethink-sled16-arm64 ;;
                arm64_26)       NODE1=codethink-sled16-arm64    NODE2=codethink-sled9-arm64 ;;
                arm64_27)       NODE1=codethink-sled10-arm64    NODE2=codethink-sled15-arm64 ;;
                arm64_28)       NODE1=codethink-sled11-arm64    NODE2=codethink-sled10-arm64 ;;
                arm64_29)       NODE1=codethink-sled12-arm64    NODE2=codethink-sled13-arm64 ;;
                arm64_30)       NODE1=codethink-sled15-arm64    NODE2=codethink-sled12-arm64 ;;
                arm64_31)       NODE1=codethink-sled14-arm64    NODE2=codethink-sled11-arm64 ;;
                arm64_32)       NODE1=codethink-sled13-arm64    NODE2=codethink-sled14-arm64 ;;
		*)		echo "Sleeping 60min"
				sleep 60m
				exit 0
				;;
	esac
}

NODE1=""
NODE2=""
for ARCH in i386 arm64 ; do
	case $ARCH in
		i386)	MAX=24 ;;
		arm64)	MAX=32 ;;
		*)	;;
	esac
	for i in $(seq 1 $MAX) ; do
	        # sleep up to 2.3 seconds (additionally to the random sleep reproducible_build.sh does anyway)
	        /bin/sleep $(echo "scale=1 ; $(shuf -i 1-23 -n 1)/10" | bc )

		WORKER_NAME=${ARCH}_$i
		choose_node $WORKER_NAME
		BUILD_BASE=/var/lib/jenkins/userContent/reproducible/debian/build_service/$WORKER_NAME
		mkdir -p $BUILD_BASE
		echo "$(date --utc) - Starting $WORKER_NAME"
		/srv/jenkins/bin/reproducible_build_service_worker.sh $WORKER_NAME $NODE1 $NODE2 >$BUILD_BASE/worker.log 2>&1 &
	done
done

# keep running forever…
while true ; do sleep 23m ; done

# TODO left:
# * translate yaml into a script or such to create those service files (done for i386 for now)
# * logs should auto display in browser like with jenkins… (long-polling, meta-refresh, something)
#   - there's an NPH solution pointed out by Xtaran
# * maintenance job might want to:
#   - check for running builds using systemctl show

