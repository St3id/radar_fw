with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Sweep;        use Radar_Sweep;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;

procedure Radar_Fw is

   --  On cree une source SIMULEE...
   Src : Simulated_Source := Make;

   --  ... mais le traitement ci-dessous parle au CONTRAT (Source'Class),
   --  sans savoir si c'est de la simu ou un vrai capteur.
   procedure Process (Radar : in out Source'Class) is
      M  : Measurement;
      OK : Boolean;
      Detections : Natural := 0;
   begin
      --  Tant que la source a des mesures, on les traite.
      while Radar.Has_More loop
         Radar.Next (M, OK);
         exit when not OK;

         --  On applique la detection (ton pipeline prouve) sur la mesure.
         if Has_Target (M.Data) then
            Detections := Detections + 1;
            Put_Line ("Detection a l'azimut"
                      & Integer'Image (Integer (M.Azimuth))
                      & " deg : cible case"
                      & Peak_Bin (M.Data)'Image
                      & " a" & Peak_Distance (M.Data)'Image & " mm");
         end if;
      end loop;

      Put_Line ("--- Balayage termine :" & Detections'Image
                & " direction(s) avec cible ---");
   end Process;

begin
   Process (Src);
end Radar_Fw;