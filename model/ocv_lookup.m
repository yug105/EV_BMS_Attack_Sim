function v = ocv_lookup(soc, p)
%OCV_LOOKUP  Open-circuit voltage for a vector of SoC values.
%   Above 100 % SoC the voltage keeps rising steeply (overcharge region).
s = min(max(soc, 0), 1);
v = interp1(p.ocv_soc, p.ocv_v, s);
over = soc > 1;
v(over) = p.ocv_v(end) + p.ocv_over_slope * (soc(over) - 1);
under = soc < 0;
v(under) = p.ocv_v(1) + 2 * soc(under);
end
