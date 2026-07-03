with Ada.Numerics.Elementary_Functions;
use  Ada.Numerics.Elementary_Functions;

package body Radar_Track is

   --  Distance max (mm) pour associer une detection a une piste,
   --  mesuree par rapport a la position PREDITE de la piste.
   Match_Radius : constant Float := 600.0;

   --  Gains du filtre alpha-beta : part de l'ecart mesure reinjectee
   --  dans la position (Alpha) et dans la vitesse (Beta). Des valeurs
   --  moderees lissent le jitter d'une cible etendue sans trop retarder
   --  la reaction aux vrais changements de cap.
   Alpha : constant Float := 0.5;
   Beta  : constant Float := 0.3;

   --  Tours manques toleres : une piste CONFIRMEE "roule sur son erre"
   --  pendant les evanouissements (Swerling) ; une TENTATIVE, elle,
   --  meurt vite - c'est le filtre anti-fantomes.
   Max_Missing_Confirmed : constant := 3;
   Max_Missing_Tentative : constant := 1;

   function Dist3D (A, B : Point_3D) return Float is
     (Sqrt ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2 + (A.Z - B.Z) ** 2));

   ------------
   -- Update --
   ------------

   procedure Update (T : in out Tracker; F : Frame) is
      Matched : array (1 .. Max_Detections) of Boolean := (others => False);
   begin
      --  --- 1. PREDICTION : chaque piste avance d'un tour. ---
      for I in T.Tracks'Range loop
         if T.Tracks (I).Active then
            T.Tracks (I).Pos :=
              (X => T.Tracks (I).Pos.X + T.Tracks (I).Velocity.X,
               Y => T.Tracks (I).Pos.Y + T.Tracks (I).Velocity.Y,
               Z => T.Tracks (I).Pos.Z + T.Tracks (I).Velocity.Z);
         end if;
      end loop;

      --  --- 2 et 3. ASSOCIATION puis CORRECTION alpha-beta. ---
      for I in T.Tracks'Range loop
         if T.Tracks (I).Active then
            declare
               Best_J    : Natural := 0;
               Best_Dist : Float   := Match_Radius;
            begin
               --  Chercher la detection non encore prise la plus proche
               --  de la position predite.
               for J in 1 .. F.Count loop
                  if not Matched (J) then
                     declare
                        D : constant Float :=
                          Dist3D (T.Tracks (I).Pos, F.Items (J).Pos);
                     begin
                        if D < Best_Dist then
                           Best_Dist := D;
                           Best_J    := J;
                        end if;
                     end;
                  end if;
               end loop;

               if Best_J /= 0 then
                  --  Correction alpha-beta : on ne saute pas sur la
                  --  mesure, on s'en rapproche (Alpha) et on ajuste la
                  --  vitesse d'une fraction de l'ecart (Beta).
                  declare
                     Rx : constant Float :=
                       F.Items (Best_J).Pos.X - T.Tracks (I).Pos.X;
                     Ry : constant Float :=
                       F.Items (Best_J).Pos.Y - T.Tracks (I).Pos.Y;
                     Rz : constant Float :=
                       F.Items (Best_J).Pos.Z - T.Tracks (I).Pos.Z;
                  begin
                     T.Tracks (I).Pos :=
                       (X => T.Tracks (I).Pos.X + Alpha * Rx,
                        Y => T.Tracks (I).Pos.Y + Alpha * Ry,
                        Z => T.Tracks (I).Pos.Z + Alpha * Rz);
                     T.Tracks (I).Velocity :=
                       (X => T.Tracks (I).Velocity.X + Beta * Rx,
                        Y => T.Tracks (I).Velocity.Y + Beta * Ry,
                        Z => T.Tracks (I).Velocity.Z + Beta * Rz);
                  end;

                  T.Tracks (I).Missing := 0;
                  T.Tracks (I).Hits    := T.Tracks (I).Hits + 1;
                  if T.Tracks (I).Hits >= Confirm_Hits then
                     T.Tracks (I).Confirmed := True;
                  end if;
                  Matched (Best_J) := True;
               else
                  --  --- 4a. Pas revue ce tour-ci. ---
                  T.Tracks (I).Missing := T.Tracks (I).Missing + 1;
                  if (T.Tracks (I).Confirmed
                      and then T.Tracks (I).Missing > Max_Missing_Confirmed)
                    or else
                     (not T.Tracks (I).Confirmed
                      and then T.Tracks (I).Missing > Max_Missing_Tentative)
                  then
                     T.Tracks (I).Active := False;
                  end if;
               end if;
            end;
         end if;
      end loop;

      --  --- 4b. Une TENTATIVE pour chaque detection orpheline. ---
      for J in 1 .. F.Count loop
         if not Matched (J) then
            for I in T.Tracks'Range loop
               if not T.Tracks (I).Active then
                  T.Tracks (I) :=
                    (Id        => T.Next_Id,
                     Pos       => F.Items (J).Pos,
                     Velocity  => (0.0, 0.0, 0.0),  --  inconnue au depart
                     Missing   => 0,
                     Hits      => 1,
                     Confirmed => False,
                     Active    => True);
                  T.Next_Id := T.Next_Id + 1;
                  exit;
               end if;
            end loop;
         end if;
      end loop;
   end Update;

end Radar_Track;
