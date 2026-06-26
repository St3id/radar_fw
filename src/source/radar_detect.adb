with Radar_Sweep;  use Radar_Sweep;
with Ada.Numerics.Elementary_Functions;   use  Ada.Numerics.Elementary_Functions;

package body Radar_Detect is

   -----------
   -- Reset --
   -----------

   procedure Reset (F : in out Frame) is
   begin
      F.Count := 0;
   end Reset;

   ---------
   -- Add --
   ---------

   procedure Add (F : in out Frame; M : Measurement) is
   begin
      --  On n'ajoute que s'il y a une cible et qu'il reste de la place.
      if Has_Target (M.Data) and then F.Count < Max_Detections then
         declare
            --  Distance physique du pic detecte.
            Dist : constant Float := Float (Peak_Distance (M.Data));

            --  Position 3D : on combine la direction visee (azimut,
            --  elevation de la mesure) avec la distance du pic.
            P : constant Point_3D :=
              To_Point (Dist, M.Azimuth, M.Elevation);
         begin
            F.Count := F.Count + 1;
            F.Items (F.Count) := (Pos => P, Distance => Dist);
         end;
      end if;
   end Add;

   -------------
   -- Cluster --
   -------------

   function Cluster (F : Frame) return Frame is
      Result : Frame;
      Used   : array (1 .. Max_Detections) of Boolean := (others => False);

      --  Distance 3D entre deux points.
      function Dist3D (A, B : Point_3D) return Float is
        (Sqrt ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2 + (A.Z - B.Z) ** 2));

   begin
      Reset (Result);

      --  Pour chaque detection pas encore regroupee...
      for I in 1 .. F.Count loop
         if not Used (I) then

            declare
               --  On demarre un groupe avec la detection I.
               Sum_X : Float := F.Items (I).Pos.X;
               Sum_Y : Float := F.Items (I).Pos.Y;
               Sum_Z : Float := F.Items (I).Pos.Z;
               Sum_D : Float := F.Items (I).Distance;
               N     : Natural := 1;
            begin
               Used (I) := True;

               --  On cherche toutes les detections proches de I.
               for J in I + 1 .. F.Count loop
                  if not Used (J)
                    and then Dist3D (F.Items (I).Pos, F.Items (J).Pos)
                             < Cluster_Radius
                  then
                     Sum_X := Sum_X + F.Items (J).Pos.X;
                     Sum_Y := Sum_Y + F.Items (J).Pos.Y;
                     Sum_Z := Sum_Z + F.Items (J).Pos.Z;
                     Sum_D := Sum_D + F.Items (J).Distance;
                     N := N + 1;
                     Used (J) := True;
                  end if;
               end loop;

               --  La cible regroupee = moyenne des positions du groupe.
               if Result.Count < Max_Detections then
                  Result.Count := Result.Count + 1;
                  Result.Items (Result.Count) :=
                    (Pos => (X => Sum_X / Float (N),
                             Y => Sum_Y / Float (N),
                             Z => Sum_Z / Float (N)),
                     Distance => Sum_D / Float (N));
               end if;
            end;
         end if;
      end loop;

      return Result;
   end Cluster;

end Radar_Detect;