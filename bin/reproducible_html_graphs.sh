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
META_PKG[5]="tails"
META_LIST[1]="acl attr base-files base-passwd bash coreutils dash debconf debianutils diffutils dpkg e2fsprogs eglibc findutils gcc-4.7 grep gzip hostname liblocale-gettext-perl libselinux libsepol libtext-charwidth-perl libtext-iconv-perl libtext-wrapi18n-perl lsb mawk ncurses pam perl sed sensible-utils shadow sysvinit tar tzdata util-linux xz-utils zlib"
META_LIST[2]="binutils build-essential dpkg eglibc gcc-defaults make-dfsg patch perl"
META_LIST[3]="passepartout agave alacarte alleyoop amide apper aptoncd ardour ardour3 arista atomix autorenamer azureus backintime balsa banshee bareftp basenji bisho blam blueman bluetile brasero brightside cairo-dock-plug-ins camorama cbrpager celestia cheese chromium-browser cinnamon cinnamon-control-center cinnamon-desktop-environment cinnamon-screensaver cinnamon-settings-daemon clamtk coriander darktable dasher ddskk debian-design debian-parl dia distcc docky dragbox dv dvswitch ekiga empathy eog epiphany-browser etherape evince evolution evolution-data-server evolution-rss expeyes fcitx-configtool file flowblade flowcanvas fpc frama-c frontaccounting g2ipmsg gallery-uploader gamazons gambas3 gaphor gbatnav gbonds gco gconf-editor gdebi gdesklets gdm3 geary gecko-mediaplayer gedit geoclue gfax ggcov ghextris gjiten gjots2 gksu glabels glotski gmfsk gmobilemedia gmotionlive gniall gnoemoe gnokii gnome-activity-journal gnome-alsamixer gnome-applets gnome-blog gnome-bluetooth gnome-breakout gnome-btdownload gnome-calculator gnome-chess gnome-clocks gnome-codec-install gnome-color-chooser gnome-colors gnome-commander gnome-contacts gnome-control-center gnome-desktop gnome-desktop-sharp2 gnome-desktop3 gnome-do gnome-do-plugins gnome-documents gnome-dvb-daemon gnome-flashback gnome-font-viewer gnome-getting-started-docs gnome-gmail gnome-hearts gnome-hwp-support gnome-icon-theme-extras gnome-icon-theme-symbolic gnome-keyring-sharp gnome-klotski gnome-mahjongg gnome-main-menu gnome-menus gnome-menus2 gnome-mines gnome-mplayer gnome-music gnome-nibbles gnome-osd gnome-packagekit gnome-panel gnome-phone-manager gnome-photos gnome-pie gnome-power-manager gnome-python gnome-python-desktop gnome-rdp gnome-robots gnome-schedule gnome-screensaver gnome-screensaver-flags gnome-session gnome-settings-daemon gnome-sharp2 gnome-shell gnome-shell-extension-autohidetopbar gnome-shell-extension-redshift gnome-shell-extension-suspend-button gnome-shell-extension-weather gnome-shell-extensions gnome-shell-mailnag gnome-shell-pomodoro gnome-shell-timer gnome-software gnome-specimen gnome-speech gnome-split gnome-system-tools gnome-terminal gnome-tetravex gnome-themes-standard gnome-tweak-tool gnome-user-share gnome-vfs gnome-video-effects gnomecatalog gnomekiss gnomeradio gnotime gnucash gobby goobox gpaste gpiv gpxviewer grcm grdesktop greenwich gresolver grhino gshare gsql gst-plugins-base0.10 gst-plugins-good0.10 gstm gtetrinet gtk-doc gtkhtml3.14 gtkhtml4.0 gui-ufw guile-gnome-platform gupnp-tools gurlchecker gwave gwc gwibber gxine hamster-applet hotssh hylafax ibus icewm indicator-session inkscape invada-studio-plugins-lv2 isenkram istanbul java-gnome jwm k3d kabikaboo kazam lablgtk2 ladish lat libbonoboui libcryptui libgksu libgnome libgnome-keyring libgnome-media-profiles libgnome2-canvas-perl libgnome2-perl libgnome2-vfs-perl libgnomecanvas libgnomecanvasmm2.6 libgnomekbd libgnomeui libgtkada libmateweather libopenraw libreoffice librest libsocialweb libsoup2.4 link-monitor-applet linsmith live-images lookup-el ltsp lybniz mail-notification mailnag mate-power-manager mathwar maximus mdbtools menulibre meta-gnome3 metacity mhc mialmpick minbar monodevelop monotone-viz monster-masher moonshot-ui mozilla-gnome-keyring mpop msmtp mutter mysql-workbench nautilus nautilus-share network-manager-applet network-manager-strongswan notebook ocamlgraph ontv openbox openbox-menu opensesame openvrml oregano padevchooser paman pan paprefs pasystray pavumeter pegsolitaire perlpanel petri-foo pida pidgin-awayonlock pike7.8 pinta pioneers pitivi pk-update-icon planner player plotdrop podbrowser postr pyacidobasic pybliographer pychess pyhoca-gui rapid-photo-downloader remmina revelation rhythmbox routeplanner ruby-gnome2 sagasu sanduhr sawfish sbackup screenlets seahorse seahorse-nautilus sflphone shiki-colors-murrine shutter slashtime smbnetfs smtube smuxi solaar soundconverter sparkleshare specto sshmenu stardict startupmanager sugar-0.96 sugar-0.98 sugar-calculate-activity sugar-toolkit-0.84 swami swt-gtk swt4-gtk syncevolution system-config-cluster system-config-lvm system-config-printer t-code tasksel teg telegnome tenace texmacs tortoisehg totem tracker tumbler txaws udev-discover uicilibris uim verbiste vim vimhelp-de viridian xchat-gnome xine-lib-1.2 xnee xournal yarssr yc-el zapping"
META_LIST[4]="accerciser accountsservice adwaita-icon-theme agave aisleriot alacarte alarm-clock-applet alleyoop alt-ergo amide anjuta anjuta-extras appsrc ardour ardour3 atk1.0 atkmm1.6 atomix atril avahi bacula balsa banshee banshee-community-extensions baobab bareftp basenji bisho brasero brightside bsl byzanz cairo-dock-plug-ins cairomm camorama caribou cbrpager cd cdda celestia cellwriter cheese chromium-browser cinnamon cinnamon-control-center cinnamon-desktop cinnamon-menus cinnamon-screensaver cinnamon-session cinnamon-settings-daemon cjs clutter-1.0 clutter-gst clutter-gst-2.0 clutter-gtk cogl colorname conduit coriander cowbell cruft crystalhd cutter-testing-framework darktable dasher data d-conf deja-dup devhelp d-feet dia distcc dmz-cursor-theme dots dv ekiga emerillon empathy entangle eog eog-plugins epiphany-browser esound etherape evince evolution evolution-data-server evolution-ews evolution-mapi evolution-rss file file-roller five-or-more florence flowcanvas four-in-a-row frama-c g2ipmsg gamazons gambas3 gamin gaphor gbatnav gbonds gbrainy gconf gconf-editor gconfmm2.6 gcr gdesklets gdk-pixbuf gdl gdm3 geary gedit gedit-plugins geeqie gegl genius geoclue geocode-glib gfbgraph ggcov ghex gimp girara gitg gjiten gjs gksu glabels glade glib2.0 glibmm2.4 glib-networking glipper glotski gmfsk gmotionlive gmpc gnac gnet gniall gnoemoe gnome-alsamixer gnome-applets gnome-backgrounds gnome-bluetooth gnome-boxes gnome-breakout gnome-calculator gnome-chemistry-utils gnome-chess gnome-clocks gnome-color-chooser gnome-color-manager gnome-commander gnome-common gnome-contacts gnome-control-center gnome-desktop gnome-desktop3 gnome-desktop-sharp2 gnome-desktop-testing gnome-devel-docs gnome-dictionary gnome-disk-utility gnome-do gnome-documents gnome-doc-utils gnome-dvb-daemon gnome-flashback gnome-font-viewer gnome-games gnome-games-extra-data gnome-getting-started-docs gnome-hearts gnome-hwp-support gnome-icon-theme gnome-icon-theme-extras gnome-icon-theme-symbolic gnome-js-common gnome-keyring gnome-keyring-sharp gnomekiss gnome-klotski gnome-logs gnome-mahjongg gnome-maps gnome-mastermind gnome-media gnome-menus gnome-menus2 gnome-mime-data gnome-mines gnome-mousetrap gnome-mud gnome-music gnome-nettool gnome-nibbles gnome-online-accounts gnome-online-miners gnome-orca gnome-osd gnome-panel gnome-phone-manager gnome-photos gnome-pie gnome-power-manager gnome-python gnome-python-desktop gnome-python-extras gnomeradio gnome-robots gnome-schedule gnome-screensaver gnome-screenshot gnome-search-tool gnome-session gnome-settings-daemon gnome-sharp2 gnome-shell gnome-shell-extension-redshift gnome-shell-extensions gnome-shell-extension-weather gnome-shell-pomodoro gnome-software gnome-sound-recorder gnome-speech gnome-split gnome-subtitles gnome-sushi gnome-system-log gnome-system-monitor gnome-system-tools gnome-terminal gnome-tetravex gnome-themes gnome-themes-extras gnome-themes-standard gnome-tweak-tool gnome-user-docs gnome-user-share gnome-vfs gnome-video-effects gnome-web-photo gnomint gnonlin gnotime gnucash gobby gobby-infinote gobject-introspection goocanvasmm gparted gpaste gpdftext gpiv gpointing-device-settings graphviz grcm grdesktop grhino grilo-plugins gsettings-desktop-schemas gshare gsql gst-buzztard gst-chromaprint gst-fluendo-mp3 gst-libav1.0 gstm gst-plugins-bad0.10 gst-plugins-bad1.0 gst-plugins-base0.10 gst-plugins-base1.0 gst-plugins-good0.10 gst-plugins-good1.0 gst-plugins-ugly0.10 gst-plugins-ugly1.0 gstreamer0.10 gstreamer0.10-ffmpeg gstreamer1.0 gstreamer-hplugins gstreamer-sharp gtetrinet gthumb gtk+2.0 gtk2-engines gtkdataboxmm gtk-doc gtkhtml3.14 gtkhtml4.0 gtkimageview gtkmm2.4 gtkmm3.0 gtkmm-documentation gtk-sharp2 gtksourceview2 gtksourceview3 gtkspell3 gtranslator guake guake-indicator gucharmap guile-gnome-platform gupnp-tools gurlchecker gvfs gwaei gwave gwc hamster-applet hicolor-icon-theme ibus-libpinyin ibus-libzhuyin icedove iceweasel icewm indicator-applet indicator-session inkscape intltool istanbul jhbuild json-glib k3d kino krb5-auth-dialog lablgtk2 ladish langdrill lazarus leafpad libappindicator libart-lgpl libbonobo libbonoboui libcanberra libchamplain libcroco libcryptui libdbusmenu libdmapsharing libepc libg3d libgda5 libgdata libgksu libglade2 libglademm2.4 libgnome libgnome2-canvas-perl libgnome2-perl libgnome2-vfs-perl libgnomecanvas libgnomecanvasmm2.6 libgnomekbd libgnome-keyring libgnome-media-profiles libgnomeui libgrip libgrss libgtkada libgtksourceviewmm libgtop2 libgweather libgwenhywfar libgwibber libgxps libindicate libinfinity libmateweather libnice libnotify liboobs libosinfo libpeas libproxy libpwquality librcc librest librsvg libsecret libsocialweb libsoup2.4 libunique libunique3 libwnck libwnck3 libxklavier libxml++2.6 libzapojit lightdm linsmith loudmouth mail-notification mate-power-manager mathwar maximus mdbtools meld memphis menulibre metacity meta-gnome3 mialmpick minbar mldonkey mm-common modemmanager monotone-viz monster-masher moonshot-ui mousetweaks mozilla-gnome-keyring mp3splt-gtk mpop msmtp muffin mutter mysql-workbench nautilus nautilus-actions nautilus-open-terminal nautilus-python nautilus-sendto nautilus-wipe nemo netspeed network-manager-applet network-manager-iodine network-manager-strongswan nip2 notebook notification-daemon notify-osd ocamlgraph ocrfeeder ontv openvrml oregano osm-gps-map packagekit padevchooser pan pango1.0 pangomm pangox-compat Passepartout patchage pdfmod pegsolitaire perlpanel petri-foo pike7.8 pioneers pitivi pk-update-icon planner player plotdrop polari postr prepaid-manager-applet pygobject pygobject-2 pygtk pygtksourceview pyhoca-gui pyorbit pywebkitgtk qapt qupzilla rarian referencer remmina revelation rhythmbox sagasu sanduhr seahorse seahorse-nautilus seed sensors-applet sflphone shadow shotwell simple-scan slashtime slmon smbnetfs solfege sound-juicer sound-theme-freedesktop stardict startup-notification subversion sugar-artwork-0.96 sugar-artwork-0.98 swami swt4-gtk swt-gtk syncevolution system-config-printer system-tools-backends taglib-sharp tali teg telegnome terminatorx tomboy totem totem-pl-parser tracker tumbler ubuntulooks uim vala-0.26 vdk2 verbiste viking vim vinagre vino vte vte2.91 vte3 wxwidgets3.0 xchat-gnome xdg-user-dirs xdg-user-dirs-gtk xine-lib-1.2 xiphos xnee xournal x-tile yelp yelp-tools yelp-xsl zapping zenity"
META_LIST[5]="a52dec aalib accountsservice acl adblock-plus adduser adwaita-icon-theme aircrack-ng alsa-lib alsa-plugins amd64-microcode anthy apg apparmor apparmor-profiles-extra appsrc apt aptitude apt-listchanges aspell at atk1.0 atkmm1.6 at-spi2-atk at-spi2-core attr audacity avahi ayaspell-dic b43-fwcutter babl base-files base-passwd bash bash-completion bc bilibop bind9 binutils blas blt bluez BlueZ bookletimposer brasero broadcom-sta-common broadcom-sta-dkms bsd-mailx bsdmainutils build-essential busybox bzip2 ca-certificates ca-certificates-java cairo cairomm caribou ccid cd cdda cdebconf cdparanoia cdrkit chardet cheese chromaprint claws-mail claws-mail-extra-plugins clutter-1.0 clutter-gtk cogl coinor-libcbc3 coinor-libcgl1 coinor-libclp1 coinor-libcoinmp1 coinor-libcoinutils3 coinor-libosi1 colord colord-data configobj connect-proxy console-common console-data console-setup coreutils cpio cpp-4.8 cpp-4.9 cracklib2 crda cron cryptsetup culmus cups cups-core-drivers cups-daemon cups-filters cups-filters-core-drivers cups-pk-helper cups-server-common curl cwidget cyrus-sasl2 dash dasher data dbus dbus-glib dbus-python d-conf dconf-cli debconf debhelper debian-archive-keyring debian-faq debianutils debootstrap deb.torproject.org-keyring desktop-base desktop-file-utils dh-python dictionaries-common diffutils dirac directfb distribute djvulibre dkms dmidecode dmz-cursor-theme doc-debian dosfstools dpatch dpkg dv e2fsprogs ecj eglibc eject ekeyd elfutils emacsen-common enca enchant eog epson-inkjet-printer-escpr equivs espa-nol espeak evince evolution evolution-data-server exempi exim4 exiv2 expat faad2 fakeroot farstream ferm file file-roller findutils firmware-atheros firmware-b43-installer firmware-b43legacy-installer firmware-brcm80211 firmware-free firmware-ipw2x00 firmware-iwlwifi firmware-libertas firmware-linux firmware-linux-nonfree firmware-ralink firmware-realtek firmware-zd1211 flac flite florence fluidsynth fontconfig fonts-arphic-ukai fonts-arphic-uming fonts-beng fonts-beng-extra fonts-cantarell fonts-dejavu fonts-dejavu-core fonts-dejavu-extra fonts-deva fonts-deva-extra fonts-farsiweb fonts-gubbi fonts-gujr fonts-gujr-extra fonts-guru fonts-guru-extra fonts-indic fonts-kacst fonts-kalapi fonts-khmeros fonts-knda fonts-lao fonts-liberation fonts-lklug-sinhala fonts-lohit-beng-assamese fonts-lohit-beng-bengali fonts-lohit-deva fonts-lohit-gujr fonts-lohit-guru fonts-lohit-knda fonts-lohit-mlym fonts-lohit-orya fonts-lohit-taml fonts-lohit-taml-classical fonts-lohit-telu fonts-mlym fonts-nakula fonts-navilu fonts-orya fonts-orya-extra fonts-pagul fonts-sahadeva fonts-samyak fonts-smc fonts-taml fonts-telu fonts-telu-extra fonts-tlwg fonts-tlwg-laksaman fonts-unfonts-core foomatic-db foomatic-db-engine freetype fribidi fuse g++-4.9 game-music-emu gcalctool gcc-4.7 gcc-4.8 gcc-4.8-base gcc-4.9 gcc-4.9-base gcc-defaults gconf gcr gdbm gdisk gdk-pixbuf gdm3 gedit gegl geocode-glib geoip geoip-database gettext ghostscript giflib gimp gir1.2-clutter-gst-2.0 gir1.2-gdm3 gir1.2-ges-1.0 gir1.2-nmgtk-1.0 git gjs gksu glib2.0 glibmm2.4 glib-networking gmime gmp gnome-backgrounds gnome-bluetooth gnome-calculator gnome-control-center gnome-desktop3 gnome-disk-utility gnome-flashback gnome-flashback-common gnome-icon-theme gnome-icon-theme-symbolic gnome-keyring gnome-media gnome-menus gnome-mime-data gnome-online-accounts gnome-orca gnome-panel gnome-power-manager gnome-screensaver gnome-screenshot gnome-search-tool gnome-session gnome-session-flashback gnome-settings-daemon gnome-shell gnome-shell-extensions gnome-speech gnome-system-log gnome-system-monitor gnome-terminal gnome-themes gnome-themes-standard gnome-theme-windows8 gnome-tweak-tool gnome-user-docs gnome-vfs gnupg gnupg2 gnustep-base gnustep-make gnutls26 gnutls28 gobby gobby-infinote gobi-loader gobject-introspection gpgme1.0 gpm grep grilo-plugins-0.2 groff gsasl gsettings-desktop-schemas gsfonts gsl gssdp gst-libav1.0 gst-plugins-bad0.10 gst-plugins-bad1.0 gst-plugins-base0.10 gst-plugins-base1.0 gst-plugins-good0.10 gst-plugins-good1.0 gst-plugins-ugly0.10 gstreamer0.10 gstreamer1.0 gstreamer1.0-clutter gstreamer1.0-gnonlin gtk+2.0 gtk2-engines gtk+3.0 gtkglext gtkhash gtkmm2.4 gtkmm3.0 GtkSourceView gtksourceview3 gtkspell guile-2.0 gupnp gupnp-igd gvfs gzip hachoir-core hachoir-parser hardlink haveged hdparm heimdal hicolor-icon-theme hledger hopenpgp-tools hostname hplip hunspell hunspell-en-us hunspell-fr hyphen i2p i2p-router ibus ibus-anthy ibus-hangul ibus-pinyin ibus-qt iceweasel ifupdown igerman98 ijs ilmbase imagemagick init initramfs-tools init-system-helpers inkscape inotify-tools insserv intel-microcode intlfonts intltool-debian io-stringy iproute2 iptables iputils isc-dhcp isl iso-codes isolinux isomd5sum iucode-tool iw jackd2 jasper java-atk-wrapper java-common jbig2dec jbigkit jigit jquery jqueryui json-c json-glib kbd keepassx kexec-tools keyutils klibc kmod krb5 lame lapack laptop-mode-tools lcms2 ldb less libabw-0.1-1 libalgorithm-c3-perl libaliased-perl libamd2.3.1 libany-moose-perl libao libarchive libarchive-extract-perl libarchive-tar-wrapper-perl libasan0 libasan1 libasound2-data libass5 libassuan libasyncns libatasmart libatomic1 libaudit1 libaudit-common libauthen-sasl-perl libavc1394 libavcodec56 libavformat56 libavresample2 libavutil54 libb-hooks-endofscope-perl libb-hooks-op-check-perl libblas-common libbluray libbonobo libboost-date-time1.55.0 libboost-filesystem1.55.0 libboost-iostreams1.55.0 libboost-regex1.55.0 libboost-system1.55.0 libboost-thread1.55.0 libbrlapi0.6 libbsd libburn libcaca libcairo-perl libcamd2.3.1 libcamel-1.2-49 libcanberra libcap2 libcap-ng libcarp-assert-more-perl libcarp-assert-perl libcarp-clan-perl libccolamd2.8.0 libcdaudio libcdio libcdr-0.1-1 libcgi-pm-perl libcheese7 libcheese-gtk23 libcholmod2.1.2 libcilkrts5 libclass-accessor-perl libclass-c3-perl libclass-c3-xs-perl libclass-data-inheritable-perl libclass-isa-perl libclass-load-perl libclass-load-xs-perl libclass-method-modifiers-perl libclass-singleton-perl libclass-tiny-perl libclone-perl libcloog-isl4 libclucene-contribs1 libclucene-core1 libclutter-gst-2.0-0 libcmis-0.4-4 libcogl20 libcogl-pango20 libcogl-path20 libcolamd2.8.0 libcolord2 libcolorhug2 libcompface libconfig-general-perl libcontext-preserve-perl libconvert-asn1-perl libcpan-meta-perl libcroco libcrypt-openssl-bignum-perl libcrypt-openssl-rsa-perl libcryptui libcrypt-x509-perl libdata-optlist-perl libdata-perl-perl libdata-section-perl libdatetime-format-dateparse-perl libdatetime-locale-perl libdatetime-perl libdatetime-timezone-perl libdatrie libdb5.3 libdb5.3++ libdbusmenu libdc1394-22 libdca libdconf1 libdesktop-notify-perl libdevel-declare-perl libdevel-globaldestruction-perl libdevel-partialdump-perl libdevel-stacktrace-perl libdiscid libdist-checkconflicts-perl libdmapsharing libdns-export100 libdotconf0 libdrm libdrm-nouveau2 libdumbnet libdv libdvdnav libdvdread libeatmydata libeatmydata1 libebackend-1.2-7 libe-book-0.1-1 libebook-1.2-14 libebook-contacts-1.2-0 libecal-1.2-16 libedata-book-1.2-20 libedata-cal-1.2-23 libedataserver-1.2-18 libedit libelf libencode-locale-perl libencode-perl libeot0 libepoxy0 libept liberror-perl libestr libetonyek-0.1-1 libetpan17 libeval-closure-perl libevdev libevent libexif libexiv2-13 libexporter-tiny-perl libexttextcat libexttextcat-2.0-0 libfakeroot libfcgi-perl libffi6 libfftw3-double3 libfftw3-single3 libfile-copy-recursive-perl libfile-homedir-perl libfile-listing-perl libfilesys-df-perl libfile-tail-perl libfile-which-perl libflorence-1.0-1 libfont-afm-perl libfontembed1 libfontenc libfreehand-0.1-1 libgadu libgc libgcc-4.8-dev libgcc-4.9-dev libgcr-base-3-1 libgcr-ui-3-1 libgcrypt20 libgd3 libgdata libgdata19 libgdm1 libgee-0.8-2 libges-1.0-0 libgetopt-long-descriptive-perl libgfshare libgjs0e libgksu libglew1.10 libglib-perl libgltf-0.0-0 libgnome-bluetooth13 libgnome-desktop-3-10 libgnomekbd libgnomekbd8 libgnome-keyring libgnupg-interface-perl libgnustep-base1.24 libgoa-1.0-0b libgoa-backend-1.0-1 libgpg-error libgphoto2-6 libgphoto2-port10 libgraphite2-3 libgrilo-0.2-1 libgsecuredelete libgsm libgtk2-perl libgtksourceview-3.0-1 libgtop2 libgusb libgweather libgweather-3-6 libgxps libhangul libharfbuzz0b libharfbuzz-icu0 libhtml-format-perl libhtml-form-perl libhtml-parser-perl libhtml-tagset-perl libhtml-tree-perl libhttp-cookies-perl libhttp-daemon-perl libhttp-date-perl libhttp-message-perl libhttp-negotiate-perl libhttp-parser2.1 libhttp-server-simple-perl libibus-1.0-5 libical1 libice libicu52 libid3tag libidl libidn libiec61883 libieee1284 libimage-exiftool-perl libimobiledevice4 libimport-into-perl libindicate libinfgtk3-0.6-0 libinfinity-0.6-0 libinput5 libintl-perl libio-html-perl libio-multiplex-perl libio-pty-perl libio-socket-inet6-perl libio-socket-socks-perl libio-socket-ssl-perl libio-string-perl libipc-run-perl libipc-run-safehandles-perl libipc-system-simple-perl libiptcdata libirs-export91 libisccfg-export90 libisc-export95 libisofs libjbigi-jni libjim0.75 libjpeg62-turbo libjson-glib-1.0-common libjson-perl libkate libksba liblangtag1 liblangtag-common liblist-allutils-perl liblist-moreutils-perl libllvm3.5 liblocale-gettext-perl liblockfile liblogging liblog-log4perl-perl liblog-message-perl liblog-message-simple-perl liblognorm1 liblouis liblqr liblucene++0 liblwp-authen-wsse-perl liblwp-mediatypes-perl liblwp-protocol-https-perl liblwp-protocol-socks-perl libmad libmagick++-6.q16-5 libmagickcore-6.q16-2 libmagickwand-6.q16-2 libmailtools-perl libmbim-glib4 libmbim-proxy libmediaart-1.0-0 libmetacity-private2 libmethod-signatures-simple-perl libmimic libmjpegutils-2.1-0 libmm-glib0 libmms libmng libmnl libmodplug libmodule-build-perl libmodule-implementation-perl libmodule-pluggable-perl libmodule-runtime-conflicts-perl libmodule-runtime-perl libmodule-signature-perl libmoo-perl libmoose-perl libmoosex-getopt-perl libmoosex-has-sugar-perl libmoosex-lazyrequire-perl libmoosex-meta-typeconstraint-forcecoercion-perl libmoosex-method-signatures-perl libmoosex-role-parameterized-perl libmoosex-traits-perl libmoosex-types-path-class-perl libmoosex-types-perl libmoosex-types-structured-perl libmoox-handlesvia-perl libmoox-late-perl libmouse-perl libmozjs-24-0 libmpc libmpc3 libmpdec2 libmpeg2encpp-2.1-0 libmplex2-2.1-0 libmro-compat-perl libmspub-0.1-1 libmtp libmusicbrainz5-1 libmutter0e libmwaw-0.3-3 libnamespace-autoclean-perl libnamespace-clean-perl libndp0 libnet-cidr-perl libnet-dbus-glib-perl libnet-dbus-perl libnetfilter-acct1 libnet-http-perl libnet-server-perl libnet-smtp-ssl-perl libnet-ssleay-perl libnfnetlink libnfsidmap libnice libnl3 libnotify libntlm libnumber-format-perl liboauth libodfgen-0.1-1 libofa libogg libopencv-calib3d2.4 libopencv-contrib2.4 libopencv-core2.4 libopencv-features2d2.4 libopencv-flann2.4 libopencv-highgui2.4 libopencv-imgproc2.4 libopencv-legacy2.4 libopencv-ml2.4 libopencv-objdetect2.4 libopencv-video2.4 libopenjpeg5 libopenraw liborbit-2-0 liborcus-0.8-0 libotr libpackage-constants-perl libpackage-deprecationmanager-perl libpackagekit-glib2-18 libpackage-stash-perl libpackage-stash-xs-perl libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 libpango-perl libpangox-1.0-0 libpangoxft-1.0-0 libpaper libparams-classify-perl libparams-util-perl libparams-validate-perl libparse-debianchangelog-perl libparse-method-signatures-perl libparse-syslog-perl libparted2 libpath-class-perl libpcap libpciaccess libpeas libperl4-corelibs-perl libperl5.20 libphonenumber6 libpipeline libplist2 libpng libpod-latex-perl libpodofo libpod-readme-perl libppi-perl libprocps3 libprotobuf9 libprotobuf-c1 libproxy1 libpsl0 libpwquality1 libpwquality-common libpython2.7-minimal libpython2.7-stdlib libpython3.4 libpython3.4-minimal libpython3.4-stdlib libpython3-stdlib libpython-stdlib libpyzy-1.0-0 libqmi-glib1 libqmi-proxy libqpdf13 libquvi libquvi-scripts libraw1394 libregexp-common-perl libreoffice librest librevenge-0.0-0 librole-tiny-perl librsvg librtmp1 libruby2.1 libsamplerate libsasl2-modules-db libsbsms libsdl1.2 libseccomp libsecret-1-0 libsecret-common libselinux libsemanage libsepol libshout libsidplay libsigc++-2.0 libsigsegv libsm libsmartcols1 libsndfile libsnmp30 libsocket6-perl libsoftware-license-perl libsoup2.4 libsoxr0 libspectre libssh2 libstdc++-4.9-dev libstrictures-perl libstring-errf-perl libstring-formatter-perl libsub-exporter-perl libsub-exporter-progressive-perl libsub-identify-perl libsub-install-perl libsub-name-perl libswitch-perl libswscale3 libsys-statistics-linux-perl libsystemd0 libtask-weaken-perl libtasn1-6 libtcl8.6 libteamdctl0 libtelepathy-logger3 libterm-ui-perl libtext-charwidth-perl libtext-iconv-perl libtext-soundex-perl libtext-template-perl libtext-unidecode-perl libtext-wrapi18n-perl libthai libtheora libtimedate-perl libtirpc libtk8.6 libtool libtotem-plparser18 libtracker-sparql-1.0-0 libtry-tiny-perl libtype-tiny-perl libubsan0 libudisks2-0 libumfpack5.6.2 libunique3 libunistring libuniversal-require-perl libunix-mknod-perl libupower-glib3 liburi-perl libusb libusb-1.0 libusbmuxd2 libusbx libuuid-perl libva libvariable-magic-perl libvisio-0.1-1 libvisual libvorbis libvpx libvte-2.91-0 libvte-2.91-common libwacom libwayland-client0 libwayland-cursor0 libwayland-egl1-mesa libwayland-server0 libwebp5 libwebpdemux1 libwebpmux1 libwmf libwnck3 libwpd-0.10-10 libwpg-0.3-3 libwps-0.3-3 libwww-curl-perl libwww-perl libwww-robotrules-perl libx11 libx264-142 libxatracker2 libxau libxaw libxcb libxcomposite libxcursor libxdamage libxdmcp libxdo3 libxext libxfixes libxfont libxi libxinerama libxkbcommon0 libxkbcommon-x11-0 libxkbfile libxklavier libxml2 libxml++2.6 libxml-atom-perl libxml-libxml-perl libxml-libxslt-perl libxml-namespacesupport-perl libxml-parser-perl libxml-sax-base-perl libxml-sax-expat-perl libxml-sax-perl libxml-twig-perl libxml-xpath-perl libxmu libxpm libxrandr libxrender libxres libxshmfence1 libxslt libxss libxt libxtables10 libxtst libxv libxvmc libxxf86dga libxxf86vm libyaml libyaml-libyaml-perl libyaml-perl liferea lilv linux linux-base linux-compiler-gcc-4.8-x86 linux-headers-3.16.0-4-586 linux-headers-3.16.0-4-amd64 linux-headers-3.16.0-4-common linux-image-3.16.0-4-586 linux-image-3.16.0-4-amd64 linux-tools lirc live-boot live-build live-config live-tools liveusb-creator lm-sensors lockfile-progs logrotate lp-solve lsb lsof lua5.1 lua5.2 luasocket lvm2 lxml lyx lzma lzo2 m4 macchanger make-guile man-db manpages mat matplotlib mawk meanwhile memlockd mesa metacity mhash mime-support mlocate mobile-broadband-provider-info modemmanager monkeysign monkeysphere moreutils mousetweaks mpeg2dec mpfr4 mpg123 msmtp msva-perl mtdev mtools mutagen mutt mutter myspell-fa myspell.pt myspell-pt-br mythes nano nas nautilus nautilus-wipe ncurses neon27 netbase netcat netkit-ftp netkit-telnet net-snmp nettle net-tools network-manager network-manager-applet newt nfacct nfs-utils notification-daemon notify-python nspr nss ntdb ntfs-3g obfsproxy Open openal-soft opencc opencore-amr openexr openjdk-7 openldap openoffice.org-dictionaries openssh openssl open-vm-tools opus orbit2 orc p11-kit p7zip packagekit pam pango1.0 pangomm parted patch pciutils pcre3 pcsc-lite pdfrw perl pexpect pidgin pidgin-otr pilot-link pinentry pitivi pixman ply plymouth po-debconf poedit poedit-common policykit-1 policykit-1-gnome poppler poppler-data popt portaudio19 portsmf ppp procmail procps psmisc pth pulseaudio pv pwgen py3cairo pyasn1 pyatspi pycairo pycountry pycparser pycurl pygments pygobject pygobject-2 pygtk pyicu pyinotify pyme pyopenssl pyparsing pyptlib pyserial python2.7 python3.4 python3.4-minimal python3-brlapi python3-defaults python3-louis python3-speechd python3-xdg python-apt python-cffi python-characteristic python-crypto python-cryptography python-cups python-dateutil python-debianbts python-defaults python-defusedxml python-docutils python-geoip python-gnutls python-gst-1.0 python-imaging python-numpy python-pil python-poppler python-pyasn1-modules python-pypdf python-qrencode python-qt4 python-reportlab python-service-identity python-soappy python-stdlib-extensions python-support python-torctl python-tz python-wstools pyxdg pyyaml qrencode qt4-x11 qt-assistant-compat qt-at-spi qtchooser qtwebkit raptor2 rasqal readline5 readline6 redland rename reportbug resolvconf rfkill rpcbind rsync rsyslog rus-ispell samba sane-backends sbc schroedinger scowl seahorse seahorse-nautilus secure-delete sed sensible-utils serd service-wrapper-java sg3-utils sgml-base shadow shared-mime-info simple-scan sip4 six slang2 slv2 sonic sord sound-juicer soundtouch spandsp speech-dispatcher speech-dispatcher-audio-plugins speex spice-vdagent sqlite3 squashfs-tools sratom srtp sshfs-fuse ssl-cert ssss startpar startup-notification sudo synaptic sysfsutils syslinux syslinux-efi syslinux-utils system-config-printer systemd sysvinit taglib tails-greeter tails-iuk tails-perl5lib tails-persistence-setup talloc tar tasksel tbb tcpdump tcpflow tcp-wrappers tdb telepathy-glib telepathy-logger telepathy-mission-control-5 tevent texinfo texlive-bin tiff time tk8.6-blt2.5 tokyocabinet tor tor-arm torsocks totem totem-pl-parser traceroute traverso tsocks ttdnsd ttf-dejavu twisted twisted-conch twisted-lore twisted-mail twisted-names twisted-news twisted-runner twisted-web twisted-words twolame tzdata ucf udev udisks udisks2 unar unifont unzip update-inetd upower urlgrabber usb-modeswitch usb-modeswitch-data usbutils user-setup ustr util-linux v4l-utils vamp-plugin-sdk vidalia vim virtualbox vo-aacenc vo-amrwbenc vte3 w3m wavpack webkit webrtc-audio-processing wget whois wildmidi window-picker-applet wireless-regdb wireless-tools wpa wxwidgets3.0 x11-apps x11-session-utils x11-utils x11-xkb-utils x11-xserver-utils xapian-core xauth xcb-util xclip xdg-user-dirs xdg-utils xdotool xfonts-100dpi xfonts-75dpi xfonts-base xfonts-bolkhov xfonts-cronyx xfonts-encodings xfonts-scalable xfonts-utils xfonts-wqy xft xinit xkeyboard-config xml-core xorg xorg-docs xorg-server xserver-xorg-input-evdev xserver-xorg-input-mouse xserver-xorg-input-synaptics xserver-xorg-input-vmmouse xserver-xorg-video-ati xserver-xorg-video-cirrus xserver-xorg-video-fbdev xserver-xorg-video-geode xserver-xorg-video-intel xserver-xorg-video-mach64 xserver-xorg-video-mga xserver-xorg-video-modesetting xserver-xorg-video-neomagic xserver-xorg-video-nouveau xserver-xorg-video-openchrome xserver-xorg-video-qxl xserver-xorg-video-r128 xserver-xorg-video-savage xserver-xorg-video-siliconmotion xserver-xorg-video-sisusb xserver-xorg-video-tdfx xserver-xorg-video-trident xserver-xorg-video-vesa xserver-xorg-video-vmware xul-ext-torbutton xvidcore xwayland xz-utils yajl yelp yelp-xsl zbar zenity zephyr zlib zope.interface zvbi"
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
		sqlite3 -init ${INIT} ${PACKAGES_DB} "INSERT INTO ${TABLE[6]} VALUES (\"$DATE\", \"$SUITE\", \"${META_PKG[$i]}\", $META_GOOD, $META_BAD, $META_UGLY, $META_REST)"
		touch -d "$DATE 00:00" ${TABLE[6]}_${META_PKG[$i]}.png
	fi
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
FIELDS[6]="datum, reproducible, unreproducible, FTBFS, other"
COLOR[0]=5
COLOR[1]=4
COLOR[2]=3
COLOR[3]=18
COLOR[4]=1
COLOR[5]=1
COLOR[6]=4
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

