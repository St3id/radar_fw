with Ada.Command_Line;    use Ada.Command_Line;
with Ada.Text_IO;         use Ada.Text_IO;
with Radar_Run_Tracking;
with Radar_Run_Mapping;
with Radar_Run_Live;

--  Point d'entree : choisit le MODE D'EXPLOITATION a la demande.
--  Tous les modes partagent la meme source de donnees (Radar_Source) et
--  la meme chaine de detection prouvee ; ils ne different que par le
--  traitement des balayages :
--    track : rejeu enregistre (objets mobiles, pistage, vitesses)
--    map   : cartographie statique (nuage de points dense d'une piece)
--    live  : surveillance TEMPS REEL dans le navigateur (serveur HTTP
--            Ada + carte de clutter : decor statique et cibles mobiles)
procedure Radar_Fw is
begin
   if Argument_Count = 0 or else Argument (1) = "track" then
      Radar_Run_Tracking;
   elsif Argument (1) = "map" then
      Radar_Run_Mapping;
   elsif Argument (1) = "live" then
      Radar_Run_Live;
   else
      Put_Line ("usage : radar_fw [track|map|live]");
      Put_Line ("  track : rejeu du pistage (defaut)");
      Put_Line ("  map   : cartographie 3D d'une piece statique");
      Put_Line ("  live  : surveillance temps reel (http://localhost:8080)");
      Set_Exit_Status (Failure);
   end if;
end Radar_Fw;
