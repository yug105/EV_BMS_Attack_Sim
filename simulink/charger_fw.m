function y = charger_fw(u, tk, ac)
%CHARGER_FW  Charger firmware: passes the BMS current command through,
%   unless it has been tampered with (attack type 5).
%#codegen
if ac.type == 5 && tk >= ac.t0 && tk <= ac.t1
    y = ac.a1 * u + ac.a2;
else
    y = u;
end
end
