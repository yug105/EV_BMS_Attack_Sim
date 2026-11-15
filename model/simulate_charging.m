function L = simulate_charging(p, atk, opts)
%SIMULATE_CHARGING  One CC-CV charging session of the 4S pack.
%
%   Signal path each sample:
%     battery -> sensors -> channel (attacker) -> BMS (EKF + detectors)
%     -> charge control -> charger (may be tampered) -> battery
%
%   opts.defence : true  = an alarm from the detection layer ramps the
%                          current down and opens the contactor
%                  false = detectors only monitor (shows attack impact)
%   opts.thr     : thresholds from calibrate_thresholds, or [] to only
%                  record detector statistics (used during calibration)
%   opts.seed    : seed for sensor noise
%
%   The basic BMS range check (over-voltage / over-temperature trip) is
%   always active, as in a real BMS.

rng(opts.seed);
haveThr = ~isempty(opts.thr);
thr     = opts.thr;

dt   = p.dt;
N    = round(p.t_end / dt) + 1;
t    = (0:N-1)' * dt;
Ns   = p.Ns;
nDet = numel(p.det_names);
a_ch = dt / p.tau_ch;

% ---- battery (true physical state)
soc = p.soc0;
v1  = zeros(1, Ns);
T   = p.T_amb * ones(1, Ns);
I_act = 0;
contactor = true;

% ---- BMS state
mode  = 1;          % 1 CC, 2 CV, 3 DONE, 4 TRIP (range check), 5 FAULT (cyber alarm)
I_cmd = 0;
I_exp = 0;          % BMS model of the charger response to I_cmd
X = zeros(2, Ns);
P = repmat(p.ekf_P0, [1 1 Ns]);
ekfReady = false;
soc_cc   = NaN;     % coulomb-counted pack SoC (uses received timestamps)
last_rx  = [];
last_ctr = 0;  max_ctr = 0;  last_ts = NaN;  miss_cnt = 0;
prev_v   = nan(1, Ns);
same_cnt = zeros(1, Ns);
pc       = zeros(1, nDet);   % persistence counters
st.freeze_val = NaN;         % attacker state

% ---- true sensor history (the replay attacker records from it)
H.v = nan(N, Ns);  H.vpack = nan(N, 1);  H.i = nan(N, 1);  H.T = nan(N, Ns);

% ---- logs
L.t = t;
L.v_true   = nan(N, Ns);  L.v_rx    = nan(N, Ns);  L.vpack_rx = nan(N, 1);
L.i_true   = zeros(N, 1); L.i_rx    = nan(N, 1);   L.i_cmd    = zeros(N, 1);
L.soc_true = nan(N, Ns);  L.soc_ekf = nan(N, Ns);  L.soc_cc   = nan(N, 1);
L.T        = nan(N, Ns);  L.mode    = zeros(N, 1); L.contactor = false(N, 1);
L.rx_valid = false(N, 1);
L.flag  = false(N, nDet);   % raw detector outputs
L.conf  = false(N, nDet);   % after persistence
L.alarm = false(N, 1);      % any cyber detector confirmed (2..nDet)
Ein = nan(N, Ns);           % EKF innovations
DV  = nan(N, Ns);           % sample-to-sample change in received voltages
S.pack  = nan(N, 1);  S.curr = nan(N, 1);  S.innov  = nan(N, 1);
S.noise = nan(N, 1);  S.freeze = zeros(N, 1);  S.fresh = nan(N, 1);
S.time  = nan(N, 1);  S.miss = zeros(N, 1);

