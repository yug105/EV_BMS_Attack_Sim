function [rx, ts, ctr, valid] = attack_step(meas, tk, nz, ur, ac, bp)
%ATTACK_STEP  Communication channel with the attacker (Simulink version of
%   apply_attack.m). nz = 4 standard-normal numbers, ur = one uniform number,
%   both from Random Number blocks so every run is repeatable.
%#codegen
persistent buf frz
if isempty(buf)
    buf = zeros(6000, 10);
    frz = NaN;
end
k = round(tk / bp.dt) + 1;
if k >= 1 && k <= 6000
    buf(k, :) = meas;
end

rx = meas;  ts = tk;  ctr = k;  valid = 1;
if ac.type == 0 || tk < ac.t0 || tk > ac.t1
    return
end

switch ac.type
    case 1  % false data injection, ramped in
        frac = min(1, (tk - ac.t0) / max(ac.a2, eps));
        rx(1:4) = meas(1:4) + ac.a1 * frac;
    case 2  % frozen cell reading
        c = round(ac.a1);
        if isnan(frz)
            frz = meas(c);
        end
        rx(c) = frz;
    case 3  % injected noise
        rx(1:4) = round((meas(1:4) + ac.a1 * nz(:)') / bp.q_v) * bp.q_v;
    case 4  % replay of old frames, old MAC-protected counter, fresh timestamp
        idx = k - round(ac.a1 / bp.dt);
        if idx >= 1
            rx  = buf(idx, :);
            ctr = idx;
        end
    case 6  % jamming / DoS
        if ur < ac.a1
            valid = 0;
        end
    case 7  % timestamp manipulation
        ts = ac.t0 + ac.a1 * (tk - ac.t0);
end
end
