with Ada.Numerics.Elementary_Functions;
use  Ada.Numerics.Elementary_Functions;

--  Corps de Radar_Track. Les cinq etapes d'un tour de pistage sont
--  numerotees dans Update et decrites dans la specification ; leur ordre
--  n'est pas indifferent, la prediction devant preceder l'association.

package body Radar_Track is

   --  Distance max (mm) pour associer une detection a une piste,
   --  mesuree par rapport a la position predite de la piste.
   Match_Radius : constant Float := 600.0;

   --  Gains du filtre alpha-beta : part de l'ecart mesure reinjectee
   --  dans la position (Alpha) et dans la vitesse (Beta). Des valeurs
   --  moderees lissent le jitter d'une cible etendue sans trop retarder
   --  la reaction aux vrais changements de cap.
   Alpha : constant Float := 0.5;
   Beta  : constant Float := 0.3;

   --  Tours manques toleres : une piste confirmee "roule sur son erre"
   --  pendant les evanouissements (Swerling) ; une tentative, elle,
   --  meurt vite - c'est le filtre anti-fantomes.
   Max_Missing_Confirmed : constant := 3;
   Max_Missing_Tentative : constant := 1;

   --  Deux pistes actives a moins de cette distance (mm) sont le meme
   --  objet fragmente : elles fusionnent (inferieur au rayon de
   --  regroupement pour ne pas coller deux objets vraiment distincts).
   Merge_Radius : constant Float := 400.0;

   function Dist3D (A, B : Point_3D) return Float is
     (Sqrt ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2 + (A.Z - B.Z) ** 2));

   ------------
   -- Update --
   ------------

   procedure Update (T : in out Tracker; F : Frame) is
      Matched : array (1 .. Max_Detections) of Boolean := (others => False);
   begin
      --  ----- 1. Prediction : chaque piste avance d'un tour -----
      for I in T.Tracks'Range loop
         if T.Tracks (I).Active then
            T.Tracks (I).Pos :=
              (X => T.Tracks (I).Pos.X + T.Tracks (I).Velocity.X,
               Y => T.Tracks (I).Pos.Y + T.Tracks (I).Velocity.Y,
               Z => T.Tracks (I).Pos.Z + T.Tracks (I).Velocity.Z);
         end if;
      end loop;

      --  ----- 2 et 3. Association globale puis correction alpha-beta -----
      --  On prend iterativement la paire (piste, detection) la plus
      --  proche au monde, sous le rayon d'association. Contrairement au
      --  "chaque piste prend son plus proche" (glouton, dependant de
      --  l'ordre des pistes), aucune piste ne vole la detection d'une
      --  autre mieux placee.
      declare
         Track_Done : array (T.Tracks'Range) of Boolean :=
           (others => False);
      begin
         loop
            declare
               Best_I    : Natural := 0;
               Best_J    : Natural := 0;
               Best_Dist : Float   := Match_Radius;
            begin
               for I in T.Tracks'Range loop
                  if T.Tracks (I).Active and then not Track_Done (I) then
                     for J in 1 .. F.Count loop
                        if not Matched (J) then
                           declare
                              D : constant Float :=
                                Dist3D (T.Tracks (I).Pos, F.Items (J).Pos);
                           begin
                              if D < Best_Dist then
                                 Best_Dist := D;
                                 Best_I    := I;
                                 Best_J    := J;
                              end if;
                           end;
                        end if;
                     end loop;
                  end if;
               end loop;

               exit when Best_I = 0;

               --  Correction alpha-beta : on ne saute pas sur la
               --  mesure, on s'en rapproche (Alpha) et on ajuste la
               --  vitesse d'une fraction de l'ecart (Beta).
               declare
                  Rx : constant Float :=
                    F.Items (Best_J).Pos.X - T.Tracks (Best_I).Pos.X;
                  Ry : constant Float :=
                    F.Items (Best_J).Pos.Y - T.Tracks (Best_I).Pos.Y;
                  Rz : constant Float :=
                    F.Items (Best_J).Pos.Z - T.Tracks (Best_I).Pos.Z;
               begin
                  T.Tracks (Best_I).Pos :=
                    (X => T.Tracks (Best_I).Pos.X + Alpha * Rx,
                     Y => T.Tracks (Best_I).Pos.Y + Alpha * Ry,
                     Z => T.Tracks (Best_I).Pos.Z + Alpha * Rz);
                  T.Tracks (Best_I).Velocity :=
                    (X => T.Tracks (Best_I).Velocity.X + Beta * Rx,
                     Y => T.Tracks (Best_I).Velocity.Y + Beta * Ry,
                     Z => T.Tracks (Best_I).Velocity.Z + Beta * Rz);
               end;

               T.Tracks (Best_I).Missing := 0;
               T.Tracks (Best_I).Hits    := T.Tracks (Best_I).Hits + 1;
               if T.Tracks (Best_I).Hits >= Confirm_Hits then
                  T.Tracks (Best_I).Confirmed := True;
               end if;
               Track_Done (Best_I) := True;
               Matched (Best_J)    := True;
            end;
         end loop;

         --  ----- 4a. Pistes non revues ce tour-ci -----
         for I in T.Tracks'Range loop
            if T.Tracks (I).Active and then not Track_Done (I) then
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
         end loop;
      end;

      --  ----- 4b. Une tentative pour chaque detection orpheline -----
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

      --  ----- 5. Fusion des pistes fragmentees -----
      --  Deux pistes actives a moins de Merge_Radius sont le meme objet
      --  (cible etendue scindee par la quantification, ou tentative nee
      --  d'un eclat) : la plus ancienne (plus de detections) absorbe
      --  l'autre - pas de piste "ombre" a l'affichage.
      for I in T.Tracks'Range loop
         if T.Tracks (I).Active then
            for J in I + 1 .. T.Tracks'Last loop
               if T.Tracks (J).Active
                 and then Dist3D (T.Tracks (I).Pos, T.Tracks (J).Pos)
                          < Merge_Radius
               then
                  declare
                     Keep  : constant Natural :=
                       (if T.Tracks (I).Hits >= T.Tracks (J).Hits
                        then I else J);
                     Drop  : constant Natural :=
                       (if Keep = I then J else I);
                  begin
                     T.Tracks (Keep).Confirmed :=
                       T.Tracks (Keep).Confirmed
                       or else T.Tracks (Drop).Confirmed;
                     T.Tracks (Drop).Active := False;
                  end;
               end if;

               --  Si c'est I qui vient d'etre absorbee, ne plus rien
               --  comparer contre elle.
               exit when not T.Tracks (I).Active;
            end loop;
         end if;
      end loop;
   end Update;

end Radar_Track;
