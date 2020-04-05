objtype=amd64
</$objtype/mkfile

KTZERO=0xffffffff80110000

OBJ=\
	l.$O\
	kern.$O\

kern:	$OBJ
	$LD -o $target -T$KTZERO -l $prereq

kern.$O:	kern.c
	$CC $CFLAGS kern.c

l.$O:	l.s
	$AS $AFLAGS l.s

kern.iso:	kern
	rm -f kern.iso
	@{rfork n
	bind /root /n/src9
	bind kern /n/src9/amd64/9pc64
	bind plan9.ini /n/src9/cfg/plan9.ini
	disk/mk9660 -c9j -B 386/9bootiso \
		-p <{cat 9bootproto} \
		-s /n/src9 -v 'Plan 9 BareBones' $target
	}

clean:V:
	rm -f *.$O kern.iso kern
