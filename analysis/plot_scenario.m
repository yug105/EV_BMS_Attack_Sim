function fig = plot_scenario(Loff, Lon, atk, p, filename)
%PLOT_SCENARIO  Five-panel figure for one attack: voltage, current,
%   temperature, SoC and which detectors fired. Red = no defence,
%   blue = with defence, shaded band = attack active.
tm   = Loff.t / 60;
red  = [0.80 0.15 0.15];
blue = [0.10 0.35 0.75];
grey = [0.25 0.25 0.25];

fig = figure('Name', atk.name, 'Color', 'w', 'Position', [80 60 950 1050]);
try, fig.Theme = 'light'; catch, end
tl  = tiledlayout(fig, 5, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, atk.name, 'FontWeight', 'bold');
ax = gobjects(5, 1);

% 1. voltage
ax(1) = nexttile(tl);
plot(ax(1), tm, max(Loff.v_true, [], 2), 'Color', red, 'LineWidth', 1.4); hold(ax(1), 'on');
plot(ax(1), tm, max(Lon.v_true, [], 2), 'Color', blue, 'LineWidth', 1.4);
plot(ax(1), tm, max(Loff.v_rx, [], 2), ':', 'Color', grey, 'LineWidth', 1.1);
yline(ax(1), p.V_cv, '--', '4.20 V limit', 'HandleVisibility', 'off');
yline(ax(1), p.V_max_trip, '-.', 'trip', 'HandleVisibility', 'off');
ylabel(ax(1), 'Max cell voltage (V)');
legend(ax(1), {'True, no defence', 'True, with defence', 'What the BMS sees, no defence'}, ...
    'Location', 'southeast');

% 2. current
ax(2) = nexttile(tl);
plot(ax(2), tm, Loff.i_true, 'Color', red, 'LineWidth', 1.4); hold(ax(2), 'on');
plot(ax(2), tm, Lon.i_true, 'Color', blue, 'LineWidth', 1.4);
plot(ax(2), tm, Loff.i_cmd, ':', 'Color', grey, 'LineWidth', 1.1);
ylabel(ax(2), 'Current (A)');
legend(ax(2), {'Actual, no defence', 'Actual, with defence', 'BMS command, no defence'}, ...
    'Location', 'northeast');

% 3. temperature
ax(3) = nexttile(tl);
plot(ax(3), tm, max(Loff.T, [], 2), 'Color', red, 'LineWidth', 1.4); hold(ax(3), 'on');
plot(ax(3), tm, max(Lon.T, [], 2), 'Color', blue, 'LineWidth', 1.4);
ylabel(ax(3), 'Max cell temp (\circC)');

% 4. SoC
ax(4) = nexttile(tl);
plot(ax(4), tm, 100 * max(Loff.soc_true, [], 2), 'Color', red, 'LineWidth', 1.4); hold(ax(4), 'on');
plot(ax(4), tm, 100 * max(Lon.soc_true, [], 2), 'Color', blue, 'LineWidth', 1.4);
plot(ax(4), tm, 100 * Loff.soc_cc, ':', 'Color', grey, 'LineWidth', 1.1);
yline(ax(4), 100, '--', '100 %', 'HandleVisibility', 'off');
ylabel(ax(4), 'SoC (%)');
legend(ax(4), {'True max cell, no defence', 'True max cell, with defence', ...
    'BMS estimate, no defence'}, 'Location', 'southeast');

% 5. detector timeline (monitor-only run, so it shows everything that fires)
ax(5) = nexttile(tl);
hold(ax(5), 'on');
nDet = numel(p.det_names);
for d = 1:nDet
    idx = Loff.conf(:, d);
    if any(idx)
        plot(ax(5), tm(idx), d * ones(nnz(idx), 1), '.', 'Color', red, 'MarkerSize', 7);
    end
end
yticks(ax(5), 1:nDet);
yticklabels(ax(5), p.det_names);
ylim(ax(5), [0.5 nDet + 0.5]);
set(ax(5), 'YDir', 'reverse', 'FontSize', 8);
xlabel(ax(5), 'Time (min)');
title(ax(5), 'Detectors that fired (monitoring only)', 'FontWeight', 'normal', 'FontSize', 9);

linkaxes(ax, 'x');
xlim(ax(1), [0 tm(end)]);
for j = 1:5
    grid(ax(j), 'on');
end

% shade attack window and mark detection time
if isfinite(atk.t_start)
    x0 = atk.t_start / 60;
    x1 = min(atk.t_end, p.t_end) / 60;
    for j = 1:5
        shade(ax(j), x0, x1);
    end
    hit = find(Lon.alarm & Lon.t >= atk.t_start, 1, 'first');
    if ~isempty(hit)
        for j = 1:4
            xline(ax(j), Lon.t(hit) / 60, '--', 'detected', 'Color', blue, 'HandleVisibility', 'off');
        end
    end
end

if nargin >= 5 && ~isempty(filename)
    exportgraphics(fig, filename, 'Resolution', 150);
end
end

function shade(ax, x0, x1)
yl = ylim(ax);
h = patch(ax, [x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], [1.0 0.85 0.55], ...
    'EdgeColor', 'none', 'FaceAlpha', 0.30, 'HandleVisibility', 'off');
uistack(h, 'bottom');
ylim(ax, yl);
end
