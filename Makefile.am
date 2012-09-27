#
# Copyright 2012 Karolis Petrauskas
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

REBAR=/opt/rebar/bin/rebar

all: erlang-compile erlang-test erlang-doc

erlang-compile:
	$(REBAR) compile

erlang-test: priv/bio_ers_solver_port
	$(REBAR) eunit

erlang-itest: priv/bio_ers_solver_port
	$(REBAR) ct

erlang-doc:
	rm -f doc/edoc-info doc/*.html
	$(REBAR) doc

erlang-clean:
	$(REBAR) clean
	rm -rfv ebin priv/bio_ers_solver_port *.log

priv/bio_ers_solver_port: ../bio_ers_solver_port/.libs/bio_ers_solver_port
	make -C ../bio_ers_solver_port
	cp ../bio_ers_solver_port/.libs/bio_ers_solver_port priv/


################################################################################
#   Formalities...
#
clean-local: erlang-clean

check-local: erlang-test erlang-itest

html-local: erlang-doc

#dist-local: bio_ers.tar.gz

.PHONY: all clean-local check-local html-local dist-local erlang-compile erlang-test erlang-itest erlang-doc erlang-clean

