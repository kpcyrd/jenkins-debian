#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# Copyright 2009-2015 Holger Levsen (holger@layer-acht.org)
#
# based on similar code taken from piuparts-reports.py written by me

import os
import sys
from rpy2 import robjects
from rpy2.robjects.packages import importr

def main():
    if len(sys.argv) != 6:
        print "we need exactly five params: csvfilein, pngoutfile, color, mainlabel, ylabl"
        return
    filein = sys.argv[1]
    fileout = sys.argv[2]
    colors = sys.argv[3]
    columns = str(int(colors)+1)
    mainlabel = sys.argv[4]
    ylabel = sys.argv[5]
    countsfile = os.path.join(filein)
    pngfile = os.path.join(fileout)
    grdevices = importr('grDevices')
    grdevices.png(file=pngfile, width=1600, height=800, pointsize=10, res=100, antialias="none")
    r = robjects.r
    r('t <- (read.table("'+countsfile+'",sep=",",header=1,row.names=1))')
    r('cname <- c("date",rep(colnames(t)))')
    # thanks to http://tango.freedesktop.org/Generic_Icon_Theme_Guidelines for those nice colors
    if int(colors) < 6:
        r('palette(c("#73d216", "#f57900", "#cc0000", "#2e3436", "#888a85"))')
    elif int(colors) == 12:
        r('palette(c("#4e9a06", "#73d216", "#8ae234", \
                     "#ce5c00", "#f57900", "#fcaf3e", \
                     "#a40000", "#cc0000", "#ef2929", \
                     "#2e3436", "#555753", "#888a85" ))')
    elif int(colors) < 39:
        r('palette(c("#fce94f", "#c4a000", "#eeeeec", "#babdb6", \
                     "#fcaf3e", "#ce5c00", "#ad7fa8", "#5c3566", \
                     "#e9b96e", "#8f5902", "#8ae234", "#4e9a06", \
                     "#729fcf", "#204a87", "#ef2929", "#a40000", \
                     "#888a85", "#2e3436", "#75507b", "#cc0000", \
                     "#ce5c00", "#73d216", "#edd400", "#f57900", \
                     "#c17d11", "#3465a4", "#666666", "#AAAAAA" ))')
    elif int(colors) == 40:
        r('palette(c("#4e9a06", "#000000"))')
    elif int(colors) == 41:
        r('palette(c("#73d216", "#000000"))')
    elif int(colors) == 42:
        r('palette(c("#8ae234", "#000000"))')
    # "revert the hack" (it's still a hack :)
    if int(colors) >= 40:
        colors='1'
    r('v <- t[0:nrow(t),0:'+colors+']')
    # make graph since day 1
    r('barplot(t(v),col = 1:'+columns+', main="'+mainlabel+'", xlab="", ylab="'+ylabel+'", space=0, border=NA)')
    if int(colors) < 10:
        r('legend(x="bottom",legend=colnames(t), ncol=2,fill=1:'+columns+',xjust=0.5,yjust=0,bty="n")')
    elif int(colors) == 12:
        r('legend(x="bottom",legend=colnames(t), ncol=4,fill=1:'+columns+',xjust=0.5,yjust=0,bty="n")')
    else:
        r('legend(x="bottom",legend=colnames(t), ncol=7,fill=1:'+columns+',xjust=0.5,yjust=0,bty="n")')
    grdevices.dev_off()

if __name__ == "__main__":
    main()

# vi:set et ts=4 sw=4 :
