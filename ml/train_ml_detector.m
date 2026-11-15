function res = train_ml_detector(X, Y, R, p, outdir)
%TRAIN_ML_DETECTOR  Boosted decision trees (AdaBoostM2) that classify each
%   sample as normal or one of the seven attacks. This is the MATLAB
%   counterpart of the XGBoost model in Kumar & Mikkili.
%   Needs the Statistics and Machine Learning Toolbox.
res = [];
if isempty(which('fitcensemble'))
    warning(['Statistics and Machine Learning Toolbox not found: ' ...
             'skipping the ML stage. The rule-based results are still valid.']);
    return
end

classes = p.ml_classes;
Yc = categorical(Y, 0:numel(classes) - 1, classes);

% split by whole runs, never by samples of the same run. Runs cycle
% through all 8 classes, so every 4th cycle is a test cycle.
nTypes = numel(classes);
isTest = mod(floor((R - 1) / nTypes), 4) == 3;
tr = ~isTest;  te = isTest;
fprintf('ML: %d training rows (%d runs), %d test rows (%d runs)\n', ...
    nnz(tr), numel(unique(R(tr))), nnz(te), numel(unique(R(te))));

tmpl = templateTree('MaxNumSplits', 40);
mdl  = fitcensemble(X(tr, :), Yc(tr), 'Method', 'AdaBoostM2', ...
    'NumLearningCycles', 150, 'Learners', tmpl, 'LearnRate', 0.3, ...
    'PredictorNames', p.ml_features);

Yp  = predict(mdl, X(te, :));
acc = mean(Yp == Yc(te));
[cm, order] = confusionmat(Yc(te), Yp);
recall    = diag(cm) ./ max(sum(cm, 2), 1);
precision = diag(cm) ./ max(sum(cm, 1)', 1);

fprintf('ML test accuracy: %.1f %%\n', 100 * acc);
disp(table(cellstr(order(:)), 100 * precision, 100 * recall, ...
    'VariableNames', {'Class', 'Precision_pct', 'Recall_pct'}));

fig = figure('Name', 'ML confusion matrix', 'Color', 'w', 'Position', [120 120 760 620]);
try, fig.Theme = 'light'; catch, end
confusionchart(fig, Yc(te), Yp, 'RowSummary', 'row-normalized', ...
    'Title', sprintf('Boosted trees on unseen runs (accuracy %.1f %%)', 100 * acc));
exportgraphics(fig, fullfile(outdir, 'ml_confusion.png'), 'Resolution', 150);

imp  = predictorImportance(mdl);
fig2 = figure('Name', 'ML feature importance', 'Color', 'w', 'Position', [140 140 760 420]);
try, fig2.Theme = 'light'; catch, end
fn = reordercats(categorical(p.ml_features), p.ml_features);
bar(fn, imp, 'FaceColor', [0.10 0.35 0.75]);
ylabel('Importance');  title('Which features the model relies on');
grid on;
set(gca, 'TickLabelInterpreter', 'none');
exportgraphics(fig2, fullfile(outdir, 'ml_feature_importance.png'), 'Resolution', 150);

res.model     = mdl;
res.accuracy  = acc;
res.confusion = cm;
res.precision = precision;
res.recall    = recall;
save(fullfile(outdir, 'ml_model.mat'), 'mdl', 'acc', 'cm', 'classes');
end
