

PYYAMLS := $(basename $(wildcard *.yaml.py))

YAMLS := $(wildcard *.yaml) $(PYYAMLS)

XMLS := $(patsubst %.yaml,%.xml,$(YAMLS))

OUTS := $(patsubst %.yaml,%.jjb-out,$(YAMLS))

OUTPUTS := $(PYYAMLS) $(XMLS) $(OUTS) zombie-names.txt jobs-names.txt

all:  $(OUTPUTS)

%.yaml: %.yaml.py
	./$< > $@


%.xml %.jjb-out: %.yaml
	jenkins-job-builder test $< > $*.xml 2> $*.jjb-out

jobs-names.txt: $(OUTS)
	sed -n 's/^INFO:jenkins_jobs.builder:Job name:  //p' $(OUTS) > $@

zombie-names.txt: jobs-names.txt ~jenkins/jobs/
	ls ~jenkins/jobs/ | grep -f jobs-names.txt -F -v > $@

clean:
	-rm $(OUTPUTS)
