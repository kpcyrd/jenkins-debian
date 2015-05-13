#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015 Mattia Rizzolo <mattia@mapreri.org>
#Based on reproducible_html_all_packages.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build all rb-pkg pages (the pages that describe the package status) using
# code already written in reproducible_html_packages


from reproducible_html_packages import gen_all_rb_pkg_pages


gen_all_rb_pkg_pages(no_clean=True)
