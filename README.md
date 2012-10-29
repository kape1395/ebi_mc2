# `ebi_mc2`

Mif Cluster v2 queue implementation for Erlang Biosensor simulation coordinator (EBI).
This module is based on the erlang's [SSH chanel implementation][1]. The notes on
coniguring such connections are provided along with the [server side scripts][2].


## Manual startup

Build the server and start the erlang shell:

    make clean compile
    env ERL_LIBS=deps:. erl -config ebi_mc2-test

In the erlang shell:

    application:start(crypto).
    application:start(ssh).
    application:start(xmerl).
    application:start(mnesia).
    lager:start().
    % Here you can include the tracing calls.
    application:start(ebi).
    application:start(ebi_mc2).
    rr(ebi).
    Model = ebi_model:read_model("example/str_nanotubes_JR/model-1D-k2fin-t5.xml", kp1_xml).
    Simulation = #simulation{model = Model, params = []}.
    ebi_queue:submit(ebi_mc2_queue, Simulation).
    init:stop().


## Tracing

In the erlang shell:

    dbg:start().
    dbg:tracer().
    %dbg:tracer(port,dbg:trace_port(file,"dbg-trace.log")).  %% How to read the output file?
    ModulesToTrace = [ebi_queue, ebi_mc2_queue, ebi_mc2_simulation, ebi_mc2_simulation_set_sup, ebi_mc2_cluster].
    lists:foreach(fun (M) -> dbg:tpl(M, dbg:fun2ms(fun(_) -> return_trace() end)) end, ModulesToTrace).
    dbg:p(all, c).
    %dbg:stop_clear().



[1]: http://binaries.erlang-solutions.com/R15A/lib/ssh-2.0.8./src/ssh_shell.erl (Erlang SSH Shell)
[2]: priv/cluster/README.md (EBI MC2 Cluster-side implementation description)
