with Ada.Numerics;                           use Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
use  Ada.Numerics.Long_Elementary_Functions;

--  Corps de Radar_Sar. La retroprojection est la methode d'imagerie SAR
--  la plus directe : pas de FFT, pas d'approximation de champ lointain,
--  seulement une somme par pixel. Elle coute Npixels x Nbalayages
--  operations, ce qui reste rapide sur un PC pour une rangee de piece.

package body Radar_Sar
  with SPARK_Mode => Off
is

   --  Ramene un angle dans ]-Pi, Pi].
   function Wrap (A : Long_Float) return Long_Float is
     (Arctan (Sin (A), Cos (A)));

   --  Echantillon complexe du balayage N a la distance D, interpole
   --  lineairement entre les deux cases voisines ; nul hors de la plage.
   --  L'interpolation suffit parce que la phase est plate le long de
   --  l'enveloppe (phase enhancement) : seule l'enveloppe, lisse, varie
   --  d'une case a l'autre.
   function Sample_At
     (Cfg  : Sensor_Config;
      Data : Scan_Data;
      N    : Positive;
      D    : Long_Float) return Complex
   is
      F : constant Long_Float := (D - Cfg.Range_Start) / Cfg.Range_Step;
   begin
      if F < 0.0 or else F >= Long_Float (Data'Length (2) - 1) then
         return (0.0, 0.0);
      end if;
      declare
         K    : constant Natural := Natural (Long_Float'Floor (F));
         Frac : constant Long_Float := F - Long_Float (K);
         C    : constant Positive := Data'First (2) + K;
      begin
         return Data (N, C) * (1.0 - Frac) + Data (N, C + 1) * Frac;
      end;
   end Sample_At;

   -----------------
   -- Backproject --
   -----------------

   procedure Backproject
     (Cfg    : Sensor_Config;
      Angles : Angle_Array;
      Data   : Scan_Data;
      Grid   : Polar_Grid;
      Beta   : Long_Float;
      Result : out Image)
   is
      --  Phase aller-retour par metre : 2 x (2 Pi / Lambda).
      K4   : constant Long_Float := 4.0 * Pi / Lambda;
      Half : constant Long_Float := Beta / 2.0;

      --  Position de l'antenne et axe de visee, calcules une fois par
      --  balayage plutot qu'une fois par pixel et par balayage.
      Ax, Ay, Ux, Uy : array (Data'Range (1)) of Long_Float;
   begin
      for N in Data'Range (1) loop
         declare
            Phi : constant Long_Float :=
              Angles (Angles'First + (N - Data'First (1)));
         begin
            Ux (N) := Cos (Phi);
            Uy (N) := Sin (Phi);
            Ax (N) := Cfg.Radius * Ux (N);
            Ay (N) := Cfg.Radius * Uy (N);
         end;
      end loop;

      for A in Result'Range (1) loop
         declare
            Az : constant Long_Float :=
              Grid.Az_First + Long_Float (A - Result'First (1)) * Grid.Az_Step;
            Ca : constant Long_Float := Cos (Az);
            Sa : constant Long_Float := Sin (Az);
         begin
            for R in Result'Range (2) loop
               declare
                  Rho : constant Long_Float :=
                    Grid.Rho_First
                    + Long_Float (R - Result'First (2)) * Grid.Rho_Step;
                  Px  : constant Long_Float := Rho * Ca;
                  Py  : constant Long_Float := Rho * Sa;
                  Sum : Complex := (0.0, 0.0);
               begin
                  for N in Data'Range (1) loop
                     declare
                        Vx : constant Long_Float := Px - Ax (N);
                        Vy : constant Long_Float := Py - Ay (N);
                        --  Le pixel est-il dans l'ouverture de ce
                        --  balayage ? Angle entre l'axe de visee et la
                        --  direction antenne -> pixel.
                        Off : constant Long_Float :=
                          Arctan (Ux (N) * Vy - Uy (N) * Vx,
                                  Ux (N) * Vx + Uy (N) * Vy);
                     begin
                        if abs Off <= Half then
                           declare
                              D : constant Long_Float :=
                                Sqrt (Vx * Vx + Vy * Vy);
                           begin
                              --  Compensation de la phase aller-retour :
                              --  l'echo d'un point a la distance D porte
                              --  la phase -K4 x D ; on la retire.
                              Sum := Sum
                                + Sample_At (Cfg, Data, N, D)
                                  * Compose_From_Polar (1.0, K4 * D);
                           end;
                        end if;
                     end;
                  end loop;
                  Result (A, R) := Modulus (Sum);
               end;
            end loop;
         end;
      end loop;
   end Backproject;

   ---------------
   -- Real_Beam --
   ---------------

   procedure Real_Beam
     (Cfg    : Sensor_Config;
      Angles : Angle_Array;
      Data   : Scan_Data;
      Grid   : Polar_Grid;
      Result : out Image)
   is
   begin
      for A in Result'Range (1) loop
         declare
            Az : constant Long_Float :=
              Grid.Az_First + Long_Float (A - Result'First (1)) * Grid.Az_Step;
            Best      : Positive := Data'First (1);
            Best_Diff : Long_Float := Long_Float'Last;
         begin
            --  Le balayage qui regardait le plus droit vers ce pixel.
            for N in Data'Range (1) loop
               declare
                  Diff : constant Long_Float :=
                    abs Wrap (Angles (Angles'First + (N - Data'First (1)))
                              - Az);
               begin
                  if Diff < Best_Diff then
                     Best_Diff := Diff;
                     Best := N;
                  end if;
               end;
            end loop;
            declare
               Phi : constant Long_Float :=
                 Angles (Angles'First + (Best - Data'First (1)));
               Ax  : constant Long_Float := Cfg.Radius * Cos (Phi);
               Ay  : constant Long_Float := Cfg.Radius * Sin (Phi);
            begin
               for R in Result'Range (2) loop
                  declare
                     Rho : constant Long_Float :=
                       Grid.Rho_First
                       + Long_Float (R - Result'First (2)) * Grid.Rho_Step;
                     D   : constant Long_Float :=
                       Sqrt ((Rho * Cos (Az) - Ax) ** 2
                             + (Rho * Sin (Az) - Ay) ** 2);
                  begin
                     Result (A, R) :=
                       Modulus (Sample_At (Cfg, Data, Best, D));
                  end;
               end loop;
            end;
         end;
      end loop;
   end Real_Beam;

   ------------------
   -- Measure_Peak --
   ------------------

   function Measure_Peak (Grid : Polar_Grid; Img : Image) return Peak_Info
   is
      Best_A : Integer := Img'First (1);
      Best_R : Integer := Img'First (2);
      Best   : Long_Float := -1.0;
   begin
      for A in Img'Range (1) loop
         for R in Img'Range (2) loop
            if Img (A, R) > Best then
               Best := Img (A, R);
               Best_A := A;
               Best_R := R;
            end if;
         end loop;
      end loop;

      declare
         --  -3 dB en amplitude : le pic divise par racine de 2.
         Level : constant Long_Float := Best / Sqrt (2.0);
         Left  : Long_Float := Long_Float (Img'First (1));
         Right : Long_Float := Long_Float (Img'Last (1));
      begin
         --  Vers la gauche, jusqu'au premier pixel sous le niveau, puis
         --  interpolation lineaire entre lui et son voisin de droite.
         for A in reverse Img'First (1) .. Best_A - 1 loop
            if Img (A, Best_R) < Level then
               Left := Long_Float (A)
                 + (Level - Img (A, Best_R))
                   / (Img (A + 1, Best_R) - Img (A, Best_R));
               exit;
            end if;
         end loop;
         for A in Best_A + 1 .. Img'Last (1) loop
            if Img (A, Best_R) < Level then
               Right := Long_Float (A)
                 - (Level - Img (A, Best_R))
                   / (Img (A - 1, Best_R) - Img (A, Best_R));
               exit;
            end if;
         end loop;
         return
           (Az       => Grid.Az_First
                        + Long_Float (Best_A - Img'First (1)) * Grid.Az_Step,
            Rho      => Grid.Rho_First
                        + Long_Float (Best_R - Img'First (2)) * Grid.Rho_Step,
            Value    => Best,
            Width_Az => (Right - Left) * Grid.Az_Step);
      end;
   end Measure_Peak;

   ----------------
   -- Worst_Lobe --
   ----------------

   function Worst_Lobe
     (Grid      : Polar_Grid;
      Img       : Image;
      Peak      : Peak_Info;
      Exclusion : Long_Float) return Lobe_Info
   is
      Worst : Lobe_Info := (Az => Peak.Az, Ratio => 0.0);
   begin
      for A in Img'Range (1) loop
         declare
            Az : constant Long_Float :=
              Grid.Az_First + Long_Float (A - Img'First (1)) * Grid.Az_Step;
         begin
            if abs Wrap (Az - Peak.Az) > Exclusion then
               for R in Img'Range (2) loop
                  if Img (A, R) / Peak.Value > Worst.Ratio then
                     Worst := (Az => Az, Ratio => Img (A, R) / Peak.Value);
                  end if;
               end loop;
            end if;
         end;
      end loop;
      return Worst;
   end Worst_Lobe;

   ----------------------------
   -- Theoretical_Resolution --
   ----------------------------

   function Theoretical_Resolution
     (Radius : Long_Float;
      Beta   : Long_Float) return Long_Float
   is (Lambda / (4.0 * Radius * Sin (Beta / 2.0)));

end Radar_Sar;
