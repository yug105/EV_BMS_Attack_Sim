%% LIVE DEMO - EV BMS cyber-attack detection (Simulink / Simscape)
%  Run one section at a time: click inside a section, then press
%  "Run Section" (or Ctrl+Enter / Cmd+Enter). Each section takes < 30 s.
%
%  Before the demo, run main_simulink once (about 2 min) so the model,
%  thresholds and all result figures already exist.

%% 1. Setup
clear; clc; close all;
root = fileparts(mfilename('fullpath'));
addpath(genpath(root));
p    = bms_params();
atks = attack_library(p);
mdl  = 'EV_BMS_Simscape';
load(fullfile(root, 'results_simulink', 'thresholds.mat'), 'thr');
disp('Attacks available:');
disp(table((1:numel(atks))', string({atks.type})', string({atks.name})', ...
    'VariableNames', {'No', 'type', 'name'}));

%% 2. Show the model (battery, charger, sensors, attacker, BMS)
open_system(fullfile(root, 'simulink', mdl));

%% 3. Normal charging, no attack
L = simulate_charging_simulink(p, atks(1), struct('defence', true, 'thr', thr, 'seed', 1), mdl);
plot_scenario(L, L, atks(1), p, '');
fprintf('Normal charge: ends in %s, peak cell voltage %.3f V, no alarms: %d\n', ...
    p.mode_names{L.mode(end)}, max(L.v_true(:)), ~any(L.alarm));

%% 4. Pick ONE attack and show: what it does, and how we stop it
%  Change the number to show another attack (2 = FDI, 6 = tampering, 7 = jamming ...)
k = 7;
Loff = simulate_charging_simulink(p, atks(k), struct('defence', false, 'thr', thr, 'seed', 1), mdl);
Lon  = simulate_charging_simulink(p, atks(k), struct('defence', true,  'thr', thr, 'seed', 1), mdl);
plot_scenario(Loff, Lon, atks(k), p, '');
m = compute_metrics(Loff, Lon, atks(k), p);
fprintf(['\n%s\n  without defence: peak cell %.2f V, %.1f degC\n' ...
         '  with defence   : detected after %g s by [%s]\n' ...
         '                   peak cell %.2f V, %.1f degC\n'], ...
    m.name, m.maxV_off, m.maxT_off, m.latency, m.detectors, m.maxV_on, m.maxT_on);

%% 5. Summary of all 7 attacks (from the main_simulink run)
figure('Color', 'w', 'Name', 'Summary');
imshow(fullfile(root, 'results_simulink', 'overview_simulink.png'));
disp(readtable(fullfile(root, 'results_simulink', 'script_vs_simulink.csv')));
