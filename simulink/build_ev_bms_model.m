function mdl = build_ev_bms_model(p)
%BUILD_EV_BMS_MODEL  Generate the Simulink/Simscape model EV_BMS_Simscape.slx
%
%   Battery pack + charger (Simscape, physical network)
%     4 x li_cell (custom Simscape component: OCV(SoC) + R0 + R1||C1 + thermal)
%     current_charger (custom Simscape component: controlled current source)
%   Charger (Simulink): firmware (tamper point) -> current-loop lag -> contactor
%   Sensors (Simulink): sample at 1 s, add noise, ADC rounding
%   Communication channel (Simulink): the attacker
%   BMS (Simulink): EKF + 8 detectors + CC-CV control + fail-safe
%
%   Run once (or after editing the .ssc files). main_simulink.m calls it.
if nargin < 1
    p = bms_params();
end
here = fileparts(mfilename('fullpath'));
mdl  = 'EV_BMS_Simscape';

%% 1. Simscape library from the .ssc components
old = cd(here);
cleanup = onCleanup(@() cd(old));
if bdIsLoaded('evbms_lib'), close_system('evbms_lib', 0); end
ssc_build('evbms');
load_system('evbms_lib');
cellLib    = find_component('evbms_lib', 'evbms.li_cell', 'li_cell');
chargerLib = find_component('evbms_lib', 'evbms.current_charger', 'current_charger');

%% 2. New model
if bdIsLoaded(mdl), close_system(mdl, 0); end
ws = warning('off', 'all');   % harmless "model name shadows file" notice on rebuild
new_system(mdl);
warning(ws);
set_param(mdl, 'StopTime', num2str(p.t_end), 'Solver', 'ode23t', 'MaxStep', '1', ...
    'ReturnWorkspaceOutputs', 'on');

%% 3. Battery pack + charger power stage (Simscape)
pk = [mdl '/Battery pack and charger (Simscape)'];
add_block('simulink/Ports & Subsystems/Subsystem', pk);
Simulink.SubSystem.deleteContents(pk);
set_param(pk, 'Position', [320 130 480 300]);

add_block('simulink/Sources/In1', [pk '/I_charger'], 'Position', [20 63 50 77]);
add_block('nesl_utility/Simulink-PS Converter', [pk '/To PS'], 'Position', [85 55 115 85]);
set_param([pk '/To PS'], 'Unit', 'A');
add_block(chargerLib, [pk '/Charger power stage'], 'Position', [150 35 230 105]);
add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference', [pk '/Ground'], ...
    'Position', [175 640 205 670]);
add_block('nesl_utility/Solver Configuration', [pk '/Solver Configuration'], ...
    'Position', [60 580 120 610]);
line_sig(pk, 'I_charger', 1, 'To PS', 1);
hTo = get_param([pk '/To PS'], 'PortHandles');
hCh = get_param([pk '/Charger power stage'], 'PortHandles');
add_line(pk, hTo.RConn(1), hCh.LConn(1), 'autorouting', 'smart');

% outports in order: 1 v_cell, 2 soc, 3 T_cell, 4 i
add_block('simulink/Sinks/Out1', [pk '/v_cell'], 'Position', [820 163 850 177]);
add_block('simulink/Sinks/Out1', [pk '/soc'],    'Position', [820  83 850  97]);
add_block('simulink/Sinks/Out1', [pk '/T_cell'], 'Position', [820 263 850 277]);
add_block('simulink/Sinks/Out1', [pk '/i'],      'Position', [820 343 850 357]);

% one subsystem per cell, wired in series
prevNeg = hCh.RConn(1);   % + terminal of the charger
for c = 1:p.Ns
    cs = [pk sprintf('/Cell %d', c)];
    y0 = 150 + 110 * (c - 1);
    make_cell(cs, cellLib, p, c, [310 y0 450 y0 + 80]);
    hc = get_param(cs, 'PortHandles');
    add_line(pk, prevNeg, hc.LConn(1), 'autorouting', 'smart');
    prevNeg = hc.LConn(2);
