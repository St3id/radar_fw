with AUnit;
with AUnit.Test_Cases;

--  Suite 3 : la synthese d'ouverture en arc (Radar_Sar, Radar_Sar_Sim).
--
--  Ces tests fixent en chiffres ce que la porte G0 du guide materiel
--  demandait de savoir avant d'acheter : la finesse obtenue par une tete
--  A121 decentree, et ce que la mecanique doit tenir pour l'obtenir. Les
--  seuils viennent des mesures du mode sar, avec une marge.

package Radar_Sar_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   --  Nom affiche pour ce groupe de tests.
   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   --  Enregistre les routines de test a executer.
   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Sar_Tests;
