with Ada.Command_Line;    use Ada.Command_Line;
with Ada.Text_IO;         use Ada.Text_IO;
with Radar_Run_Tracking;
with Radar_Run_Mapping;
with Radar_Run_Live;
with Radar_Run_Scan;
with Radar_Run_Sar;

--  Point d'entree : choisit le mode D'exploitation a la demande.
--  Les modes a profils utilisent Radar_Source ; les modules qui livrent
--  deja des cibles ont un contrat separe. La chaine aval de pistage reste
--  partagee :
--    track : rejeu enregistre (objets mobiles, pistage, vitesses)
--    map   : cartographie statique (nuage de points dense d'une piece)
--    live  : surveillance temps reel dans le navigateur (serveur HTTP
--            Ada + carte de clutter : decor statique et cibles mobiles)
--    sar   : synthese d'ouverture simulee (finesse et tolerances d'une
--            tete A121 decentree), resultats en texte
procedure Radar_Fw is
begin
   if Argument_Count = 0 or else Argument (1) = "track" then
      Radar_Run_Tracking;
   elsif Argument (1) = "map" then
      Radar_Run_Mapping;
   elsif Argument (1) = "live" then
      Radar_Run_Live;
   elsif Argument (1) = "scan" then
      Radar_Run_Scan
        (Dwell => Argument_Count >= 2 and then Argument (2) = "--dwell");
   elsif Argument (1) = "sar" then
      Radar_Run_Sar;
   else
      Put_Line ("usage : radar_fw [track|map|live|scan [--dwell]|sar]");
      Put_Line ("  track : rejeu du pistage (defaut)");
      Put_Line ("  map   : cartographie 3D d'une piece statique (fichier)");
      Put_Line ("  live  : surveillance temps reel (http://localhost:8080)");
      Put_Line ("  scan  : carte rapide puis detaillee (http://localhost:"
                & "8080)");
      Put_Line ("  scan --dwell : idem, en ralentissant sur les cibles");
      Put_Line ("  sar   : synthese d'ouverture simulee (texte)");
      Set_Exit_Status (Failure);
   end if;
end Radar_Fw;