end
add_line(pk, prevNeg, hCh.RConn(2), 'autorouting', 'smart');
hG = get_param([pk '/Ground'], 'PortHandles');
hS = get_param([pk '/Solver Configuration'], 'PortHandles');
add_line(pk, hCh.RConn(2), hG.LConn(1), 'autorouting', 'smart');
add_line(pk, hCh.RConn(2), hS.RConn(1), 'autorouting', 'smart');

% gather [SoC V T I] of all cells, then pick out each quantity
add_block('simulink/Signal Routing/Mux', [pk '/All cells'], 'Inputs', '4', ...
    'Position', [520 150 526 560]);
for c = 1:p.Ns
    line_sig(pk, sprintf('Cell %d', c), 1, 'All cells', c);
end
sel = {'SoC of cells', '[1 5 9 13]', 'soc',    80; ...
       'V of cells',   '[2 6 10 14]', 'v_cell', 160; ...
       'T of cells',   '[3 7 11 15]', '',       260; ...
       'Pack current', '[4]',         'i',      340};
for j = 1:size(sel, 1)
    y = sel{j, 4};
    add_block('simulink/Signal Routing/Selector', [pk '/' sel{j, 1}], ...
        'NumberOfDimensions', '1', 'IndexOptions', 'Index vector (dialog)', ...
        'Indices', sel{j, 2}, 'InputPortWidth', '16', 'Position', [600 y - 15 660 y + 15]);
    line_sig(pk, 'All cells', 1, sel{j, 1}, 1);
end
add_block('simulink/Math Operations/Bias', [pk '/K to degC'], 'Bias', '-273.15', ...
    'Position', [710 255 770 285]);
line_sig(pk, 'SoC of cells', 1, 'soc', 1);
line_sig(pk, 'V of cells', 1, 'v_cell', 1);
line_sig(pk, 'T of cells', 1, 'K to degC', 1);
line_sig(pk, 'K to degC', 1, 'T_cell', 1);
line_sig(pk, 'Pack current', 1, 'i', 1);

set_icon(pk, [ ...
    'port_label(''input'',1,''I charger'');port_label(''output'',1,''V cells'');' ...
    'port_label(''output'',2,''SoC'');port_label(''output'',3,''T cells'');' ...
    'port_label(''output'',4,''I pack'');']);

%% 4. Charger control (Simulink): firmware -> current loop -> contactor
ch = [mdl '/Charger control'];
add_block('simulink/Ports & Subsystems/Subsystem', ch, 'Position', [140 160 260 260]);
Simulink.SubSystem.deleteContents(ch);
add_block('simulink/Sources/In1', [ch '/I_cmd'], 'Position', [20 40 50 54]);
add_block('simulink/Sources/In1', [ch '/contactor'], 'Position', [20 140 50 154]);
add_block('simulink/Sources/In1', [ch '/t'], 'Position', [20 80 50 94]);
add_block('simulink/User-Defined Functions/MATLAB Function', [ch '/Charger firmware'], ...
    'Position', [100 30 200 100]);
set_mfun([ch '/Charger firmware'], ...
    'function I_target = firmware(I_cmd, t, ac)\nI_target = charger_fw(I_cmd, t, ac);\n', {'ac'});
add_block('simulink/Continuous/Transfer Fcn', [ch '/Current loop'], ...
    'Numerator', '1', 'Denominator', sprintf('[%g 1]', p.tau_ch), 'Position', [250 45 330 85]);
add_block('simulink/Math Operations/Product', [ch '/Contactor'], 'Position', [380 50 410 120]);
add_block('simulink/Sinks/Out1', [ch '/I_charger'], 'Position', [460 78 490 92]);
line_sig(ch, 'I_cmd', 1, 'Charger firmware', 1);
line_sig(ch, 't', 1, 'Charger firmware', 2);
line_sig(ch, 'Charger firmware', 1, 'Current loop', 1);
line_sig(ch, 'Current loop', 1, 'Contactor', 1);
line_sig(ch, 'contactor', 1, 'Contactor', 2);
line_sig(ch, 'Contactor', 1, 'I_charger', 1);
set_icon(ch, [ ...
    'port_label(''input'',1,''I cmd'');port_label(''input'',2,''contactor'');' ...
    'port_label(''input'',3,''t'');port_label(''output'',1,''I'');']);

