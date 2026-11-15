function [rx, st] = apply_attack(meas, k, tk, atk, H, p, st)
%APPLY_ATTACK  What the BMS receives after the frame crosses the channel.
%   meas : true sensor frame (fields v, vpack, i, T, ts, ctr, valid)
%   H    : history of all true sensor frames (used by the replay attacker)
%   st   : attacker state that must persist between samples
rx = meas;
if tk < atk.t_start || tk > atk.t_end
    return
end

switch atk.type
    case 'fdi'
        % V' = V + dV, ramped in. Pack voltage comes from a separate sensor
        % the attacker has not compromised.
        frac = min(1, (tk - atk.t_start) / max(atk.param.ramp, eps));
        rx.v = meas.v + atk.param.dV * frac;

    case 'freeze'
        c = atk.param.cell;
        if isnan(st.freeze_val)
            st.freeze_val = meas.v(c);
        end
        rx.v(c) = st.freeze_val;

    case 'noise'
        % V' = V + N(0, sigma^2), then through the ADC
        rx.v = quantize(meas.v + atk.param.sigma * randn(1, numel(meas.v)), p.q_v);

    case 'replay'
        idx = k - round(atk.param.lag / p.dt);
        if idx >= 1
            rx.v     = H.v(idx, :);
            rx.vpack = H.vpack(idx);
            rx.i     = H.i(idx);
            rx.T     = H.T(idx, :);
            rx.ctr   = idx;   % old, MAC-protected counter
            rx.ts    = tk;    % timestamp rewritten to look current
        end

    case 'dos'
        if rand < atk.param.p_drop
            rx.valid = false;
        end

    case 'timestamp'
        rx.ts = atk.t_start + atk.param.rate * (tk - atk.t_start);

    case 'tamper'
        % acts inside the charger (see simulate_charging), not on the data

    case 'none'
end
end
