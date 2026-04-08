%------------------------------------------------------------------------------
% File     : prop_cnf_example_001.p
% Domain   : Propositional CNF subset example
% Status   : Unsatisfiable
% Syntax   : TPTP CNF, propositional atoms only
%------------------------------------------------------------------------------
cnf(c1, axiom, (p | q)).
cnf(c2, axiom, (~p | q)).
cnf(c3, axiom, (p | ~q)).
cnf(c4, axiom, (~p | ~q)).