%% 5. Clock, sensors, channel, BMS
add_block('simulink/Sources/Digital Clock', [mdl '/Clock'], 'SampleTime', num2str(p.dt), ...
    'Position', [40 420 90 450]);

for nm = {'v_cell', 'i', 'T_cell'}
    add_block('simulink/Discrete/Zero-Order Hold', [mdl '/Sample ' nm{1}], ...
        'SampleTime', num2str(p.dt));
end
set_param([mdl '/Sample v_cell'], 'Position', [540 140 570 170]);
set_param([mdl '/Sample i'],      'Position', [540 290 570 320]);
set_param([mdl '/Sample T_cell'], 'Position', [540 220 570 250]);

add_block('simulink/Sources/Random Number', [mdl '/Sensor noise'], ...
    'Mean', 'zeros(1,10)', 'Variance', 'ones(1,10)', 'Seed', 'seed_meas', ...
    'SampleTime', num2str(p.dt), 'Position', [540 360 590 390]);
add_block('simulink/User-Defined Functions/MATLAB Function', [mdl '/Sensors (ADC)'], ...
    'Position', [640 150 740 380]);
set_mfun([mdl '/Sensors (ADC)'], ...
    'function meas = adc(v_cell, i, T_cell, noise, bp)\nmeas = adc_step(v_cell, i, T_cell, noise, bp);\n', {'bp'});

add_block('simulink/Sources/Random Number', [mdl '/Attacker noise'], ...
    'Mean', 'zeros(1,4)', 'Variance', 'ones(1,4)', 'Seed', 'seed_atk', ...
    'SampleTime', num2str(p.dt), 'Position', [780 410 830 440]);
add_block('simulink/Sources/Uniform Random Number', [mdl '/Jamming draw'], ...
    'Minimum', '0', 'Maximum', '1', 'Seed', 'seed_u', ...
    'SampleTime', num2str(p.dt), 'Position', [780 470 830 500]);
add_block('simulink/User-Defined Functions/MATLAB Function', [mdl '/Communication channel (attacker)'], ...
    'Position', [870 150 990 380]);
set_mfun([mdl '/Communication channel (attacker)'], ...
    ['function [rx, ts, ctr, valid] = channel(meas, t, nz, ur, ac, bp)\n' ...
     '[rx, ts, ctr, valid] = attack_step(meas, t, nz, ur, ac, bp);\n'], {'ac', 'bp'});

add_block('simulink/User-Defined Functions/MATLAB Function', [mdl '/BMS (EKF + IDS + CC-CV)'], ...
    'Position', [1050 130 1190 400]);
set_mfun([mdl '/BMS (EKF + IDS + CC-CV)'], ...
    ['function [I_cmd, contactor, bms_mode, alarm, conf, soc_ekf, soc_cc, stats] = bms(rx, ts, ctr, valid, t, bp, thr, defence)\n' ...
     '[I_cmd, contactor, bms_mode, alarm, conf, soc_ekf, soc_cc, stats] = bms_step(rx, ts, ctr, valid, t, bp, thr, defence);\n'], ...
     {'bp', 'thr', 'defence'});

add_block('simulink/Discrete/Unit Delay', [mdl '/Contactor delay'], 'InitialCondition', '1', ...
    'SampleTime', num2str(p.dt), 'Position', [1240 160 1270 190]);

% wiring
line_sig(mdl, 'Charger control', 1, 'Battery pack and charger (Simscape)', 1);
line_sig(mdl, 'Battery pack and charger (Simscape)', 1, 'Sample v_cell', 1);
line_sig(mdl, 'Battery pack and charger (Simscape)', 4, 'Sample i', 1);
line_sig(mdl, 'Battery pack and charger (Simscape)', 3, 'Sample T_cell', 1);
line_sig(mdl, 'Sample v_cell', 1, 'Sensors (ADC)', 1);
line_sig(mdl, 'Sample i', 1, 'Sensors (ADC)', 2);
line_sig(mdl, 'Sample T_cell', 1, 'Sensors (ADC)', 3);
line_sig(mdl, 'Sensor noise', 1, 'Sensors (ADC)', 4);
line_sig(mdl, 'Sensors (ADC)', 1, 'Communication channel (attacker)', 1);
line_sig(mdl, 'Clock', 1, 'Communication channel (attacker)', 2);
line_sig(mdl, 'Attacker noise', 1, 'Communication channel (attacker)', 3);
line_sig(mdl, 'Jamming draw', 1, 'Communication channel (attacker)', 4);
for j = 1:4
    line_sig(mdl, 'Communication channel (attacker)', j, 'BMS (EKF + IDS + CC-CV)', j);
