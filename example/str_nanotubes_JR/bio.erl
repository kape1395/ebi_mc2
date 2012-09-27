-module(bio).
-export([params_diffusion/8, params_enzyme/3, exp_seq/3]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Expressions for diffusion coefficients as defined in the CNT article.
%%  Value for Alpha parameters are also calculated.
%%
%%  For the exact match with the initial diffusion coefficients:
%%      bio:params_diffusion(3.0e-10, 6.0e-10, 0.125*4/3=1/6, 0.25, 0.25*4/3=1/3, 0.5, 0.5, math:pow(0.25, 2)).   
%%      {{dr,[3.0e-10,7.5e-11,1.5e-10,6.0e-10]},
%%       {dz,[3.0e-10,1.5e-10,3.0e-10,6.0e-10]},
%%       {d,[3.0e-10,1.5e-10,1.875e-11,6.0e-10]},
%%       {a2,2.0},
%%       {a3,2.0}}
%%
%%  Acceptable results can be obtained using:
%%      bio:params_diffusion(3.0e-10, 6.0e-10, 0.125, 0.25, 0.25, 0.5, 0.5, math:pow(0.25, 2)).
%%      {{dr,[3.0e-10,5.625e-11,1.5e-10,6.0e-10]},
%%       {dz,[3.0e-10,1.125e-10,3.0e-10,6.0e-10]},
%%       {d,[3.0e-10,1.125e-10,1.875e-11,6.0e-10]},
%%       {a2,2.0},
%%       {a3,2.0}}
%%
params_diffusion(De, Dn, Theta2r, Theta3r, Theta2z, Theta3z, Eta, Rho) ->
    Alpha2 = Theta2z / Theta2r,
    Alpha3 = Theta3z / Theta3r,

    D1r = De,
    D2r = Theta2r * (Eta * De + (1 - Eta) * Dn),
    D3r = Theta3r * Dn,
    D4r = Dn,

    D1z = D1r,
    D2z = D2r * Alpha2,
    D3z = D3r * Alpha3,
    D4z = D4r,

    D1 = D1z,
    D2 = D2z,
    D3 = D3z * Rho,
    D4 = D4z,

    {
        {dr, [D1r, D2r, D3r, D4r]},
        {dz, [D1z, D2z, D3z, D4z]},
        {d,  [D1,  D2,  D3,  D4 ]},
        {a2, Alpha2},
        {a3, Alpha3}
    }.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%  Calculates initial concentrations for the enzyme. To get the default config:
%%      bio:params_enzyme(4.55E-2, 1/200, 0.5).
%%
-record(params_E, {e_0, e_1, e_1a}).
params_enzyme(E0, Alpha, Eta) ->
    Eox1 = E0,
    Eox2 = (1 - Alpha) * Eta * E0,
    Eeox2 = Alpha * Eta * E0,
    #params_E{e_0 = Eox1, e_1 = Eox2, e_1a = Eeox2}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Create exponentialy increasing/decreasing sequence.
%%  Example:
%%      bio:exp_seq(1, 0.5, 4).  
%%      [1,0.5,0.25,0.125]
%%
exp_seq(From, Ratio, Count) ->
    lists:reverse(exp_seq_int([From], Ratio, Count-1)).

exp_seq_int(Seq, _, 0) ->
    Seq;
exp_seq_int([H | T], Ratio, Count) ->
    exp_seq_int([H * Ratio | [H | T]], Ratio, Count-1).



