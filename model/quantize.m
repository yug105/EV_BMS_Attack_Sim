function y = quantize(x, q)
%QUANTIZE  Round a sensor reading to the sensor resolution q.
y = round(x / q) * q;
end
