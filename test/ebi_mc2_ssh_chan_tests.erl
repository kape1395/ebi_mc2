-module(ebi_mc2_ssh_chan_tests).
%%
%%  Temporary.
%%

%
% rr(ebi).
%
% [application:start(M) || M <- [crypto, ssh, mnesia, xmerl, ebi, ebi_mc2]].
%
% application:start(crypto), application:start(ssh), application:start(mnesia).
% {ok, PID} = ebi_queue_mifcl2_ssh_chan:start_link().
% ok = ebi_queue_mifcl2_ssh_chan:check(PID).
% 
% Model = ebi_model:read_model("test/ebi_model_tests-CNT-2D.xml", kp1_xml).
% #model{definition = ModelDef} = Model.
% ModelId = ebi:get_id(Model).
% ebi_queue_mifcl2_ssh_chan:store_config(PID, ModelId, ModelDef).
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
% ebi_queue_mifcl2_ssh_chan:submit_simulation(PID, Sa).
% ebi_queue_mifcl2_ssh_chan:submit_simulation(PID, Sb).
% ebi_queue_mifcl2_ssh_chan:submit_simulation(PID, Sc).
% ebi_queue_mifcl2_ssh_chan:submit_simulation(PID, Sd).
% 
% ebi_queue_mifcl2_ssh_chan:simulation_status(PID, Sa).
% ebi_queue_mifcl2_ssh_chan:simulation_status(PID, Sb).
% ebi_queue_mifcl2_ssh_chan:simulation_status(PID, Sc).
% ebi_queue_mifcl2_ssh_chan:simulation_status(PID, Sd).
% 
% {ok, SIDc, RESc} = ebi_queue_mifcl2_ssh_chan:simulation_result(PID, Sc).
% file:write_file(lists:flatten([SIDc, ".tar.gz"]), binary:list_to_bin(RESc)).
% 
% ebi_queue_mifcl2_ssh_chan:cancel_simulation(PID, Sa).
% ebi_queue_mifcl2_ssh_chan:delete_simulation(PID, Sa).
% 
% ok = ebi_queue_mifcl2_ssh_chan:stop(PID).
% 
