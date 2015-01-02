#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

init_html
gather_stats

#
# create stats
#
# FIXME?: we only do stats up until yesterday... we also could do today too but not update the db yet...
DATE=$(date -d "1 day ago" '+%Y-%m-%d')
TABLE[0]=stats_pkg_state
TABLE[1]=stats_builds_per_day
TABLE[2]=stats_builds_age
TABLE[3]=stats_bugs
TABLE[4]=stats_notes
TABLE[5]=stats_issues
TABLE[6]=stats_meta_pkg_state
RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum,suite from ${TABLE[0]} WHERE datum = \"$DATE\" AND suite = \"$SUITE\"")
if [ -z $RESULT ] ; then
	ALL=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(name) from sources")
	GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'reproducible' AND date(build_date)<='$DATE';")
	GOOAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'reproducible' AND date(build_date)='$DATE';")
	BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'unreproducible' AND date(build_date)<='$DATE';")
	BAAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'unreproducible' AND date(build_date)='$DATE';")
	UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'FTBFS' AND date(build_date)<='$DATE';")
	UGLDAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'FTBFS' AND date(build_date)='$DATE';")
	REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE (status != 'FTBFS' AND status != 'unreproducible' AND status != 'reproducible') AND date(build_date)<='$DATE';")
	RESDAY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE (status != 'FTBFS' AND status != 'unreproducible' AND status != 'reproducible') AND date(build_date)='$DATE';")
	OLDESTG=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT build_date FROM source_packages WHERE status = 'reproducible' AND NOT date(build_date)>='$DATE' ORDER BY build_date LIMIT 1;")
	OLDESTB=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT build_date FROM source_packages WHERE status = 'unreproducible' AND NOT date(build_date)>='$DATE' ORDER BY build_date LIMIT 1;")
	OLDESTU=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT build_date FROM source_packages WHERE status = 'FTBFS' AND NOT date(build_date)>='$DATE' ORDER BY build_date LIMIT 1;")
	DIFFG=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTG');")
	if [ -z $DIFFG ] ; then DIFFG=0 ; fi
	DIFFB=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTB');")
	if [ -z $DIFFB ] ; then DIFFB=0 ; fi
	DIFFU=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT julianday('$DATE') - julianday('$OLDESTU');")
	if [ -z $DIFFU ] ; then DIFFU=0 ; fi
	let "TOTAL=GOOD+BAD+UGLY+REST"
	let "UNTESTED=ALL-TOTAL"
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[0]} VALUES (\"$DATE\", \"$SUITE\", $UNTESTED, $GOOD, $BAD, $UGLY, $REST)" 
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[1]} VALUES (\"$DATE\", \"$SUITE\", $GOOAY, $BAAY, $UGLDAY, $RESDAY)"
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[2]} VALUES (\"$DATE\", \"$SUITE\", \"$DIFFG\", \"$DIFFB\", \"$DIFFU\")"
	# FIXME: we don't do 2 / stats_builds_age.png yet :/ (and do 3 later) and 6 is special anyway
	for i in 0 1 4 5 ; do
		# force regeneration of the image
		touch -d "$DATE 00:00" ${TABLE[$i]}.png
	done
	# gather notes stats
	# FIXME: hard-coding another job path is meh
	NOTES=$(grep -c -v "^ " /var/lib/jenkins/jobs/reproducible_html_notes/workspace/packages.yml)
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[4]} VALUES (\"$DATE\", \"$NOTES\")"
	ISSUES=$(grep -c -v "^ " /var/lib/jenkins/jobs/reproducible_html_notes/workspace/issues.yml)
	sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[5]} VALUES (\"$DATE\", \"$ISSUES\")"
fi

# FIXME: work in progress: meta package state graphs
META_PKG[1]="required"
META_PKG[2]="build-essential"
META_PKG[3]="gnome"
META_PKG[4]="build-depends_gnome"
META_LIST[1]="acl attr base-files base-passwd bash coreutils dash debconf debianutils diffutils dpkg e2fsprogs eglibc findutils gcc-4.7 grep gzip hostname liblocale-gettext-perl libselinux libsepol libtext-charwidth-perl libtext-iconv-perl libtext-wrapi18n-perl lsb mawk ncurses pam perl sed sensible-utils shadow sysvinit tar tzdata util-linux xz-utils zlib"
META_LIST[2]="binutils build-essential dpkg eglibc gcc-defaults make-dfsg patch perl"
META_LIST[3]="passepartout agave alacarte alleyoop amide apper aptoncd ardour ardour3 arista atomix autorenamer azureus backintime balsa banshee bareftp basenji bisho blam blueman bluetile brasero brightside cairo-dock-plug-ins camorama cbrpager celestia cheese chromium-browser cinnamon cinnamon-control-center cinnamon-desktop-environment cinnamon-screensaver cinnamon-settings-daemon clamtk coriander darktable dasher ddskk debian-design debian-parl dia distcc docky dragbox dv dvswitch ekiga empathy eog epiphany-browser etherape evince evolution evolution-data-server evolution-rss expeyes fcitx-configtool file flowblade flowcanvas fpc frama-c frontaccounting g2ipmsg gallery-uploader gamazons gambas3 gaphor gbatnav gbonds gco gconf-editor gdebi gdesklets gdm3 geary gecko-mediaplayer gedit geoclue gfax ggcov ghextris gjiten gjots2 gksu glabels glotski gmfsk gmobilemedia gmotionlive gniall gnoemoe gnokii gnome-activity-journal gnome-alsamixer gnome-applets gnome-blog gnome-bluetooth gnome-breakout gnome-btdownload gnome-calculator gnome-chess gnome-clocks gnome-codec-install gnome-color-chooser gnome-colors gnome-commander gnome-contacts gnome-control-center gnome-desktop gnome-desktop-sharp2 gnome-desktop3 gnome-do gnome-do-plugins gnome-documents gnome-dvb-daemon gnome-flashback gnome-font-viewer gnome-getting-started-docs gnome-gmail gnome-hearts gnome-hwp-support gnome-icon-theme-extras gnome-icon-theme-symbolic gnome-keyring-sharp gnome-klotski gnome-mahjongg gnome-main-menu gnome-menus gnome-menus2 gnome-mines gnome-mplayer gnome-music gnome-nibbles gnome-osd gnome-packagekit gnome-panel gnome-phone-manager gnome-photos gnome-pie gnome-power-manager gnome-python gnome-python-desktop gnome-rdp gnome-robots gnome-schedule gnome-screensaver gnome-screensaver-flags gnome-session gnome-settings-daemon gnome-sharp2 gnome-shell gnome-shell-extension-autohidetopbar gnome-shell-extension-redshift gnome-shell-extension-suspend-button gnome-shell-extension-weather gnome-shell-extensions gnome-shell-mailnag gnome-shell-pomodoro gnome-shell-timer gnome-software gnome-specimen gnome-speech gnome-split gnome-system-tools gnome-terminal gnome-tetravex gnome-themes-standard gnome-tweak-tool gnome-user-share gnome-vfs gnome-video-effects gnomecatalog gnomekiss gnomeradio gnotime gnucash gobby goobox gpaste gpiv gpxviewer grcm grdesktop greenwich gresolver grhino gshare gsql gst-plugins-base0.10 gst-plugins-good0.10 gstm gtetrinet gtk-doc gtkhtml3.14 gtkhtml4.0 gui-ufw guile-gnome-platform gupnp-tools gurlchecker gwave gwc gwibber gxine hamster-applet hotssh hylafax ibus icewm indicator-session inkscape invada-studio-plugins-lv2 isenkram istanbul java-gnome jwm k3d kabikaboo kazam lablgtk2 ladish lat libbonoboui libcryptui libgksu libgnome libgnome-keyring libgnome-media-profiles libgnome2-canvas-perl libgnome2-perl libgnome2-vfs-perl libgnomecanvas libgnomecanvasmm2.6 libgnomekbd libgnomeui libgtkada libmateweather libopenraw libreoffice librest libsocialweb libsoup2.4 link-monitor-applet linsmith live-images lookup-el ltsp lybniz mail-notification mailnag mate-power-manager mathwar maximus mdbtools menulibre meta-gnome3 metacity mhc mialmpick minbar monodevelop monotone-viz monster-masher moonshot-ui mozilla-gnome-keyring mpop msmtp mutter mysql-workbench nautilus nautilus-share network-manager-applet network-manager-strongswan notebook ocamlgraph ontv openbox openbox-menu opensesame openvrml oregano padevchooser paman pan paprefs pasystray pavumeter pegsolitaire perlpanel petri-foo pida pidgin-awayonlock pike7.8 pinta pioneers pitivi pk-update-icon planner player plotdrop podbrowser postr pyacidobasic pybliographer pychess pyhoca-gui rapid-photo-downloader remmina revelation rhythmbox routeplanner ruby-gnome2 sagasu sanduhr sawfish sbackup screenlets seahorse seahorse-nautilus sflphone shiki-colors-murrine shutter slashtime smbnetfs smtube smuxi solaar soundconverter sparkleshare specto sshmenu stardict startupmanager sugar-0.96 sugar-0.98 sugar-calculate-activity sugar-toolkit-0.84 swami swt-gtk swt4-gtk syncevolution system-config-cluster system-config-lvm system-config-printer t-code tasksel teg telegnome tenace texmacs tortoisehg totem tracker tumbler txaws udev-discover uicilibris uim verbiste vim vimhelp-de viridian xchat-gnome xine-lib-1.2 xnee xournal yarssr yc-el zapping"
META_LIST[4]="accerciser accountsservice adwaita-icon-theme agave aisleriot alacarte alarm-clock-applet alleyoop alt-ergo amide anjuta anjuta-extras appsrc ardour ardour3 atk1.0 atkmm1.6 atomix atril avahi bacula balsa banshee banshee-community-extensions baobab bareftp basenji bisho brasero brightside bsl byzanz cairo-dock-plug-ins cairomm camorama caribou cbrpager cd cdda celestia cellwriter cheese chromium-browser cinnamon cinnamon-control-center cinnamon-desktop cinnamon-menus cinnamon-screensaver cinnamon-session cinnamon-settings-daemon cjs clutter-1.0 clutter-gst clutter-gst-2.0 clutter-gtk cogl colorname conduit coriander cowbell cruft crystalhd cutter-testing-framework darktable dasher data d-conf deja-dup devhelp d-feet dia distcc dmz-cursor-theme dots dv ekiga emerillon empathy entangle eog eog-plugins epiphany-browser esound etherape evince evolution evolution-data-server evolution-ews evolution-mapi evolution-rss file file-roller five-or-more florence flowcanvas four-in-a-row frama-c g2ipmsg gamazons gambas3 gamin gaphor gbatnav gbonds gbrainy gconf gconf-editor gconfmm2.6 gcr gdesklets gdk-pixbuf gdl gdm3 geary gedit gedit-plugins geeqie gegl genius geoclue geocode-glib gfbgraph ggcov ghex gimp girara gitg gjiten gjs gksu glabels glade glib2.0 glibmm2.4 glib-networking glipper glotski gmfsk gmotionlive gmpc gnac gnet gniall gnoemoe gnome-alsamixer gnome-applets gnome-backgrounds gnome-bluetooth gnome-boxes gnome-breakout gnome-calculator gnome-chemistry-utils gnome-chess gnome-clocks gnome-color-chooser gnome-color-manager gnome-commander gnome-common gnome-contacts gnome-control-center gnome-desktop gnome-desktop3 gnome-desktop-sharp2 gnome-desktop-testing gnome-devel-docs gnome-dictionary gnome-disk-utility gnome-do gnome-documents gnome-doc-utils gnome-dvb-daemon gnome-flashback gnome-font-viewer gnome-games gnome-games-extra-data gnome-getting-started-docs gnome-hearts gnome-hwp-support gnome-icon-theme gnome-icon-theme-extras gnome-icon-theme-symbolic gnome-js-common gnome-keyring gnome-keyring-sharp gnomekiss gnome-klotski gnome-logs gnome-mahjongg gnome-maps gnome-mastermind gnome-media gnome-menus gnome-menus2 gnome-mime-data gnome-mines gnome-mousetrap gnome-mud gnome-music gnome-nettool gnome-nibbles gnome-online-accounts gnome-online-miners gnome-orca gnome-osd gnome-panel gnome-phone-manager gnome-photos gnome-pie gnome-power-manager gnome-python gnome-python-desktop gnome-python-extras gnomeradio gnome-robots gnome-schedule gnome-screensaver gnome-screenshot gnome-search-tool gnome-session gnome-settings-daemon gnome-sharp2 gnome-shell gnome-shell-extension-redshift gnome-shell-extensions gnome-shell-extension-weather gnome-shell-pomodoro gnome-software gnome-sound-recorder gnome-speech gnome-split gnome-subtitles gnome-sushi gnome-system-log gnome-system-monitor gnome-system-tools gnome-terminal gnome-tetravex gnome-themes gnome-themes-extras gnome-themes-standard gnome-tweak-tool gnome-user-docs gnome-user-share gnome-vfs gnome-video-effects gnome-web-photo gnomint gnonlin gnotime gnucash gobby gobby-infinote gobject-introspection goocanvasmm gparted gpaste gpdftext gpiv gpointing-device-settings graphviz grcm grdesktop grhino grilo-plugins gsettings-desktop-schemas gshare gsql gst-buzztard gst-chromaprint gst-fluendo-mp3 gst-libav1.0 gstm gst-plugins-bad0.10 gst-plugins-bad1.0 gst-plugins-base0.10 gst-plugins-base1.0 gst-plugins-good0.10 gst-plugins-good1.0 gst-plugins-ugly0.10 gst-plugins-ugly1.0 gstreamer0.10 gstreamer0.10-ffmpeg gstreamer1.0 gstreamer-hplugins gstreamer-sharp gtetrinet gthumb gtk+2.0 gtk2-engines gtkdataboxmm gtk-doc gtkhtml3.14 gtkhtml4.0 gtkimageview gtkmm2.4 gtkmm3.0 gtkmm-documentation gtk-sharp2 gtksourceview2 gtksourceview3 gtkspell3 gtranslator guake guake-indicator gucharmap guile-gnome-platform gupnp-tools gurlchecker gvfs gwaei gwave gwc hamster-applet hicolor-icon-theme ibus-libpinyin ibus-libzhuyin icedove iceweasel icewm indicator-applet indicator-session inkscape intltool istanbul jhbuild json-glib k3d kino krb5-auth-dialog lablgtk2 ladish langdrill lazarus leafpad libappindicator libart-lgpl libbonobo libbonoboui libcanberra libchamplain libcroco libcryptui libdbusmenu libdmapsharing libepc libg3d libgda5 libgdata libgksu libglade2 libglademm2.4 libgnome libgnome2-canvas-perl libgnome2-perl libgnome2-vfs-perl libgnomecanvas libgnomecanvasmm2.6 libgnomekbd libgnome-keyring libgnome-media-profiles libgnomeui libgrip libgrss libgtkada libgtksourceviewmm libgtop2 libgweather libgwenhywfar libgwibber libgxps libindicate libinfinity libmateweather libnice libnotify liboobs libosinfo libpeas libproxy libpwquality librcc librest librsvg libsecret libsocialweb libsoup2.4 libunique libunique3 libwnck libwnck3 libxklavier libxml++2.6 libzapojit lightdm linsmith loudmouth mail-notification mate-power-manager mathwar maximus mdbtools meld memphis menulibre metacity meta-gnome3 mialmpick minbar mldonkey mm-common modemmanager monotone-viz monster-masher moonshot-ui mousetweaks mozilla-gnome-keyring mp3splt-gtk mpop msmtp muffin mutter mysql-workbench nautilus nautilus-actions nautilus-open-terminal nautilus-python nautilus-sendto nautilus-wipe nemo netspeed network-manager-applet network-manager-iodine network-manager-strongswan nip2 notebook notification-daemon notify-osd ocamlgraph ocrfeeder ontv openvrml oregano osm-gps-map packagekit padevchooser pan pango1.0 pangomm pangox-compat Passepartout patchage pdfmod pegsolitaire perlpanel petri-foo pike7.8 pioneers pitivi pk-update-icon planner player plotdrop polari postr prepaid-manager-applet pygobject pygobject-2 pygtk pygtksourceview pyhoca-gui pyorbit pywebkitgtk qapt qupzilla rarian referencer remmina revelation rhythmbox sagasu sanduhr seahorse seahorse-nautilus seed sensors-applet sflphone shadow shotwell simple-scan slashtime slmon smbnetfs solfege sound-juicer sound-theme-freedesktop stardict startup-notification subversion sugar-artwork-0.96 sugar-artwork-0.98 swami swt4-gtk swt-gtk syncevolution system-config-printer system-tools-backends taglib-sharp tali teg telegnome terminatorx tomboy totem totem-pl-parser tracker tumbler ubuntulooks uim vala-0.26 vdk2 verbiste viking vim vinagre vino vte vte2.91 vte3 wxwidgets3.0 xchat-gnome xdg-user-dirs xdg-user-dirs-gtk xine-lib-1.2 xiphos xnee xournal x-tile yelp yelp-tools yelp-xsl zapping zenity"
for i in $(seq 1 ${#META_PKG[@]}) ; do
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT datum,meta_pkg,suite from ${TABLE[6]} WHERE datum = \"$DATE\" AND suite = \"$SUITE\" AND meta_pkg = \"${META_PKG[$i]}\"")
	if [ -z $RESULT ] ; then
		META_TOTAL=0
		META_WHERE=""
		for PKG in ${META_LIST[$i]} ; do
			if [ -z "$META_WHERE" ] ; then
				META_WHERE="name in ('$PKG'"
			else
				META_WHERE="$META_WHERE, '$PKG'"
			fi
			let "META_TOTAL=META_TOTAL+1"
		done
		META_WHERE="$META_WHERE)"
		META_GOOD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'reproducible' AND date(build_date)<='$DATE' AND $META_WHERE;")
		META_BAD=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'unreproducible' AND date(build_date)<='$DATE' AND $META_WHERE;")
		META_UGLY=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE status = 'FTBFS' AND date(build_date)<='$DATE' AND $META_WHERE;")
		META_REST=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT count(status) from source_packages WHERE (status != 'FTBFS' AND status != 'unreproducible' AND status != 'reproducible') AND date(build_date)<='$DATE' AND $META_WHERE;")
		let "META_UNTESTED=META_TOTAL-META_GOOD-META_BAD-META_UGLY-META-REST"
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[6]} VALUES (\"$DATE\", \"$SUITE\", \"${META_PKG[$i]}\", $META_UNTESTED, $META_GOOD, $META_BAD, $META_UGLY, $META_REST)" 
	fi
	# FIXME: touch -d to force re-creation is missing...
done

# query bts
USERTAGS="toolchain infrastructure timestamps fileordering buildpath username hostname uname randomness"
RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT * from ${TABLE[3]} WHERE datum = \"$DATE\"")
if [ -z $RESULT ] ; then
	declare -a DONE
	declare -a OPEN
	SQL="INSERT INTO ${TABLE[3]} VALUES (\"$DATE\" "
	for TAG in $USERTAGS ; do
		OPEN[$TAG]=$(bts select usertag:$TAG users:reproducible-builds@lists.alioth.debian.org status:open status:forwarded 2>/dev/null|wc -l)
		DONE[$TAG]=$(bts select usertag:$TAG users:reproducible-builds@lists.alioth.debian.org status:done archive:both 2>/dev/null|wc -l)
		# test if both values are integers
		if ! ( [[ ${DONE[$TAG]} =~ ^-?[0-9]+$ ]] && [[ ${OPEN[$TAG]} =~ ^-?[0-9]+$ ]] ) ; then
			echo "Non-integers value detected, exiting."
			echo "Usertag: $TAG"
			echo "Open: ${OPEN[$TAG]}"
			echo "Done: ${DONE[$TAG]}"
			exit 1
		fi
		SQL="$SQL, ${OPEN[$TAG]}, ${DONE[$TAG]}"
	done
	SQL="$SQL)"
	echo $SQL
	sqlite3 -init ${INIT} ${PACKAGES_DB} "$SQL"
	# force regeneration of the image
	touch -d "$DATE 00:00" ${TABLE[3]}.png
fi

# used for redo_png (but only needed to define once)
FIELDS[0]="datum, reproducible, unreproducible, FTBFS, other, untested"
FIELDS[1]="datum, reproducible, unreproducible, FTBFS, other"
FIELDS[2]="datum, oldest_reproducible, oldest_unreproducible, oldest_FTBFS"
FIELDS[3]="datum "
for TAG in $USERTAGS ; do
	FIELDS[3]="${FIELDS[3]}, open_$TAG, done_$TAG"
done
FIELDS[4]="datum, packages_with_notes"
FIELDS[5]="datum, known_issues"
FIELDS[6]="datum, reproducible, unreproducible, FTBFS, other, untested"
COLOR[0]=5
COLOR[1]=4
COLOR[2]=3
COLOR[3]=18
COLOR[4]=1
COLOR[5]=1
COLOR[6]=5
MAINLABEL[0]="Package reproducibility status"
MAINLABEL[1]="Amount of packages build each day"
MAINLABEL[2]="Age in days of oldest kind of logfile"
MAINLABEL[3]="Bugs with usertags for user reproducible-builds@lists.alioth.debian.org"
MAINLABEL[4]="Packages which have notes"
MAINLABEL[5]="Identified issues"
YLABEL[0]="Amount (total)"
YLABEL[1]="Amount (per day)"
YLABEL[2]="Age in days"
YLABEL[3]="Amount of bugs"
YLABEL[4]="Amount of packages"
YLABEL[5]="Amount of issues"

redo_png() {
	echo "${FIELDS[$i]}" > ${TABLE[$i]}.csv
	# TABLE[3+4+5] don't have a suite column...
	# 6 is special anyway
	if [ $i -eq 6 ] ; then
		WHERE_EXTRA="WHERE suite = '$SUITE' and meta_pkg = '$2'"
	elif [ $i -ne 3 ] && [ $i -ne 4 ] && [ $i -ne 5 ] ; then
		WHERE_EXTRA="WHERE suite = '$SUITE'"
	else
		WHERE_EXTRA=""
	fi
	sqlite3 -init ${INIT} -csv ${PACKAGES_DB} "SELECT ${FIELDS[$i]} from ${TABLE[$i]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$i]}.csv
	/srv/jenkins/bin/make_graph.py ${TABLE[$i]}.csv $1 ${COLOR[$i]} "${MAINLABEL[$i]}" "${YLABEL[$i]}"
	rm ${TABLE[$i]}.csv
	mv $1 /var/lib/jenkins/userContent/
}

write_usertag_table() {
	RESULT=$(sqlite3 -init ${INIT} ${PACKAGES_DB} "SELECT * from ${TABLE[3]} WHERE datum = \"$DATE\"")
	if [ -z "$RESULTS" ] ; then
		COUNT=0
		for FIELD in $(echo ${FIELDS[3]} | tr -d ,) ; do
			let "COUNT+=1"
			VALUE=$(echo $RESULT | cut -d "|" -f$COUNT)
			if [ $COUNT -eq 1 ] ; then
				write_page "<table class=\"body\"><tr><th colspan=\"3\">Bugs with usertags for reproducible-builds@lists.alioth.debian.org on $VALUE</th></tr>"
			elif [ $((COUNT%2)) -eq 0 ] ; then
				write_page "<tr><td><a href=\"https://bugs.debian.org/cgi-bin/pkgreport.cgi?tag=${FIELD:5};users=reproducible-builds@lists.alioth.debian.org&archive=both\">${FIELD:5}</a></td><td>Open: $VALUE</td>"
			else
				write_page "<td>Done: $VALUE</td></tr>"
			fi
		done
		write_page "</table>"
	fi
}

VIEW=stats
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
write_page "<p>"
set_icon reproducible
write_icon
write_page "$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly."
set_icon unreproducible with
write_icon
set_icon unreproducible
write_icon
write_page "$COUNT_BAD packages ($PERCENT_BAD%) failed to built reproducibly."
set_icon FTBFS
write_icon
write_page "$COUNT_UGLY packages ($PERCENT_UGLY%) failed to build from source.</p>"
write_page "<p>"
if [ $COUNT_SOURCELESS -gt 0 ] ; then
	write_page "For "
	set_icon 404
	write_icon
	write_page "$COUNT_SOURCELESS ($PERCENT_SOURCELESS%) packages sources could not be downloaded,"
fi
set_icon not_for_us
write_icon
write_page "$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any', 'all', 'amd64', 'linux-any', 'linux-amd64' nor 'any-amd64' will not be build here"
write_page "and those "
set_icon blacklisted
write_icon
write_page "$COUNT_BLACKLISTED blacklisted packages neither.</p>"
write_page "<p>"
# FIXME: we don't do 2 / stats_builds_age.png yet :/ (also see above)
for i in 0 3 4 5 6 1 ; do
	if [ "$i" = "3" ] ; then
		write_usertag_table
	fi
	# FIXME: split this out in html_meta_graphs... really.
	if [ "$i" = "6" ] ; then
		# FIXME: THIS IS A MESS
		for j in $(seq 1 ${#META_PKG[@]}) ; do
			MAINLABEL[6]="Package reproducibility status for ${META_PKG[$j]} packages"
			YLABEL[6]="Amount (${META_PKG[$j]} packages)"
			PNG=${TABLE[$i]}_${META_PKG[$j]}.png
			write_page " <div>"
			write_page " <a href=\"/userContent/$PNG\"><img src=\"/userContent/$PNG\" class=\"graph\" alt=\"${MAINLABEL[$i]}\"></a>"
			write_page " <br />The package set '${META_PKG[$j]}' consists of: "
			# FIXME: split into good/bad/ugly too
			force_package_targets ${META_LIST[$j]}
			link_packages ${META_LIST[$j]}
			write_page " </div>"
			# redo pngs once a day
			if [ ! -f /var/lib/jenkins/userContent/$PNG ] || [ -z $(find /var/lib/jenkins/userContent -maxdepth 1 -mtime +0 -name $PNG) ] ; then
				# FIXME: call redo_png differently here.. sux
				redo_png $PNG ${META_PKG[$j]}
			fi
		done
	else
		write_page " <a href=\"/userContent/${TABLE[$i]}.png\"><img src=\"/userContent/${TABLE[$i]}.png\" class=\"graph\" alt=\"${MAINLABEL[$i]}\"></a>"
		# redo pngs once a day
		if [ ! -f /var/lib/jenkins/userContent/${TABLE[$i]}.png ] || [ -z $(find /var/lib/jenkins/userContent -maxdepth 1 -mtime +0 -name ${TABLE[$i]}.png) ] ; then
			redo_png ${TABLE[$i]}.png
		fi
	fi
done
write_page "</p>"
write_page_footer
publish_page

