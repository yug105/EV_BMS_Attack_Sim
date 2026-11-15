%% Cybersecurity and Anomaly Detection in EV Battery Management Systems
%  Minor project, Dept. of Electrical Engineering, MNIT Jaipur
%
%  Runs the full simulation study:
%   1. Calibrate detector thresholds from attack-free charging runs
%   2. For each attack: simulate without defence (impact) and with
%      defence (detection + fail-safe stop), plot and tabulate
%   3. (optional) Train a boosted-tree classifier on randomised attacks
%
%  Requires MATLAB R2020a or newer. Step 3 also needs the Statistics and
%  Machine Learning Toolbox. Output goes to the results folder.

clear; clc; close all;
root = fileparts(mfilename('fullpath'));
addpath(genpath(root));
outdir = fullfile(root, 'results');
if ~exist(outdir, 'dir'), mkdir(outdir); end

RUN_ML  = true;    % set false to skip step 3
ML_RUNS = 96;      % 12 runs per class; more runs = better model, slower

p = bms_params();

%% 1. Thresholds from normal operation only
fprintf('== Step 1: calibrating detectors on attack-free runs ==\n');
thr = calibrate_thresholds(p, [101 102 103]);

%% 2. Attack scenarios
fprintf('\n== Step 2: attack scenarios ==\n');
atks = attack_library(p);
nA = numel(atks);
runs = struct('off', cell(nA, 1), 'on', cell(nA, 1));
for a = 1:nA
    fprintf('  %-34s ', atks(a).name);
    Loff = simulate_charging(p, atks(a), struct('defence', false, 'thr', thr, 'seed', 1));
    Lon  = simulate_charging(p, atks(a), struct('defence', true,  'thr', thr, 'seed', 1));
    M(a) = compute_metrics(Loff, Lon, atks(a), p); %#ok<SAGROW>
    runs(a).off = Loff;
    runs(a).on  = Lon;
    plot_scenario(Loff, Lon, atks(a), p, ...
        fullfile(outdir, sprintf('%02d_%s.png', a - 1, atks(a).type)));
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

summary = table( ...
    string({M.name})', ...
    [M.detected]', [M.latency]', [M.range_latency]', string({M.detectors})', ...
    round([M.maxV_off]', 3), round([M.maxV_on]', 3), ...
    round([M.maxT_off]', 1), round([M.maxT_on]', 1), ...
    round([M.maxSoC_off]', 1), round([M.maxSoC_on]', 1), ...
    [M.overV_s_off]', [M.overV_s_on]', ...
    string({M.end_off})', string({M.end_on})', [M.false_alarm]', ...
    'VariableNames', {'Attack', 'Detected', 'Latency_s', 'RangeCheck_latency_s', ...
    'Detectors', 'MaxV_noDef', 'MaxV_def', 'MaxT_noDef', 'MaxT_def', ...
    'MaxSoC_noDef', 'MaxSoC_def', 'OverV_s_noDef', 'OverV_s_def', ...
    'End_noDef', 'End_def', 'FalseAlarm'});
fprintf('\n');
disp(summary(:, {'Attack', 'Detected', 'Latency_s', 'RangeCheck_latency_s', ...
    'MaxV_noDef', 'MaxV_def', 'MaxT_noDef', 'MaxT_def', 'End_noDef', 'End_def'}));
writetable(summary, fullfile(outdir, 'summary.csv'));
plot_overview(M, p, fullfile(outdir, 'overview.png'));
save(fullfile(outdir, 'scenarios.mat'), 'runs', 'M', 'thr', 'p', 'atks', '-v7.3');

%% 3. Machine-learning detector
if RUN_ML
    fprintf('\n== Step 3: ML classifier on %d randomised runs ==\n', ML_RUNS);
    [X, Y, R] = build_dataset(p, thr, ML_RUNS, 7);
    ml = train_ml_detector(X, Y, R, p, outdir);
end

fprintf('\nDone. Figures and summary.csv are in %s\n', outdir);
