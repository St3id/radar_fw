with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Sweep;        use Radar_Sweep;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;

procedure Radar_Fw is

   Src : Simulated_Source := Make;

   --  Traite un balayage complet via le CONTRAT (sans savoir que c'est simule).
   procedure Process (Radar : in out Source'Class) is
      M  : Measurement;
      OK : Boolean;
      Found : Natural := 0;
   begin
      while Radar.Has_More loop
         Radar.Next (M, OK);
         exit when not OK;

         --  On applique la detection prouvee sur chaque direction.
         if Has_Target (M.Data) then
            Found := Found + 1;
            Put_Line ("Detection a l'azimut"
                      & Integer'Image (Integer (M.Azimuth))
                      & " deg : case" & Peak_Bin (M.Data)'Image
                      & " (" & Peak_Distance (M.Data)'Image & " mm)");
         end if;
      end loop;

      Put_Line ("--- Tour termine :" & Found'Image & " direction(s) avec cible ---");
   end Process;

begin
   Process (Src);
end Radar_Fw;