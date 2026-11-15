function atk = attack_library(p)
%ATTACK_LIBRARY  The demonstration scenarios, one per attack from the slides.
%   Each attack acts on the data path between the sensors and the BMS,
%   except firmware tampering, which acts inside the charger.
%   Normal CC phase ends around t = 2450 s, so most attacks start before
%   that, when wrong data can push the pack into overcharge.

atk = struct('type', {}, 'name', {}, 't_start', {}, 't_end', {}, 'param', {});

atk(end+1) = mk('none', 'No attack (baseline)', Inf, Inf, struct());

% 1. FDI: every cell voltage reported 0.15 V low, ramped in over 60 s so
%    there is no sudden jump. Values stay inside the normal range.
atk(end+1) = mk('fdi', 'False data injection', 1800, p.t_end, ...
    struct('dV', -0.15, 'ramp', 60));

% 2a. Spoofing: cell 2 (the fullest cell) frozen at its current reading.
atk(end+1) = mk('freeze', 'Sensor spoofing: frozen value', 1800, p.t_end, ...
    struct('cell', 2));

% 2b. Spoofing / EMI: random noise added to all cell voltages.
atk(end+1) = mk('noise', 'Sensor spoofing: injected noise', 1800, 2600, ...
    struct('sigma', 0.04));

% 3. Replay: frames recorded at t = 1000-1600 s are re-sent at 2300-2900 s.
%    The attacker rewrites timestamps but cannot forge the MAC-protected
%    message counter, so old counters arrive.
atk(end+1) = mk('replay', 'Man-in-the-middle replay', 2300, 2900, ...
    struct('lag', 1300));

% 4. Firmware tampering: charger delivers 1.5x the commanded current plus
%    0.8 A, and keeps pushing 0.8 A even after the BMS commands stop.
atk(end+1) = mk('tamper', 'Charger firmware tampering', 1500, p.t_end, ...
    struct('gain', 1.5, 'offset', 0.8));

% 5. Jamming / DoS: all packets lost (channel shutdown).
atk(end+1) = mk('dos', 'Jamming / denial of service', 2000, 3200, ...
    struct('p_drop', 1.0));

% 6. Timestamp attack: the reported clock runs at half speed.
atk(end+1) = mk('timestamp', 'Timestamp manipulation', 2000, p.t_end, ...
    struct('rate', 0.5));
end

function a = mk(type, name, t0, t1, param)
a = struct('type', type, 'name', name, 't_start', t0, 't_end', t1, 'param', param);
end
