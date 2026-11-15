function m = compute_metrics(Loff, Lon, atk, p)
%COMPUTE_METRICS  Detection and physical-impact numbers for one scenario.
%   Loff : run without defence (shows what the attack does)
%   Lon  : run with defence (shows what the detection layer saves)
t = Loff.t;
m.name = atk.name;

if isfinite(atk.t_start)
    pre = t >= p.t_arm & t < atk.t_start;
    win = t >= atk.t_start & t <= atk.t_end;
else
    pre = t >= p.t_arm;          % baseline: every alarm is a false alarm
    win = pre;
end

m.false_alarm = any(Loff.alarm(pre)) || any(Lon.alarm(pre));

hit = find(Loff.alarm & t >= atk.t_start, 1, 'first');
if isempty(hit) || ~isfinite(atk.t_start)
    m.t_detect = NaN;
else
    m.t_detect = t(hit);
end
m.latency  = m.t_detect - atk.t_start;
m.detected = ~isnan(m.t_detect);

% first-firing time of the basic range check (to compare with our layer)
hitR = find(Loff.conf(:, 1) & t >= atk.t_start, 1, 'first');
if isempty(hitR) || ~isfinite(atk.t_start)
    m.range_latency = NaN;
else
    m.range_latency = t(hitR) - atk.t_start;
end

fired = any(Loff.conf(win, :), 1);
if any(fired)
    m.detectors = strjoin(p.det_names(fired), ', ');
else
    m.detectors = '-';
end

m.maxV_off   = max(Loff.v_true(:));
m.maxV_on    = max(Lon.v_true(:));
m.maxT_off   = max(Loff.T(:));
m.maxT_on    = max(Lon.T(:));
m.maxSoC_off = 100 * max(Loff.soc_true(:));
m.maxSoC_on  = 100 * max(Lon.soc_true(:));
m.overV_s_off = p.dt * sum(any(Loff.v_true > p.V_cv + 0.02, 2));
m.overV_s_on  = p.dt * sum(any(Lon.v_true  > p.V_cv + 0.02, 2));
m.end_off = p.mode_names{Loff.mode(end)};
m.end_on  = p.mode_names{Lon.mode(end)};
end
