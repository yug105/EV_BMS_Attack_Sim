function meas = adc_step(vt, ib, T, noise, bp)
%ADC_STEP  Sensor front end: add noise and round to the ADC resolution.
%   Output frame: [v_cell(1:4) v_pack i T_cell(1:4)]
%#codegen
x   = [vt(:)' sum(vt) ib T(:)'];
sig = [bp.sig_v * ones(1, 4), bp.sig_vpack, bp.sig_i, bp.sig_T * ones(1, 4)];
q   = [bp.q_v * ones(1, 4), bp.q_vpack, bp.q_i, bp.q_T * ones(1, 4)];
meas = round((x + sig .* noise(:)') ./ q) .* q;
end
