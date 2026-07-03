with Ada.Command_Line;    use Ada.Command_Line;
with Ada.Text_IO;         use Ada.Text_IO;
with Radar_Run_Tracking;
with Radar_Run_Mapping;

--  Point d'entree : choisit le MODE D'EXPLOITATION a la demande.
--  Les deux modes partagent la meme source de donnees (Radar_Source) et
--  la meme chaine de detection prouvee ; ils ne different que par le
--  traitement des balayages :
--    track : surveillance temps reel (objets mobiles, pistage, vitesses)
--    map   : cartographie statique (nuage de points dense d'une piece)
procedure Radar_Fw is
begin
   if Argument_Count = 0 or else Argument (1) = "track" then
      Radar_Run_Tracking;
   elsif Argument (1) = "map" then
      Radar_Run_Mapping;
   else
      Put_Line ("usage : radar_fw [track|map]");
      Put_Line ("  track : surveillance temps reel (defaut)");
      Put_Line ("  map   : cartographie 3D d'une piece statique");
      Set_Exit_Status (Failure);
   end if;
end Radar_Fw;
