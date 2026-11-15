function F = extract_features(L, p)
%EXTRACT_FEATURES  One feature row per sample, using only data the BMS
%   has at that moment (trailing windows, no future samples).
%   Column order matches p.ml_features.
S    = L.stat;
vmax = max(L.v_rx, [], 2);
dv   = [NaN; diff(vmax)];

F = [S.pack, S.curr, S.innov, S.freeze, S.noise, min(S.fresh, 1), S.time, S.miss, ...
     vmax, L.i_rx, movmean(dv, [p.win - 1, 0], 'omitnan'), ...
     L.soc_cc - mean(L.soc_ekf, 2)];

% missing packets: carry the last known value forward
F = fillmissing(F, 'previous');
F(isnan(F)) = 0;
end