end
line_sig(mdl, 'Clock', 1, 'BMS (EKF + IDS + CC-CV)', 5);
line_sig(mdl, 'BMS (EKF + IDS + CC-CV)', 1, 'Charger control', 1);
line_sig(mdl, 'BMS (EKF + IDS + CC-CV)', 2, 'Contactor delay', 1);
line_sig(mdl, 'Contactor delay', 1, 'Charger control', 2);
line_sig(mdl, 'Clock', 1, 'Charger control', 3);

%% 6. Logging (one row per second)
logs = { ...
    'Battery pack and charger (Simscape)', 1, 'log_vt'; ...
    'Battery pack and charger (Simscape)', 2, 'log_soc'; ...
    'Battery pack and charger (Simscape)', 3, 'log_T'; ...
    'Battery pack and charger (Simscape)', 4, 'log_i'; ...
    'Communication channel (attacker)', 1, 'log_rx'; ...
    'Communication channel (attacker)', 4, 'log_valid'; ...
    'BMS (EKF + IDS + CC-CV)', 1, 'log_icmd'; ...
    'BMS (EKF + IDS + CC-CV)', 2, 'log_cont'; ...
    'BMS (EKF + IDS + CC-CV)', 3, 'log_mode'; ...
    'BMS (EKF + IDS + CC-CV)', 4, 'log_alarm'; ...
    'BMS (EKF + IDS + CC-CV)', 5, 'log_conf'; ...
    'BMS (EKF + IDS + CC-CV)', 6, 'log_socekf'; ...
    'BMS (EKF + IDS + CC-CV)', 7, 'log_soccc'; ...
    'BMS (EKF + IDS + CC-CV)', 8, 'log_stats'};
lg = [mdl '/Data logging'];
add_block('simulink/Ports & Subsystems/Subsystem', lg, 'Position', [1330 120 1420 660]);
Simulink.SubSystem.deleteContents(lg);

for j = 1:size(logs, 1)
    nm = logs{j, 3};
    add_block('simulink/Sources/In1', [lg '/' nm(5:end)], 'Position', [30 23 + 50 * (j - 1) 60 37 + 50 * (j - 1)]);
    add_block('simulink/Sinks/To Workspace', [lg '/' nm], 'VariableName', nm, ...
        'SaveFormat', 'Array', 'SampleTime', num2str(p.dt), ...
        'Position', [140 15 + 50 * (j - 1) 230 45 + 50 * (j - 1)]);
    try
        set_param([lg '/' nm], 'Save2DSignal', '2-D array (concatenate along first dimension)');
    catch
    end
    line_sig(lg, nm(5:end), 1, nm, 1);
    line_sig(mdl, logs{j, 1}, logs{j, 2}, 'Data logging', j);
end

set_icon(lg, 'disp(''Data logging\n(To Workspace)'');');

% live view while the model runs: cell voltages, current, alarm
sc = [mdl '/Live view'];
add_block('simulink/Sinks/Scope', sc, 'Position', [1240 470 1290 560]);
set_param(sc, 'NumInputPorts', '3');
try, set_param(sc, 'LayoutDimensions', '[3 1]'); catch, end
line_sig(mdl, 'Sample v_cell', 1, 'Live view', 1);
line_sig(mdl, 'Sample i', 1, 'Live view', 2);
line_sig(mdl, 'BMS (EKF + IDS + CC-CV)', 4, 'Live view', 3);

% Save to a local temp folder first, then copy: writing the .slx straight
% into a cloud-synced folder (MATLAB Drive) can leave a broken file.
target = fullfile(here, [mdl '.slx']);
tmp    = fullfile(tempdir, [mdl '.slx']);
save_system(mdl, tmp);
close_system(mdl, 0);
copyfile(tmp, target, 'f');
load_system(target);   % proves the saved file opens
fprintf('Built %s (%d blocks)\n', target, numel(find_system(mdl, 'Type', 'Block')));
end

