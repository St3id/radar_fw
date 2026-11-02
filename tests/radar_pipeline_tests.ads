with AUnit;
with AUnit.Test_Cases;

--  Suite 2 : la chaine complete, de la geometrie au pistage.
--
--  Elle verifie des proprietes que seul l'assemblage revele : un
--  aller-retour geometrique qui doit redonner le point de depart, deux
--  echos sur un meme rayon qui doivent rester deux cibles, une piste qui
--  doit survivre a un trou de detection, et le pilotage de la source a
--  travers l'interface abstraite plutot que par le type concret.

package Radar_Pipeline_Tests is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   --  Nom affiche pour ce groupe de tests.
   overriding
   function Name (T : Test_Case) return AUnit.Message_String;

   --  Enregistre les routines de test a executer.
   overriding
   procedure Register_Tests (T : in out Test_Case);

end Radar_Pipeline_Tests;
