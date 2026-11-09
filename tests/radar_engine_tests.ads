with AUnit;
with AUnit.Test_Cases;

--  Suite 7 : le moteur de la console, sans GTK, sur une fausse source.

package Radar_Engine_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Engine_Tests;
