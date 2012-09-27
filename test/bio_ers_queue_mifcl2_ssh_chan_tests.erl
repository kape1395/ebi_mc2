-module(bio_ers_queue_mifcl2_ssh_chan_tests).
%%
%%  Temporary.
%%

%
% rr(bio_ers).
% application:start(crypto), application:start(ssh).
% {ok, PID} = bio_ers_queue_mifcl2_ssh_chan:start_link().
% ok = bio_ers_queue_mifcl2_ssh_chan:check(PID).
% 
% Model = bio_ers_model:read_model("test/bio_ers_model_tests-CNT-2D.xml", kp1_xml).
% #model{definition = ModelDef} = Model.
% ModelId = bio_ers:get_id(Model).
% bio_ers_queue_mifcl2_ssh_chan:store_config(PID, ModelId, ModelDef).
% 
% 
% Param1 = #param{name='S_0', value=0.5}.
% Param2a = #param{name='M_0', value=5.0e-3}.
% Param2b = #param{name='M_0', value=5.0e-4}.
% Param2c = #param{name='M_0', value=5.0e-5}.
% Param2d = #param{name='M_0', value=5.0e-6}.
% 
% Sa = #simulation{model = Model, params = [Param1, Param2a]}.
% Sb = #simulation{model = Model, params = [Param1, Param2b]}.
% Sc = #simulation{model = Model, params = [Param1, Param2c]}.
% Sd = #simulation{model = Model, params = [Param1, Param2d]}.
% 
% bio_ers_queue_mifcl2_ssh_chan:submit_simulation(PID, Sa).
% bio_ers_queue_mifcl2_ssh_chan:submit_simulation(PID, Sb).
% bio_ers_queue_mifcl2_ssh_chan:submit_simulation(PID, Sc).
% bio_ers_queue_mifcl2_ssh_chan:submit_simulation(PID, Sd).
% 
% bio_ers_queue_mifcl2_ssh_chan:simulation_status(PID, Sa).
% bio_ers_queue_mifcl2_ssh_chan:simulation_status(PID, Sb).
% bio_ers_queue_mifcl2_ssh_chan:simulation_status(PID, Sc).
% bio_ers_queue_mifcl2_ssh_chan:simulation_status(PID, Sd).
% 
% {ok, SIDc, RESc} = bio_ers_queue_mifcl2_ssh_chan:simulation_result(PID, Sc).
% file:write_file(lists:flatten([SIDc, ".tar.gz"]), binary:list_to_bin(RESc)).
% 
% bio_ers_queue_mifcl2_ssh_chan:cancel_simulation(PID, Sa).
% bio_ers_queue_mifcl2_ssh_chan:delete_simulation(PID, Sa).
% 
% ok = bio_ers_queue_mifcl2_ssh_chan:stop(PID).
% 