for k = 1:N
    tk = t(k);

    %% 1) battery terminal voltage
    vt = ocv_lookup(soc, p) + v1 + p.R0 .* I_act;

    %% 2) sensors (true frame)
    meas.v     = quantize(vt + p.sig_v * randn(1, Ns), p.q_v);
    meas.vpack = quantize(sum(vt) + p.sig_vpack * randn, p.q_vpack);
    meas.i     = quantize(I_act + p.sig_i * randn, p.q_i);
    meas.T     = quantize(T + p.sig_T * randn(1, Ns), p.q_T);
    meas.ts    = tk;
    meas.ctr   = k;
    meas.valid = true;
    H.v(k, :) = meas.v;  H.vpack(k) = meas.vpack;  H.i(k) = meas.i;  H.T(k, :) = meas.T;

    %% 3) communication channel (attacker sits here)
    [rx, st] = apply_attack(meas, k, tk, atk, H, p, st);

    %% 4) BMS: state estimation and detector statistics
    if rx.valid
        miss_cnt = 0;
        if ~ekfReady
            for c = 1:Ns
                X(:, c) = [ocv_inverse(rx.v(c), p); 0];
            end
            soc_cc = mean(X(1, :));
            dts = dt;  dctr = 1;
            ekfReady = true;
        else
            dts  = rx.ts - last_ts;
            dctr = rx.ctr - last_ctr;
        end
        dt_e = min(max(dts, 0), 10 * dt);

        e = zeros(1, Ns);
        for c = 1:Ns
            [X(:, c), P(:, :, c), e(c)] = ekf_cell_step(X(:, c), P(:, :, c), ...
                rx.i, rx.v(c), dt_e, p);
        end
        soc_cc = soc_cc + rx.i * dt_e / (3600 * p.Q_nom);

        Ein(k, :) = e;
        DV(k, :)  = rx.v - prev_v;
        same = (rx.v == prev_v);
        same_cnt(same)  = same_cnt(same) + 1;
        same_cnt(~same) = 0;
        k0 = max(1, k - p.win + 1);

        S.pack(k)  = abs(rx.vpack - sum(rx.v));                     % physics: pack = sum of cells
        S.curr(k)  = abs(rx.i - I_exp);                             % measured vs commanded current
        S.innov(k) = max(abs(mean(Ein(k0:k, :), 1, 'omitnan')));    % model-based residual
        S.noise(k) = max(std(DV(k0:k, :), 0, 1, 'omitnan'));        % rolling noise level
        if abs(rx.i) > 0.1
            S.freeze(k) = max(same_cnt);                            % stuck sensor
        end
        S.fresh(k) = rx.ctr - max_ctr;                              % must be > 0
        S.time(k)  = abs(dts - dctr * dt);                          % clock vs counter

        max_ctr = max(max_ctr, rx.ctr);
        last_ctr = rx.ctr;
        last_ts  = rx.ts;
        prev_v   = rx.v;
        last_rx  = rx;
    else
        miss_cnt = miss_cnt + 1;
    end
    S.miss(k) = miss_cnt;

    %% 5) detectors
    f = false(1, nDet);
    if haveThr
        f(2) = S.pack(k)  > thr.pack;
        f(3) = S.curr(k)  > thr.curr;
        f(4) = S.innov(k) > thr.innov;
        f(5) = S.freeze(k) >= p.freeze_N;
        f(6) = S.noise(k) > thr.noise;
        f(7) = rx.valid && S.fresh(k) <= 0;
        f(8) = S.time(k)  > p.dt_tol;
        f(9) = miss_cnt   >= p.link_timeout;
        f    = f & (tk >= p.t_arm);
    end

    % BMS works on the last frame it received (hold-last-value)
    v_use = last_rx.v;
    T_use = last_rx.T;
    f(1) = any(v_use > p.V_max_trip) || any(v_use < p.V_min_trip) || any(T_use > p.T_max_trip);

    pc(f)  = pc(f) + 1;
    pc(~f) = 0;
    conf  = pc >= p.persist;
    alarm = any(conf(2:end));

    %% 6) charge control and response
    if mode <= 3 && conf(1)
        mode = 4;                       % basic over-voltage / over-temp trip
    end
    if opts.defence && alarm && mode <= 3
        mode = 5;                       % cyber alarm -> fail-safe stop
    end

    switch mode
        case 1  % CC
            I_cmd = p.I_cc;
            if max(v_use) >= p.V_cv
                mode = 2;
            end
        case 2  % CV
            I_cmd = min(max(I_cmd + p.Ki_cv * (p.V_cv - max(v_use)) * dt, 0), p.I_cc);
            if I_cmd < p.I_term
                mode  = 3;
                I_cmd = 0;
            end
        case 3  % DONE
            I_cmd = 0;
        case 4  % TRIP
            I_cmd = 0;
            contactor = false;
        case 5  % FAULT: ramp down, then open contactor
            I_cmd = max(I_cmd - p.ramp_rate * dt, 0);
            if I_cmd <= 0
                contactor = false;
            end
    end

    %% log this sample
    L.v_true(k, :)   = vt;
    L.i_true(k)      = I_act;
    L.i_cmd(k)       = I_cmd;
    L.soc_true(k, :) = soc;
    L.soc_ekf(k, :)  = X(1, :);
    L.soc_cc(k)      = soc_cc;
    L.T(k, :)        = T;
    L.mode(k)        = mode;
    L.contactor(k)   = contactor;
    L.rx_valid(k)    = rx.valid;
    if rx.valid
        L.v_rx(k, :)  = rx.v;
        L.vpack_rx(k) = rx.vpack;
        L.i_rx(k)     = rx.i;
    end
    L.flag(k, :) = f;
    L.conf(k, :) = conf;
    L.alarm(k)   = alarm;

    %% 7) charger (possibly tampered) and the BMS model of it
    tampered = strcmp(atk.type, 'tamper') && tk >= atk.t_start && tk <= atk.t_end;
    if tampered
        I_target = atk.param.gain * I_cmd + atk.param.offset;
    else
        I_target = I_cmd;
    end
    if contactor
        I_act = I_act + a_ch * (I_target - I_act);
        I_exp = I_exp + a_ch * (I_cmd - I_exp);
    else
        I_act = 0;
        I_exp = 0;
    end

    %% 8) battery dynamics over one step
    ad   = exp(-dt ./ (p.R1 .* p.C1));
    soc  = soc + I_act * dt ./ (3600 * p.Q);
    v1   = v1 .* ad + p.R1 .* (1 - ad) * I_act;
    heat = I_act^2 * p.R0 + v1.^2 ./ p.R1 + p.k_oc * max(soc - 1, 0) * abs(I_act);
    T    = T + dt / p.Cth * (heat - p.hA * (T - p.T_amb));
end

L.stat = S;
L.Ein  = Ein;
end
