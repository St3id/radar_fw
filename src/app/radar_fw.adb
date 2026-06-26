with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Sweep;        use Radar_Sweep;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;

procedure Radar_Fw is

   --  3 tours pour ne pas noyer l'affichage (la grille 3D est dense).
   Src : Simulated_Source := Make (Sweeps => 3);

   procedure Process (Radar : in out Source'Class) is
      M  : Measurement;
      OK : Boolean;
   begin
      while Radar.Has_More loop
         Radar.Next (M, OK);
         exit when not OK;

         if Has_Target (M.Data) then
            Put_Line ("azimut" & Integer'Image (Integer (M.Azimuth))
                      & " | elevation" & Integer'Image (Integer (M.Elevation))
                      & " : case" & Peak_Bin (M.Data)'Image
                      & " (" & Peak_Distance (M.Data)'Image & " mm)");
         end if;
      end loop;
      Put_Line ("--- termine ---");
   end Process;

begin
   Process (Src);
end Radar_Fw;