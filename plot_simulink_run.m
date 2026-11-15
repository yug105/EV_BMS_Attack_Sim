%% Plot the run you just started with the Run button in Simulink
%  (after setup_simulink_run.m). Uses the "out" variable Simulink creates.
if ~exist('out', 'var') || ~exist('run_info', 'var')
    error('Run setup_simulink_run, press Run in Simulink, then run this.');
end
p = bms_params();
L = out_to_L(out, p);
a = run_info.attack;
if run_info.defence
    a.name = [a.name ' - with defence'];
else
    a.name = [a.name ' - no defence'];
end
plot_scenario(L, L, a, p, '');
hit = find(L.alarm & L.t >= run_info.attack.t_start, 1);
if isempty(hit)
    fprintf('No attack alarm. Peak cell %.3f V, %.1f degC, ends in %s\n', ...
        max(L.v_true(:)), max(L.T(:)), p.mode_names{L.mode(end)});
else
    fprintf('Alarm %g s after the attack started. Peak cell %.3f V, %.1f degC, ends in %s\n', ...
        L.t(hit) - run_info.attack.t_start, max(L.v_true(:)), max(L.T(:)), p.mode_names{L.mode(end)});
end
