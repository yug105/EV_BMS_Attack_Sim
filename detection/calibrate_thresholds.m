function thr = calibrate_thresholds(p, seeds)
%CALIBRATE_THRESHOLDS  Detector thresholds from attack-free charging runs.
%   Each threshold = p.margin x the worst value seen with no attack
%   (with a small floor). This is how thresholds are set on real data:
%   from normal operation only, without needing attack examples.
atk  = attack_library(p);
none = atk(1);
names = {'pack', 'curr', 'innov', 'noise'};
worst = zeros(1, numel(names));

for s = seeds
    L = simulate_charging(p, none, struct('defence', false, 'thr', [], 'seed', s));
    armed = L.t >= p.t_arm;
    for j = 1:numel(names)
        x = L.stat.(names{j});
        worst(j) = max(worst(j), max(x(armed)));
    end
end

for j = 1:numel(names)
    thr.(names{j}) = max(p.margin * worst(j), p.thr_floor.(names{j}));
end

fprintf('Thresholds from %d attack-free runs:\n', numel(seeds));
fprintf('  pack vs sum of cells : %.1f mV\n', 1000 * thr.pack);
fprintf('  current vs command   : %.0f mA\n', 1000 * thr.curr);
fprintf('  EKF residual         : %.1f mV\n', 1000 * thr.innov);
fprintf('  noise level          : %.1f mV\n', 1000 * thr.noise);
end