%% helpers
function line_sig(sys, src, sp, dst, dp)
add_line(sys, sprintf('%s/%d', src, sp), sprintf('%s/%d', dst, dp), 'autorouting', 'smart');
end

function set_mfun(blk, code, params)
rt = sfroot;
ch = rt.find('-isa', 'Stateflow.EMChart', 'Path', blk);
ch.Script = sprintf(code);
for j = 1:numel(params)
    d = ch.find('-isa', 'Stateflow.Data', 'Name', params{j});
    d.Scope = 'Parameter';
    d.Tunable = false;
end
end

function blk = find_component(lib, compPath, fallback)
blk = [lib '/' fallback];
cands = find_system(lib, 'SearchDepth', 1, 'Type', 'Block');
for j = 1:numel(cands)
    try
        if strcmp(get_param(cands{j}, 'ComponentPath'), compPath)
            blk = cands{j};
            return
        end
    catch
    end
end
end

function make_cell(cs, cellLib, p, c, pos)
% One cell: custom Simscape component + converters, output [SoC V T I]
add_block('simulink/Ports & Subsystems/Subsystem', cs, 'Position', pos);
Simulink.SubSystem.deleteContents(cs);
add_block('nesl_utility/Connection Port', [cs '/+'], 'Side', 'left', 'Position', [20 60 50 80]);
add_block('nesl_utility/Connection Port', [cs '/-'], 'Side', 'left', 'Position', [20 140 50 160]);
add_block(cellLib, [cs '/Cell model'], 'Position', [120 50 200 170]);
set_param([cs '/Cell model'], ...
    'Q', num2str(p.Q(c)), 'R0', num2str(p.R0(c)), 'R1', num2str(p.R1(c)), ...
    'C1', num2str(p.C1(c)), 'soc0', num2str(p.soc0(c)), ...
    'Cth', num2str(p.Cth), 'hA', num2str(p.hA), ...
    'Tamb', num2str(p.T_amb + 273.15), 'k_oc', num2str(p.k_oc));
hc = get_param([cs '/Cell model'], 'PortHandles');
add_line(cs, cport([cs '/+']), hc.LConn(1), 'autorouting', 'smart');
add_line(cs, cport([cs '/-']), hc.LConn(2), 'autorouting', 'smart');
names = {'SoC', 'V', 'T', 'I'};
units = {'1', 'V', 'K', 'A'};
add_block('simulink/Signal Routing/Mux', [cs '/Mux'], 'Inputs', '4', 'Position', [370 45 376 175]);
for m = 1:4
    pp = get_param(hc.RConn(m), 'Position');
    cv = ['PS to Simulink ' names{m}];
    add_block('nesl_utility/PS-Simulink Converter', [cs '/' cv], ...
        'Position', [pp(1) + 60, pp(2) - 10, pp(1) + 95, pp(2) + 10]);
    set_param([cs '/' cv], 'Unit', units{m});
    hv = get_param([cs '/' cv], 'PortHandles');
    add_line(cs, hc.RConn(m), hv.LConn(1), 'autorouting', 'smart');
    line_sig(cs, cv, 1, 'Mux', m);
end
add_block('simulink/Sinks/Out1', [cs '/SoC V T I'], 'Position', [420 103 450 117]);
line_sig(cs, 'Mux', 1, 'SoC V T I', 1);
set_icon(cs, sprintf(['disp(''Li-ion cell %d\\nSoC0 = %.2f'');' ...
    'port_label(''LConn'',1,''+'');port_label(''LConn'',2,''-'');'], c, p.soc0(c)));
end

function h = cport(blk)
ph = get_param(blk, 'PortHandles');
h = [ph.LConn ph.RConn];
h = h(1);
end

function set_icon(blk, display)
% plain readable icon with port labels instead of a content preview
try, set_param(blk, 'ContentPreviewEnabled', 'off'); catch, end
mk = Simulink.Mask.create(blk);
mk.Display = display;
mk.IconOpaque = 'opaque';
end
