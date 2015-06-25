

PYYAMLS := $(basename $(wildcard *.yaml.py))

YAMLS := $(wildcard *.yaml) $(PYYAMLS)

XMLS := $(patsubst %.yaml,%.xml,$(YAMLS))

OUTPUTS := $(PYYAMLS) $(XMLS)

all:  $(OUTPUTS)

%.yaml: %.yaml.py
	./$< > $@

%.xml: %.yaml
	jenkins-jobs test $< > $@

clean:
	rm $(sort $(OUTPUTS))
