with Ada.Numerics.Elementary_Functions;

package body Radar_Track_2D is

   use Ada.Numerics.Elementary_Functions;

   Alpha : constant Float := 0.5;
   Beta  : constant Float := 0.2;

   --  Sous cet ecart la division par dt amplifie le bruit de position : deux
   --  trames collees donnaient 29 m/s pour un objet a 1 m/s (dette 14). Seuil
   --  sous la periode du module (100 ms), a recaler apres la mesure de gigue.
   Min_Velocity_Interval_Ms : constant Time_Ms := 70;

   Clock_Back_Ms    : constant Time_Ms := 2_000;
   Clock_Forward_Ms : constant Time_Ms := 60_000;

   procedure Clear_Tracks (T : in out Tracker) is
   begin
      T.Tracks       := (others => <>);
      T.Clock_Resets := T.Clock_Resets + 1;
   end Clear_Tracks;

   procedure Bound_Speed (K : in out Track; Limit : Float) is
      V : constant Float := Sqrt (K.Vx_Mm_S ** 2 + K.Vy_Mm_S ** 2);
   begin
      if V > Limit then
         K.Vx_Mm_S := K.Vx_Mm_S * Limit / V;
         K.Vy_Mm_S := K.Vy_Mm_S * Limit / V;
      end if;
   end Bound_Speed;

   --  La porte s'elargit avec le temps ecoule : une piste non revue depuis
   --  2 s peut etre loin de sa position predite.
   function Gate (K : Track; Stamp : Time_Ms; P : Parameters) return Float is
     (P.Base_Gate_Mm
      + Sqrt (K.Vx_Mm_S ** 2 + K.Vy_Mm_S ** 2)
        * Float (Stamp - K.Last_Seen) / 1_000.0);

   procedure Correct
     (T     : in out Tracker;
      Index : Positive;
      D     : Detection_2D;
      S     : Time_Ms;
      P     : Parameters)
   is
      K        : Track renames T.Tracks (Index);
      Rx       : constant Float := D.X_Mm - K.X_Mm;
      Ry       : constant Float := D.Y_Mm - K.Y_Mm;
      Interval : constant Time_Ms := S - K.Vel_Stamp;
      Velocity_Updated : constant Boolean :=
        Interval >= Min_Velocity_Interval_Ms;
   begin
      if Velocity_Updated then
         --  Deuxieme observation : pas encore de vitesse, on la tire de
         --  l'ecart brut. Ensuite, correction lente pour lisser le bruit.
         --  L'ecart se prend depuis l'ancre, pas depuis la prediction : si
         --  une trame a ete sautee (rapports a 50 ms), Rx n'en garde que la
         --  moitie, Alpha ayant deja mange le reste, alors que Dt couvre
         --  tout. Meme calcul qu'en 3D ; a 100 ms, ca redonne Rx / Dt.
         declare
            Dt   : constant Float := Float (Interval) / 1_000.0;
            Gain : constant Float := (if K.Hits = 1 then 1.0 else Beta);
            Ex   : constant Float :=
              D.X_Mm - (K.Anchor_X_Mm + K.Vx_Mm_S * Dt);
            Ey   : constant Float :=
              D.Y_Mm - (K.Anchor_Y_Mm + K.Vy_Mm_S * Dt);
         begin
            K.Vx_Mm_S := K.Vx_Mm_S + Gain * Ex / Dt;
            K.Vy_Mm_S := K.Vy_Mm_S + Gain * Ey / Dt;
         end;
         Bound_Speed (K, P.Max_Speed_Mm_S);
         K.Vel_Stamp := S;
      end if;

      K.X_Mm := K.X_Mm + Alpha * Rx;
      K.Y_Mm := K.Y_Mm + Alpha * Ry;
      if Velocity_Updated then
         K.Anchor_X_Mm := K.X_Mm;
         K.Anchor_Y_Mm := K.Y_Mm;
      end if;
      K.Last_Seen := S;
      K.Hits      := K.Hits + 1;
      K.Coasting  := False;

      if not K.Confirmed and then K.Hits >= P.Confirm_Hits then
         K.Confirmed := True;
         K.Id        := T.Next_Id;
         T.Next_Id   := T.Next_Id + 1;
      end if;
   end Correct;

   procedure Create (T : in out Tracker; D : Detection_2D; S : Time_Ms) is
   begin
      for K of T.Tracks loop
         if not K.Active then
            K := (X_Mm      => D.X_Mm,
                  Y_Mm      => D.Y_Mm,
                  Last_Seen => S,
                  Vel_Stamp => S,
                  Anchor_X_Mm => D.X_Mm,
                  Anchor_Y_Mm => D.Y_Mm,
                  Hits      => 1,
                  Active    => True,
                  others    => <>);
            return;
         end if;
      end loop;
      T.Dropped := T.Dropped + 1;
   end Create;

   procedure Update
     (T : in out Tracker;
      R : Planar_Report;
      P : Parameters := Default_Parameters)
   is
      S       : constant Time_Ms := R.Stamp;
      Dt      : Float := 0.0;
      Taken_T : array (1 .. Max_Tracks) of Boolean := (others => False);
      Taken_D : array (1 .. R.Count) of Boolean := (others => False);
   begin
      if T.Started then
         if S < T.Last_Stamp then
            if T.Last_Stamp - S <= Clock_Back_Ms then
               T.Late_Frames := T.Late_Frames + 1;
               return;
            end if;
            Clear_Tracks (T);
         elsif S - T.Last_Stamp > Clock_Forward_Ms then
            Clear_Tracks (T);
         else
            Dt := Float (S - T.Last_Stamp) / 1_000.0;
         end if;
      end if;

      for K of T.Tracks loop
         if K.Active then
            K.X_Mm := K.X_Mm + K.Vx_Mm_S * Dt;
            K.Y_Mm := K.Y_Mm + K.Vy_Mm_S * Dt;
         end if;
      end loop;

      --  La paire la plus proche d'abord, sur toutes les paires : une piste
      --  ne prend pas une detection qu'une autre, mieux placee, attend.
      loop
         declare
            Best   : Float   := Float'Last;
            Best_T : Natural := 0;
            Best_D : Natural := 0;
         begin
            for I in T.Tracks'Range loop
               if T.Tracks (I).Active and then not Taken_T (I) then
                  for J in Taken_D'Range loop
                     if not Taken_D (J) then
                        declare
                           Dist : constant Float :=
                             Sqrt ((R.Items (J).X_Mm - T.Tracks (I).X_Mm) ** 2
                                   + (R.Items (J).Y_Mm - T.Tracks (I).Y_Mm)
                                     ** 2);
                        begin
                           if Dist <= Gate (T.Tracks (I), S, P)
                             and then Dist < Best
                           then
                              Best   := Dist;
                              Best_T := I;
                              Best_D := J;
                           end if;
                        end;
                     end if;
                  end loop;
               end if;
            end loop;
            exit when Best_T = 0;
            Taken_T (Best_T) := True;
            Taken_D (Best_D) := True;
            Correct (T, Best_T, R.Items (Best_D), S, P);
         end;
      end loop;

      for I in T.Tracks'Range loop
         declare
            K : Track renames T.Tracks (I);
         begin
            if K.Active and then not Taken_T (I) then
               K.Coasting := True;
               if S - K.Last_Seen
                    > (if K.Confirmed then P.Coast_Confirmed_Ms
                       else P.Coast_Tentative_Ms)
               then
                  K := (others => <>);
               end if;
            end if;
         end;
      end loop;

      for J in Taken_D'Range loop
         if not Taken_D (J) then
            Create (T, R.Items (J), S);
         end if;
      end loop;

      T.Last_Stamp := S;
      T.Started    := True;
   end Update;

end Radar_Track_2D;
