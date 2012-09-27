
%%
%%  Partition configuration.
%%
-record(part_cfg, {name,
    ssh_host, ssh_port, ssh_user, local_user_dir,
    cluster_command, cluster_partition,
    max_parallel_jobs, status_check_ms
}).

%%
%%  Queue configuration.
%%
-record(cfg, {name, partitions = []}).

-record(ebi_mifcl2_sim, {id, definition, state}).
