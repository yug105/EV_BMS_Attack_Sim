function p = bms_params()
%BMS_PARAMS  All parameters of the simulation in one place.
%   4S1P Li-ion (NMC 18650) pack, CC-CV charging at 1C, BMS with an
%   EKF state-of-charge estimator and a cyber-attack detection layer.

%% Time
p.dt    = 1;        % sample time (s)
p.t_end = 5000;     % length of one charging session (s)

%% Battery pack: 4 cells in series, 1st-order Thevenin (R0 + R1||C1) model
p.Ns     = 4;
p.Q_nom  = 2.6;     % cell capacity (Ah)
p.R0_nom = 0.030;   % ohmic resistance (ohm)
p.R1_nom = 0.015;   % polarisation resistance (ohm)
p.C1_nom = 2000;    % polarisation capacitance (F) -> tau = 30 s

% Small cell-to-cell spread, as in a real pack. Fixed (not random) so every
% run is comparable. Cell 2 starts fullest, so it is the first to reach 4.2 V.
p.Q    = p.Q_nom  * [1.00 0.98 1.01 0.99];
p.R0   = p.R0_nom * [1.00 1.05 0.97 1.02];
p.R1   = p.R1_nom * [1.00 1.04 0.98 1.01];
p.C1   = p.C1_nom * [1.00 0.97 1.02 1.00];
p.soc0 = [0.20 0.24 0.21 0.20];

% Open-circuit voltage vs SoC (typical NMC curve)
p.ocv_soc = [0    0.05 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 0.95 1.00];
p.ocv_v   = [3.00 3.35 3.45 3.55 3.62 3.68 3.74 3.82 3.90 3.98 4.07 4.12 4.20];
p.ocv_over_slope = 2.0;   % V per unit SoC above 100 % (overcharge region)

%% Lumped thermal model per cell
p.Cth   = 40;      % heat capacity (J/K)
p.hA    = 0.05;    % heat transfer to ambient (W/K)
p.T_amb = 25;      % ambient (degC)
p.k_oc  = 5;       % extra heat from overcharge side reactions (W per A per unit SoC above 1)

%% Charger and BMS charge control (CC-CV)
p.I_cc   = 2.6;    % constant-current setpoint, 1C (A)
p.V_cv   = 4.20;   % constant-voltage limit per cell (V)
p.I_term = 0.13;   % stop charging below C/20 in CV (A)
p.Ki_cv  = 5;      % CV integral gain (A per V per s)
p.tau_ch = 2;      % charger current-loop time constant (s)

%% Basic BMS protection (range limits, always on)
p.V_max_trip = 4.25;
p.V_min_trip = 2.80;
p.T_max_trip = 50;

%% Sensors: noise std and resolution
p.sig_v     = 2e-3;  p.q_v     = 1e-3;   % cell voltage (V)
p.sig_vpack = 5e-3;  p.q_vpack = 5e-3;   % separate pack voltage sensor (V)
p.sig_i     = 0.01;  p.q_i     = 0.005;  % current (A)
p.sig_T     = 0.1;   p.q_T     = 0.1;    % temperature (degC)

%% EKF (state = [SoC; V1] per cell, uses nominal parameters)
p.ekf_Q  = diag([1e-8 1e-6]);
p.ekf_R  = (5e-3)^2;
p.ekf_P0 = diag([1e-4 1e-4]);

%% Detection layer
p.det_names = {'Range check (basic BMS)', 'Pack vs sum of cells', ...
               'Current vs command', 'EKF voltage residual', 'Frozen value', ...
               'Noise level', 'Freshness counter', 'Timestamp check', 'Link timeout'};
p.persist     = [1 3 3 5 1 5 1 2 1];  % consecutive samples before a flag is confirmed
p.win         = 20;    % window for moving residual / noise statistics (samples)
p.freeze_N    = 20;    % identical samples in a row while current flows = frozen
p.link_timeout = 3;    % missed packets in a row = link lost
p.dt_tol      = 0.2;   % allowed timestamp error (s)
p.t_arm       = 30;    % detectors armed after start-up transient (s)
p.margin      = 1.5;   % threshold = margin x worst value seen in attack-free runs
p.thr_floor   = struct('pack', 0.02, 'curr', 0.03, 'innov', 0.008, 'noise', 0.008);

%% Response when the detection layer raises an alarm
p.ramp_rate = 1.0;     % ramp charging current down at this rate (A/s), then open contactor

p.mode_names = {'CC', 'CV', 'DONE', 'TRIP', 'FAULT'};

%% Machine-learning stage
p.ml_classes  = {'none', 'fdi', 'freeze', 'noise', 'replay', 'tamper', 'dos', 'timestamp'};
p.ml_features = {'pack_resid', 'curr_resid', 'ekf_resid', 'same_count', 'noise_std', ...
                 'counter_step', 'time_err', 'missed_pkts', 'v_max', 'i_meas', ...
                 'dv_trend', 'soc_gap'};
p.ml_stride   = 5;     % keep every 5th sample to keep the dataset small
end
