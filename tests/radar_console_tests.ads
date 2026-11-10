with AUnit;
with AUnit.Test_Cases;

--  Suite 8 : ce qui sert la console sans GTK. Provenance des captures, pistage
--  2D, reglages, geometrie d'ecran, cartographie et veille pas a pas.

package Radar_Console_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Console_Tests;
