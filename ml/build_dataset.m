function [X, Y, R] = build_dataset(p, thr, nRuns, seed)
%BUILD_DATASET  Simulate nRuns charging sessions with random attacks and
%   return labelled feature rows.
%   X : features, Y : class index (0 = none, 1..7 = attack type),
%   R : run number of each row (so train/test can be split by run).
types = p.ml_classes;

% choose all attacks first: simulate_charging reseeds the generator
rng(seed);
atks = cell(nRuns, 1);
for r = 1:nRuns
    atks{r} = random_attack(types{mod(r - 1, numel(types)) + 1}, p);
end

Xc = cell(nRuns, 1);  Yc = cell(nRuns, 1);  Rc = cell(nRuns, 1);
for r = 1:nRuns
    a = atks{r};
    L = simulate_charging(p, a, struct('defence', false, 'thr', thr, 'seed', 1000 + r));
    F = extract_features(L, p);

    N   = numel(L.t);
    lab = zeros(N, 1);
    in  = L.t >= a.t_start & L.t <= a.t_end;
    lab(in) = find(strcmp(types, a.type)) - 1;

    % keep samples while charging is connected (after a trip there is
    % nothing left to classify), every p.ml_stride-th sample
    keep = L.t >= p.t_arm & L.contactor & mod((0:N-1)', p.ml_stride) == 0;
    Xc{r} = F(keep, :);
    Yc{r} = lab(keep);
    Rc{r} = r * ones(nnz(keep), 1);

    if mod(r, 8) == 0
        fprintf('  simulated %d / %d runs\n', r, nRuns);
    end
end
X = vertcat(Xc{:});
Y = vertcat(Yc{:});
R = vertcat(Rc{:});
end
