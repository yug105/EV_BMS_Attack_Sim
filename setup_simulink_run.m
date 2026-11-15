%% Prepare the Simulink model so it can be run with the green Run button
%  1. Choose an attack number and whether the defence is on (below)
%  2. Run this script
%  3. In the Simulink window press Run, and double-click "Live view" to watch
%  4. When it finishes, type  plot_simulink_run  in the Command Window
%
%  Attack numbers:
%   1 none | 2 false data injection | 3 frozen sensor | 4 noise | 5 replay
%   6 firmware tampering | 7 jamming | 8 timestamp

ATTACK  = 7;      % <- change this
DEFENCE = true;   % <- true = our detection layer can stop charging

root = fileparts(mfilename('fullpath'));
addpath(genpath(root));
p    = bms_params();
atks = attack_library(p);
thrFile = fullfile(root, 'results_simulink', 'thresholds.mat');
if ~exist(thrFile, 'file')
    error('Run main_simulink once first (it creates the thresholds).');
end
load(thrFile, 'thr');

% variables the model blocks read
bp        = sim_params(p);
ac        = attack_code(atks(ATTACK));
defence   = double(DEFENCE);
seed_meas = 100 + (1:10);
seed_atk  = 100 + (11:14);
seed_u    = 115;
run_info  = struct('attack', atks(ATTACK), 'defence', DEFENCE);

open_system(fullfile(root, 'simulink', 'EV_BMS_Simscape'));
fprintf('Ready: "%s", defence %s. Press Run in Simulink.\n', ...
    atks(ATTACK).name, string(DEFENCE));
