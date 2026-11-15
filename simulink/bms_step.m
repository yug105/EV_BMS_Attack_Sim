function [I_cmd_o, cont_o, mode_o, alarm_o, conf_o, socekf_o, soccc_o, stats_o] = ...
    bms_step(rx, ts, ctr, valid, tk, bp, thr, defence)
%BMS_STEP  One 1-second step of the BMS: EKF state estimation, the eight
%   cyber detectors, CC-CV charge control and the fail-safe response.
%   Same logic as the BMS part of simulate_charging.m, written so that a
%   Simulink MATLAB Function block can compile it.
%
%   rx    : received frame [v_cell(1:4) v_pack i T_cell(1:4)]
%   ts    : received timestamp, ctr : received message counter
%   valid : 0 if the frame never arrived
%   stats : [pack curr innov noise freeze fresh time miss]
%#codegen
WIN = 20;   % detector window (samples), same as p.win
NS  = 4;    % cells

persistent mode I_cmd I_exp X P ekfReady soc_cc last_rx last_ctr max_ctr ...
    last_ts miss_cnt prev_v same_cnt pc Ebuf Dbuf bi contactor
if isempty(mode)
    mode = 1;  I_cmd = 0;  I_exp = 0;
    X = zeros(2, NS);
    P = repmat(bp.ekf_P0, [1 1 NS]);
    ekfReady = false;  soc_cc = NaN;
    last_rx = zeros(1, 10);
    last_ctr = 0;  max_ctr = 0;  last_ts = NaN;  miss_cnt = 0;
    prev_v = nan(1, NS);  same_cnt = zeros(1, NS);  pc = zeros(1, 9);
    Ebuf = nan(WIN, NS);  Dbuf = nan(WIN, NS);  bi = 0;
    contactor = true;
end

dt   = bp.dt;
a_ch = 1 - exp(-dt / bp.tau_ch);   % exact discrete model of the charger lag
bi   = mod(bi, WIN) + 1;
stats = nan(1, 8);
stats(5) = 0;

%% receive, estimate, detector statistics
if valid > 0.5
    miss_cnt = 0;
    v = rx(1:4);  vpack = rx(5);  i_m = rx(6);
    if ~ekfReady
        for c = 1:NS
            X(1, c) = ocv_inverse(v(c), bp);
            X(2, c) = 0;
        end
        soc_cc = mean(X(1, :));
        dts = dt;  dctr = 1;
        ekfReady = true;
    else
        dts  = ts - last_ts;
        dctr = ctr - last_ctr;
    end
    dt_e = min(max(dts, 0), 10 * dt);

    e = zeros(1, NS);
    for c = 1:NS
        [xc, Pc, ec] = ekf_cell_step(X(:, c), P(:, :, c), i_m, v(c), dt_e, bp);
        X(:, c) = xc;  P(:, :, c) = Pc;  e(c) = ec;
    end
    soc_cc = soc_cc + i_m * dt_e / (3600 * bp.Q_nom);

    same = (v == prev_v);
    same_cnt(same)  = same_cnt(same) + 1;
    same_cnt(~same) = 0;
    Ebuf(bi, :) = e;
    Dbuf(bi, :) = v - prev_v;

    stats(1) = abs(vpack - sum(v));
    stats(2) = abs(i_m - I_exp);
    stats(3) = max(abs(col_mean(Ebuf)));
    stats(4) = max(col_std(Dbuf));
    if abs(i_m) > 0.1
        stats(5) = max(same_cnt);
    end
    stats(6) = ctr - max_ctr;
    stats(7) = abs(dts - dctr * dt);

    max_ctr  = max(max_ctr, ctr);
    last_ctr = ctr;
    last_ts  = ts;
    prev_v   = v;
    last_rx  = rx;
else
    miss_cnt = miss_cnt + 1;
    Ebuf(bi, :) = NaN;
    Dbuf(bi, :) = NaN;
end
stats(8) = miss_cnt;

%% detectors
f = false(1, 9);
if tk >= bp.t_arm
    f(2) = stats(1) > thr.pack;
    f(3) = stats(2) > thr.curr;
    f(4) = stats(3) > thr.innov;
    f(5) = stats(5) >= bp.freeze_N;
    f(6) = stats(4) > thr.noise;
    f(7) = valid > 0.5 && stats(6) <= 0;
    f(8) = stats(7) > bp.dt_tol;
    f(9) = miss_cnt >= bp.link_timeout;
end
v_use = last_rx(1:4);
T_use = last_rx(7:10);
f(1) = any(v_use > bp.V_max_trip) || any(v_use < bp.V_min_trip) || any(T_use > bp.T_max_trip);

for d = 1:9
    if f(d)
        pc(d) = pc(d) + 1;
    else
        pc(d) = 0;
    end
end
conf  = pc >= bp.persist;
alarm = any(conf(2:9));

%% charge control and response
if mode <= 3 && conf(1)
    mode = 4;
end
if defence > 0.5 && alarm && mode <= 3
    mode = 5;
end
switch mode
    case 1  % CC
        I_cmd = bp.I_cc;
        if max(v_use) >= bp.V_cv
            mode = 2;
        end
    case 2  % CV
        I_cmd = min(max(I_cmd + bp.Ki_cv * (bp.V_cv - max(v_use)) * dt, 0), bp.I_cc);
        if I_cmd < bp.I_term
            mode = 3;
            I_cmd = 0;
        end
    case 3  % DONE
        I_cmd = 0;
    case 4  % TRIP
        I_cmd = 0;
        contactor = false;
    otherwise  % 5 FAULT: ramp down, then open contactor
        I_cmd = max(I_cmd - bp.ramp_rate * dt, 0);
        if I_cmd <= 0
            contactor = false;
        end
end

I_cmd_o  = I_cmd;
cont_o   = double(contactor);
mode_o   = mode;
alarm_o  = double(alarm);
conf_o   = double(conf);
socekf_o = X(1, :);
soccc_o  = soc_cc;
stats_o  = stats;

% BMS model of the charger response, for the current-vs-command detector
if contactor
    I_exp = I_exp + a_ch * (I_cmd - I_exp);
else
    I_exp = 0;
end
end

function m = col_mean(A)
m = nan(1, size(A, 2));
for c = 1:size(A, 2)
    x = A(:, c);
    ok = ~isnan(x);
    n = sum(ok);
    if n > 0
        x(~ok) = 0;
        m(c) = sum(x) / n;
    end
end
end

function s = col_std(A)
s = nan(1, size(A, 2));
for c = 1:size(A, 2)
    x = A(:, c);
    ok = ~isnan(x);
    n = sum(ok);
    if n > 1
        x(~ok) = 0;
        mu = sum(x) / n;
        r = (x - mu) .* ok;
        s(c) = sqrt(sum(r .^ 2) / (n - 1));
    elseif n == 1
        s(c) = 0;
    end
end
end
