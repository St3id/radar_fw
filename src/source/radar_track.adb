with Ada.Numerics.Elementary_Functions;
use  Ada.Numerics.Elementary_Functions;

package body Radar_Track is

   --  Distance max (mm) pour associer une detection a une piste existante.
   Match_Radius : constant Float := 600.0;

   --  Nb de tours sans re-detection avant d'abandonner une piste.
   Max_Missing : constant := 3;

   function Dist3D (A, B : Point_3D) return Float is
     (Sqrt ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2 + (A.Z - B.Z) ** 2));

   ------------
   -- Update --
   ------------

   procedure Update (T : in out Tracker; F : Frame) is
      --  Marque les detections deja associees a une piste.
      Matched : array (1 .. Max_Detections) of Boolean := (others => False);
   begin
      --  --- Etape 1 : associer chaque piste active a la detection
      --      la plus proche (si assez proche). ---
      for I in T.Tracks'Range loop
         if T.Tracks (I).Active then
            declare
               Best_J    : Natural := 0;
               Best_Dist : Float   := Match_Radius;
            begin
               --  Chercher la detection non encore prise la plus proche.
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
                  --  Trouvee : on met a jour la piste.
                  declare
                     Old_Pos : constant Point_3D := T.Tracks (I).Pos;
                     New_Pos : constant Point_3D := F.Items (Best_J).Pos;
                  begin
                     --  Vitesse = deplacement depuis le tour precedent.
                     T.Tracks (I).Velocity :=
                       (X => New_Pos.X - Old_Pos.X,
                        Y => New_Pos.Y - Old_Pos.Y,
                        Z => New_Pos.Z - Old_Pos.Z);
                     T.Tracks (I).Pos     := New_Pos;
                     T.Tracks (I).Missing := 0;
                     Matched (Best_J)     := True;
                  end;
               else
                  --  Pas trouvee ce tour-ci : on incremente le compteur.
                  T.Tracks (I).Missing := T.Tracks (I).Missing + 1;
                  if T.Tracks (I).Missing > Max_Missing then
                     T.Tracks (I).Active := False;  --  piste abandonnee
                  end if;
               end if;
            end;
         end if;
      end loop;

      --  --- Etape 2 : creer une nouvelle piste pour chaque detection
      --      non associee. ---
      for J in 1 .. F.Count loop
         if not Matched (J) then
            --  Chercher un emplacement de piste libre.
            for I in T.Tracks'Range loop
               if not T.Tracks (I).Active then
                  T.Tracks (I) :=
                    (Id       => T.Next_Id,
                     Pos      => F.Items (J).Pos,
                     Velocity => (0.0, 0.0, 0.0),  --  inconnue au depart
                     Missing  => 0,
                     Active   => True);
                  T.Next_Id := T.Next_Id + 1;
                  exit;
               end if;
            end loop;
         end if;
      end loop;
   end Update;

end Radar_Track;