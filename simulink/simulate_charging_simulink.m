function L = simulate_charging_simulink(p, atk, opts, mdl)
%SIMULATE_CHARGING_SIMULINK  Run EV_BMS_Simscape.slx for one attack and
%   return the same log struct as simulate_charging.m, so the existing
%   metrics and plotting functions work unchanged.
%   opts: defence (true/false), thr ([] = statistics only), seed
if nargin < 4, mdl = 'EV_BMS_Simscape'; end
load_system(mdl);

thr = opts.thr;
if isempty(thr)
    thr = struct('pack', Inf, 'curr', Inf, 'innov', Inf, 'noise', Inf);
end
s0 = 100 * opts.seed;

in = Simulink.SimulationInput(mdl);
in = in.setVariable('bp', sim_params(p));
in = in.setVariable('ac', attack_code(atk));
in = in.setVariable('thr', thr);
in = in.setVariable('defence', double(opts.defence));
in = in.setVariable('seed_meas', s0 + (1:10));
in = in.setVariable('seed_atk', s0 + (11:14));
in = in.setVariable('seed_u', s0 + 15);
out = sim(in);

L = out_to_L(out, p);
end
