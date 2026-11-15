%% Simulink / Simscape version of the EV BMS attack study
%  Same experiment as main.m, but the battery pack and charger are a
%  Simscape physical network and the sensors, attacker channel, BMS and
%  charger control are Simulink blocks.
%
%   1. Build EV_BMS_Simscape.slx (custom Simscape cell + charger blocks)
%   2. Calibrate detector thresholds from attack-free Simulink runs
%   3. Run every attack without and with defence, plot and tabulate
%   4. Compare with the MATLAB-script results (results/summary.csv)
%
%  Needs Simulink and Simscape. Open the model to see the block diagram:
%     open_system('simulink/EV_BMS_Simscape')

clear; clc; close all;
root = fileparts(mfilename('fullpath'));
addpath(genpath(root));
outdir = fullfile(root, 'results_simulink');
if ~exist(outdir, 'dir'), mkdir(outdir); end

p   = bms_params();
mdl = build_ev_bms_model(p);

%% 1. Thresholds from normal operation only
fprintf('\n== Simulink step 1: calibrating detectors on attack-free runs ==\n');
atks  = attack_library(p);
names = {'pack', 'curr', 'innov', 'noise'};
worst = zeros(1, 4);
for s = [101 102 103]
    L = simulate_charging_simulink(p, atks(1), struct('defence', false, 'thr', [], 'seed', s), mdl);
    armed = L.t >= p.t_arm;
    for j = 1:4
        worst(j) = max(worst(j), max(L.stat.(names{j})(armed)));
    end
end
for j = 1:4
    thr.(names{j}) = max(p.margin * worst(j), p.thr_floor.(names{j}));
end
fprintf('  pack %.1f mV | current %.0f mA | EKF %.1f mV | noise %.1f mV\n', ...
    1000 * thr.pack, 1000 * thr.curr, 1000 * thr.innov, 1000 * thr.noise);
save(fullfile(outdir, 'thresholds.mat'), 'thr');   % reused by demo.m

%% 2. Attack scenarios
fprintf('\n== Simulink step 2: attack scenarios ==\n');
nA = numel(atks);
for a = 1:nA
    fprintf('  %-34s ', atks(a).name);
    Loff = simulate_charging_simulink(p, atks(a), struct('defence', false, 'thr', thr, 'seed', 1), mdl);
    Lon  = simulate_charging_simulink(p, atks(a), struct('defence', true,  'thr', thr, 'seed', 1), mdl);
    M(a) = compute_metrics(Loff, Lon, atks(a), p); %#ok<SAGROW>
    a_plot = atks(a);
    a_plot.name = [atks(a).name ' (Simulink/Simscape)'];
    plot_scenario(Loff, Lon, a_plot, p, fullfile(outdir, sprintf('%02d_%s.png', a - 1, atks(a).type)));
    if M(a).detected
        fprintf('detected after %g s\n', M(a).latency);
    elseif isfinite(atks(a).t_start)
        fprintf('NOT detected\n');
    elseif M(a).false_alarm
        fprintf('FALSE ALARM in baseline\n');
    else
        fprintf('no false alarms\n');
    end
end

summary = table(string({M.name})', [M.detected]', [M.latency]', [M.range_latency]', ...
    round([M.maxV_off]', 3), round([M.maxV_on]', 3), round([M.maxT_off]', 1), round([M.maxT_on]', 1), ...
    string({M.end_off})', string({M.end_on})', [M.false_alarm]', ...
    'VariableNames', {'Attack', 'Detected', 'Latency_s', 'RangeCheck_latency_s', ...
    'MaxV_noDef', 'MaxV_def', 'MaxT_noDef', 'MaxT_def', 'End_noDef', 'End_def', 'FalseAlarm'});
writetable(summary, fullfile(outdir, 'summary_simulink.csv'));
plot_overview(M, p, fullfile(outdir, 'overview_simulink.png'));

%% 3. Compare with the MATLAB-script model
scriptCsv = fullfile(root, 'results', 'summary.csv');
fprintf('\n');
if exist(scriptCsv, 'file')
    S = readtable(scriptCsv);
    cmp = table(summary.Attack, S.Latency_s, summary.Latency_s, S.MaxV_noDef, summary.MaxV_noDef, ...
        S.MaxT_noDef, summary.MaxT_noDef, ...
        'VariableNames', {'Attack', 'Latency_script', 'Latency_simulink', ...
        'MaxV_script', 'MaxV_simulink', 'MaxT_script', 'MaxT_simulink'});
    disp(cmp);
    writetable(cmp, fullfile(outdir, 'script_vs_simulink.csv'));
else
    disp(summary);
end
export_diagrams(mdl, outdir);
fprintf('\nDone. Figures are in %s\n', outdir);
