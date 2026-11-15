function a = random_attack(type, p)
%RANDOM_ATTACK  An attack of the given type with random start time,
%   duration and strength, for building the ML training dataset.
t0  = 1200 + 1400 * rand;
dur = 400 + 800 * rand;
t1  = min(t0 + dur, p.t_end);

switch type
    case 'none'
        t0 = Inf;  t1 = Inf;  param = struct();
    case 'fdi'
        param = struct('dV', -(0.05 + 0.20 * rand), 'ramp', 10 + 110 * rand);
    case 'freeze'
        param = struct('cell', randi(p.Ns));
    case 'noise'
        param = struct('sigma', 0.015 + 0.045 * rand);
    case 'replay'
        param = struct('lag', 500 + rand * (t0 - 501));
    case 'tamper'
        param = struct('gain', 1.2 + 0.6 * rand, 'offset', rand);
    case 'dos'
        param = struct('p_drop', 0.6 + 0.4 * rand);
    case 'timestamp'
        param = struct('rate', 0.3 + 0.5 * rand);
    otherwise
        error('Unknown attack type %s', type);
end
a = struct('type', type, 'name', type, 't_start', t0, 't_end', t1, 'param', param);
end
