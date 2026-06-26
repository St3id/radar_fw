with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;
with Radar_Detect;       use Radar_Detect;
with Radar_Track;        use Radar_Track;

procedure Radar_Fw is

   Src : Simulated_Source := Make (Sweeps => 5);
   Trk : Tracker;

   procedure Process (Radar : in out Source'Class) is
      M       : Measurement;
      OK      : Boolean;
      F       : Frame;
      Turn    : Natural := 1;
      Last_Az : Float := 0.0;

      --  Fin d'un tour : on regroupe, on met a jour le tracking, on affiche.
      procedure End_Of_Turn is
         C : constant Frame := Cluster (F);
      begin
         Update (Trk, C);

         Put_Line ("===== Tour" & Turn'Image & " =====");
         for I in Trk.Tracks'Range loop
            if Trk.Tracks (I).Active then
               declare
                  Tk : constant Track := Trk.Tracks (I);
               begin
                  Put_Line ("  Cible #" & Tk.Id'Image
                            & " | pos (" & Integer'Image (Integer (Tk.Pos.X))
                            & "," & Integer'Image (Integer (Tk.Pos.Y))
                            & "," & Integer'Image (Integer (Tk.Pos.Z))
                            & " ) | vitesse ("
                            & Integer'Image (Integer (Tk.Velocity.X))
                            & "," & Integer'Image (Integer (Tk.Velocity.Y))
                            & "," & Integer'Image (Integer (Tk.Velocity.Z))
                            & " )");
               end;
            end if;
         end loop;
      end End_Of_Turn;

   begin
      Reset (F);
      while Radar.Has_More loop
         Radar.Next (M, OK);
         exit when not OK;

         if M.Azimuth < Last_Az - 1.0 then
            End_Of_Turn;
            Turn := Turn + 1;
            Reset (F);
         end if;
         Last_Az := M.Azimuth;

         Add (F, M);
      end loop;

      End_Of_Turn;  --  dernier tour
   end Process;

begin
   Process (Src);
end Radar_Fw;