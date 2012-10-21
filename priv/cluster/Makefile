PST_HOME=/scratch/lustre/karolis/PST

all:
	@echo "Try to run make install"

install:
	mkdir -p $(PST_HOME)
	mkdir -p $(PST_HOME)/bin
	mkdir -p $(PST_HOME)/cfg
	mkdir -p $(PST_HOME)/sim
	cp bin/bio-solver* bin/cleanup $(PST_HOME)/bin
	tar -xzf biosensor-0.6.6-amd64-debian-6.0.4.tar.gz -C $(PST_HOME)

#push-data:
#	cp -r data $(PST_HOME)

