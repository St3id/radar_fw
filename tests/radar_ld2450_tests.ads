with AUnit;
with AUnit.Test_Cases;

--  Suite 4 : le module LD2450 (Radar_Ld2450), du format de trame a
--  l'emulateur.
--
--  Regle de cette suite (ARCHITECTURE.md, section 2.6) : les vecteurs de
--  test viennent du manuel du constructeur, jamais de notre propre
--  encodeur. Un encodeur et un decodeur ecrits avec la meme erreur se
--  valideraient l'un l'autre.

package Radar_Ld2450_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   --  Nom affiche pour ce groupe de tests.
   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   --  Enregistre les routines de test a executer.
   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Ld2450_Tests;
