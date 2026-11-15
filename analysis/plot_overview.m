function fig = plot_overview(M, p, filename)
%PLOT_OVERVIEW  One summary figure for the slides: peak cell voltage and
%   temperature with and without the detection layer, and how fast each
%   attack was detected compared with the basic range check.
names = {M.name};
cats  = reordercats(categorical(names), names);

fig = figure('Name', 'Overview', 'Color', 'w', 'Position', [100 100 1300 420]);
try, fig.Theme = 'light'; catch, end
tl  = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
b = bar(ax1, cats, [[M.maxV_off]' [M.maxV_on]']);
b(1).FaceColor = [0.80 0.15 0.15];  b(2).FaceColor = [0.10 0.35 0.75];
yline(ax1, p.V_cv, '--', '4.20 V', 'HandleVisibility', 'off');
ylim(ax1, [3.8 max([M.maxV_off]) + 0.05]);
ylabel(ax1, 'Peak true cell voltage (V)');
legend(ax1, {'No defence', 'With defence'}, 'Location', 'northwest');
ax1.XTickLabelRotation = 35;  grid(ax1, 'on');

ax2 = nexttile(tl);
b = bar(ax2, cats, [[M.maxT_off]' [M.maxT_on]']);
b(1).FaceColor = [0.80 0.15 0.15];  b(2).FaceColor = [0.10 0.35 0.75];
ylabel(ax2, 'Peak cell temperature (\circC)');
legend(ax2, {'No defence', 'With defence'}, 'Location', 'northwest');
ax2.XTickLabelRotation = 35;  grid(ax2, 'on');

ax3 = nexttile(tl);
lat = [[M.latency]' [M.range_latency]'];
b = bar(ax3, cats, lat);
b(1).FaceColor = [0.10 0.35 0.75];  b(2).FaceColor = [0.6 0.6 0.6];
for j = 1:2
    ok = ~isnan(lat(:, j));
    text(ax3, b(j).XEndPoints(ok), lat(ok, j)', compose('%g s', lat(ok, j)'), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7);
end
ylabel(ax3, 'Time to detect after attack starts (s)');
legend(ax3, {'Our detection layer', 'Range check only'}, 'Location', 'northwest');
ax3.XTickLabelRotation = 35;  grid(ax3, 'on');
title(ax3, 'Missing grey bar = range check never fired', 'FontWeight', 'normal', 'FontSize', 9);

if nargin >= 3 && ~isempty(filename)
    exportgraphics(fig, filename, 'Resolution', 150);
end
end
