function L = out_to_L(out, p)
%OUT_TO_L  Convert the Simulink logs into the same struct as simulate_charging.m.
vt = getlog(out, 'log_vt');
N  = size(vt, 1);
L.t = (0:N-1)' * p.dt;
L.v_true   = vt;
L.soc_true = getlog(out, 'log_soc');
L.T        = getlog(out, 'log_T');
L.i_true   = getlog(out, 'log_i');

rx    = getlog(out, 'log_rx');
valid = getlog(out, 'log_valid') > 0.5;
L.rx_valid = valid;
L.v_rx     = rx(:, 1:4);   L.v_rx(~valid, :) = NaN;
L.vpack_rx = rx(:, 5);     L.vpack_rx(~valid) = NaN;
L.i_rx     = rx(:, 6);     L.i_rx(~valid) = NaN;

L.i_cmd     = getlog(out, 'log_icmd');
L.contactor = getlog(out, 'log_cont') > 0.5;
L.mode      = getlog(out, 'log_mode');
L.alarm     = getlog(out, 'log_alarm') > 0.5;
L.conf      = getlog(out, 'log_conf') > 0.5;
L.flag      = L.conf;
L.soc_ekf   = getlog(out, 'log_socekf');
L.soc_cc    = getlog(out, 'log_soccc');

st = getlog(out, 'log_stats');
L.stat = struct('pack', st(:, 1), 'curr', st(:, 2), 'innov', st(:, 3), 'noise', st(:, 4), ...
    'freeze', st(:, 5), 'fresh', st(:, 6), 'time', st(:, 7), 'miss', st(:, 8));
end

function x = getlog(out, name)
% To Workspace may store 1xK signals as 1xKxN; return N x K
x = out.get(name);
if ndims(x) == 3
    x = permute(x, [3 2 1]);
    x = reshape(x, size(x, 1), []);
end
end
