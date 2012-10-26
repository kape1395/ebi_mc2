REBAR=rebar

compile:
	$(REBAR) compile

itest: compile
	$(REBAR) ct apps=ebi_mc2

clean:
	$(REBAR) clean apps=ebi_mc2

clean-all:
	$(REBAR) clean

test:
	$(REBAR) eunit apps=ebi_mc2

.PHONY: compile itest clean test

