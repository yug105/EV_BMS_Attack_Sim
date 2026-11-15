function [x, P, e] = ekf_cell_step(x, P, i_in, v_meas, dt_e, p)
%EKF_CELL_STEP  One predict + update step of the per-cell EKF.
%   x = [SoC; V1], i_in = measured current (A, + = charging),
%   v_meas = measured terminal voltage, dt_e = time since last sample.
%   e is the innovation (measured minus predicted voltage). Under normal
%   operation it is small noise; tampered data makes it grow.
tau = p.R1_nom * p.C1_nom;
ad  = exp(-dt_e / tau);
A = [1 0; 0 ad];
B = [dt_e / (3600 * p.Q_nom); p.R1_nom * (1 - ad)];

% predict
x = A * x + B * i_in;
P = A * P * A' + p.ekf_Q * (dt_e / p.dt);

% update
H    = [docv(x(1), p), 1];
vhat = ocv_lookup(x(1), p) + x(2) + p.R0_nom * i_in;
e    = v_meas - vhat;
S    = H * P * H' + p.ekf_R;
K    = P * H' / S;
x    = x + K * e;
P    = (eye(2) - K * H) * P;
end
