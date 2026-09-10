with AUnit;
with AUnit.Test_Cases;

--  Suite 1 : le traitement d'un balayage isole (Radar_Sweep).
--
--  Ces tests couvrent ce que la preuve SPARK ne dit pas. La preuve
--  garantit qu'aucune cible rapportee n'est en dessous de son seuil ;
--  elle ne dit pas que les cibles attendues sont bien trouvees. C'est
--  l'objet de cette suite.

package Radar_Sweep_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   --  Nom affiche pour ce groupe de tests.
   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   --  Enregistre les routines de test a executer.
   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Sweep_Tests;
