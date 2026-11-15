function soc = ocv_inverse(v, p)
%OCV_INVERSE  SoC from a rest voltage (used once to initialise the EKF).
v = min(max(v, p.ocv_v(1)), p.ocv_v(end));
soc = interp1(p.ocv_v, p.ocv_soc, v);
end
