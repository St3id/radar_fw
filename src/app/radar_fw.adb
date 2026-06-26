with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Sweep;        use Radar_Sweep;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;

procedure Radar_Fw is

   --  Source simulee qui fera 5 tours (le monde avance entre chaque tour).
   Src : Simulated_Source := Make (Sweeps => 5);

   procedure Process (Radar : in out Source'Class) is
      M  : Measurement;
      OK : Boolean;
      Turn : Natural := 1;
      Last_Az : Float := -1.0;
   begin
      while Radar.Has_More loop
         Radar.Next (M, OK);
         exit when not OK;

         --  Detecter le retour a l'azimut 0 = nouveau tour.
         if M.Azimuth < Last_Az then
            Turn := Turn + 1;
         end if;
         Last_Az := M.Azimuth;

         if Has_Target (M.Data) then
            Put_Line ("Tour" & Turn'Image
                      & " | azimut" & Integer'Image (Integer (M.Azimuth))
                      & " deg : case" & Peak_Bin (M.Data)'Image
                      & " (" & Peak_Distance (M.Data)'Image & " mm)");
         end if;
      end loop;
   end Process;

begin
   Process (Src);
end Radar_Fw;