with AUnit;
with AUnit.Test_Cases;

package Radar_Sweep_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   --  Nom affiche pour ce groupe de tests.
   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   --  Enregistre les routines de test a executer.
   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Sweep_Tests;