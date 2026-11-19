with AUnit;
with AUnit.Test_Cases;

--  Suite 9 : le contrat Radar_Target_Source, utilise a travers l'interface
--  (classwide) sur une source factice qui rejoue des frames ecrites a la main.

package Radar_Target_Source_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Target_Source_Tests;
