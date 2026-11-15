function ac = attack_code(atk)
%ATTACK_CODE  Numeric form of an attack (from attack_library or
%   random_attack) for the Simulink model.
%   type: 0 none, 1 fdi, 2 freeze, 3 noise, 4 replay, 5 tamper, 6 dos, 7 timestamp
types = {'none', 'fdi', 'freeze', 'noise', 'replay', 'tamper', 'dos', 'timestamp'};
ac.type = find(strcmp(types, atk.type)) - 1;
ac.t0 = atk.t_start;
ac.t1 = atk.t_end;
ac.a1 = 0;
ac.a2 = 0;
switch atk.type
    case 'fdi',       ac.a1 = atk.param.dV;    ac.a2 = atk.param.ramp;
    case 'freeze',    ac.a1 = atk.param.cell;
    case 'noise',     ac.a1 = atk.param.sigma;
    case 'replay',    ac.a1 = atk.param.lag;
    case 'tamper',    ac.a1 = atk.param.gain;  ac.a2 = atk.param.offset;
    case 'dos',       ac.a1 = atk.param.p_drop;
    case 'timestamp', ac.a1 = atk.param.rate;
end
end
