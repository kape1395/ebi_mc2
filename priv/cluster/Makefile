CLUSTER_HOME=/scratch/lustre/karolis/PST
MANAGER_HOME=/users3/karolis/PST
SOLVER_BIN=biosensor-0.6.6-amd64-debian-6.0.4.tar.gz

all:
	@echo "Try to run make install-cluster or install-manager"

install-cluster: $(SOLVER_BIN)
	mkdir -p $(CLUSTER_HOME)
	mkdir -p $(CLUSTER_HOME)/bin
	mkdir -p $(CLUSTER_HOME)/cfg
	mkdir -p $(CLUSTER_HOME)/sim
	cp bio-solver bio-solver-sup.awk cleanup $(CLUSTER_HOME)/bin
	tar -xzf $(SOLVER_BIN) -C $(CLUSTER_HOME)

install-manager:
	mkdir -p $(MANAGER_HOME)
	mkdir -p $(MANAGER_HOME)/bin
	cp cluster cluster-shell $(MANAGER_HOME)/bin


$(SOLVER_BIN):
	wget http://karolis.5grupe.lt/ebi/archive/$(SOLVER_BIN)

