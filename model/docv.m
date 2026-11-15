function d = docv(soc, p)
%DOCV  Slope dOCV/dSoC, needed for the EKF measurement Jacobian.
h = 1e-3;
d = (ocv_lookup(soc + h, p) - ocv_lookup(soc - h, p)) / (2 * h);
end
