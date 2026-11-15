function export_diagrams(mdl, outdir)
%EXPORT_DIAGRAMS  Save the block diagrams for the report.
%   PDF = vector (sharp at any zoom, best for the report),
%   PNG = 300 dpi (for slides).
load_system(mdl);
views = { ...
    mdl,                                                 'model_1_top'; ...
    [mdl '/Battery pack and charger (Simscape)'],        'model_2_pack'; ...
    [mdl '/Battery pack and charger (Simscape)/Cell 1'], 'model_3_cell'; ...
    [mdl '/Charger control'],                            'model_4_charger'};
for j = 1:size(views, 1)
    sys = views{j, 1};
    base = fullfile(outdir, views{j, 2});
    print(['-s' sys], '-dpng', '-r300', [base '.png']);
    try
        print(['-s' sys], '-dpdf', [base '.pdf']);
    catch err
        warning('PDF export of %s failed: %s', sys, err.message);
    end
end
fprintf('Diagrams saved to %s (PDF = vector, PNG = 300 dpi)\n', outdir);
end
