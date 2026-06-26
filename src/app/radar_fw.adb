with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;
with Radar_Detect;       use Radar_Detect;

procedure Radar_Fw is

   Src : Simulated_Source := Make (Sweeps => 4);

   procedure Process (Radar : in out Source'Class) is
      M       : Measurement;
      OK      : Boolean;
      F       : Frame;
      Turn    : Natural := 1;
      Last_Az : Float := 0.0;

      --  Affiche le contenu d'une frame (les objets vus ce tour).
   procedure Show_Frame is
            C : constant Frame := Cluster (F);
         begin
            Put_Line ("=== Tour" & Turn'Image & " :" & C.Count'Image
                     & " cible(s) (regroupe de" & F.Count'Image & ") ===");
            for I in 1 .. C.Count loop
               declare
                  D : constant Detection_3D := C.Items (I);
            begin
               Put_Line ("   X=" & Integer'Image (Integer (D.Pos.X))
                         & " Y=" & Integer'Image (Integer (D.Pos.Y))
                         & " Z=" & Integer'Image (Integer (D.Pos.Z))
                         & "  (dist" & Integer'Image (Integer (D.Distance))
                         & " mm)");
            end;
         end loop;
      end Show_Frame;

   begin
      Reset (F);
      while Radar.Has_More loop
         Radar.Next (M, OK);
         exit when not OK;

         --  Retour de l'azimut a ~0 = nouveau tour : on cloture la frame.
         if M.Azimuth < Last_Az - 1.0 then
            Show_Frame;
            Turn := Turn + 1;
            Reset (F);
         end if;
         Last_Az := M.Azimuth;

         Add (F, M);
      end loop;

      --  Cloturer le dernier tour.
      Show_Frame;
   end Process;

begin
   Process (Src);
end Radar_Fw;