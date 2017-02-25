.PHONY: all

all: Release InRelease Release.gpg

BINARY_PACKAGES = $(sort $(wildcard *.deb))
SOURCE_PACKAGES = $(sort $(wildcard *.dsc))
GPG_KEY := 248645A4EA225CC4DA9B5370F0157CE09656467C
SECRING := /var/lib/jenkins/.gnupg/secring.gpg
PUBRING := /var/lib/jenkins/.gnupg/pubring.gpg
GPG_OPTS := --no-default-keyring --secret-keyring=$(SECRING) --keyring=$(PUBRING) -u $(GPG_KEY) --digest-algo SHA512

Release: Packages Sources Packages.gz Sources.gz
	apt-ftparchive -o APT::FTPArchive::Release::Origin=jenkins-debian-net-d-i-jobs \
		release . > $@.new
	mv $@.new $@
	chmod 664 $@

InRelease: Release
	gpg $(GPG_OPTS) --clearsign -o - Release > $@.new
	mv $@.new $@
	chmod 664 $@

Release.gpg: Release
	gpg $(GPG_OPTS) -o - -abs Release > $@.new
	mv $@.new $@
	chmod 664 $@

Packages: $(BINARY_PACKAGES)
	apt-ftparchive packages . > $@.new
	mv $@.new $@
	chmod 664 $@

Sources: $(SOURCE_PACKAGES)
	apt-ftparchive sources . > $@.new
	mv $@.new $@
	chmod 664 $@
	for i in $? ; do [ -f .kgb-stamp/$$i.stamp ] || ( /home/groups/kgb/bin/kgb-client-trunk --conf /home/groups/reproducible/private/kgb-client.conf --relay-msg "$$i has just been uploaded to https://wiki.debian.org/ReproducibleBuilds/ExperimentalToolchain" && echo "$$i has just been uploaded to https://wiki.debian.org/ReproducibleBuilds/ExperimentalToolchain" | mail -s "package uploaded to our repo" phil@hands.com && touch .kgb-stamp/$$i.stamp ) ; done

Packages.gz: Packages
	gzip -n9 < $< > $@.new
	mv $@.new $@
	chmod 664 $@

Sources.gz: Sources
	gzip -n9 < $< > $@.new
	mv $@.new $@
	chmod 664 $@

