include ../Makefile.common

LANGS = de fr pt

DESC_de/ = Debian-Hilfswerkzeuge
DESC_fr/ = Utilitaires Debian
DESC_pt/ = Utilitários Debian

GEN_TR_MAN1S := $(sort $(foreach lang,$(LANGS),$(patsubst %.1,$(lang)/%.$(lang).1,$(GEN_MAN1S))))

all: translate
# GEN_TR_MAN1S needs translate finished, serialize the calls
	@$(MAKE) transform
transform: $(GEN_TR_MAN1S)

translate: ../doc/devscripts.7
	po4a --previous --no-backups --keep=0 devscripts-po4a.conf
	touch $@

clean: ../doc/devscripts.7
	po4a --previous --rm-translations --no-backups devscripts-po4a.conf
	rm -f $(GEN_TR_MAN1S) translate
	rm -rf $(LANGS)

../doc/devscripts.7:
	# po4a translate and clean need ../doc/devscripts.7, rebuild it
	$(MAKE) -C ../doc devscripts.7

%.1:: %.pl translate
	-podchecker $<
	pod2man --utf8 --center=" " --release="$(DESC_$(dir $@))" $< > $@
%.1:: %.pod translate
	-podchecker $<
	pod2man --utf8 --center=" " --release="$(DESC_$(dir $@))" $< > $@
%.1:: %.dbk translate
	mkdir -p $(LANGS)
	xsltproc --nonet -o $@ \
	  /usr/share/sgml/docbook/stylesheet/xsl/nwalsh/manpages/docbook.xsl $<
