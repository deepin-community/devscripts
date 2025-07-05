include ../Makefile.common

all: devscripts.7

clean:
	rm -f devscripts.7 devscripts.7.tmp.*

# There is a slight chance this gets called twice, once here from here and once
# from ../po4a/Makefile. Treat files with care.
PID := $(shell echo $$$$-$$PPID)
devscripts.7: devscripts.7.in ../README.md genmanpage.pl
	cat $< > $@.tmp.$(PID)
	cat ../README.md | \
		awk '/^- annotate-output/,/^  mailing lists./'|sed -e '/^[[:space:]]*$$/d' -e 's/^/ /g' | \
		perl genmanpage.pl \
		>> $@.tmp.$(PID)
	mv $@.tmp.$(PID) $@

install: install_man1 install_man5 install_man7

install_man1: *.1
	install -d "$(DESTDIR)$(MAN1DIR)"
	install -m0644 -t "$(DESTDIR)$(MAN1DIR)" $^
install_man5: *.5
	install -d "$(DESTDIR)$(MAN5DIR)"
	install -m0644 -t "$(DESTDIR)$(MAN5DIR)" $^
install_man7: *.7 devscripts.7
	install -d "$(DESTDIR)$(MAN7DIR)"
	install -m0644 -t "$(DESTDIR)$(MAN7DIR)" $^
