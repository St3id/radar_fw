with AUnit;
with AUnit.Test_Cases;

--  Suite 5 : le flux du LD2450, de l'octet abime a la cible plausible.
--
--  Parseur (Radar_Ld2450_Stream) et plausibilite (Radar_Ld2450_Plausibility).
--  Les flux sont abimes par Radar_Ld2450_Faults a partir des trames du manuel ;
--  l'emulateur sert de second temoin, jamais de seul vecteur.

package Radar_Ld2450_Stream_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   --  Nom affiche pour ce groupe de tests.
   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   --  Enregistre les routines de test a executer.
   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Ld2450_Stream_Tests;
