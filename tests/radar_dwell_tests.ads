with AUnit;
with AUnit.Test_Cases;

--  Suite 6 : le balayage adaptatif, du plan en temps aux mesures simulees.
--
--  Le plan (Radar_Dwell) est prouve ; ces tests fixent ce que la preuve n'enonce
--  pas : l'egalite des parts vue fenetre par fenetre, le retard du moteur
--  (Radar_Turret_Sim) et le gain effectif en mesures et en echos.

package Radar_Dwell_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   --  Nom affiche pour ce groupe de tests.
   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   --  Enregistre les routines de test a executer.
   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Dwell_Tests;
