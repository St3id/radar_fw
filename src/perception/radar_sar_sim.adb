with Ada.Numerics;                           use Ada.Numerics;
with Ada.Numerics.Float_Random;
with Ada.Numerics.Long_Elementary_Functions;
use  Ada.Numerics.Long_Elementary_Functions;
with Ada.Numerics.Long_Complex_Types;
use  Ada.Numerics.Long_Complex_Types;

--  Corps de Radar_Sar_Sim. Chaque cible n'ajoute sa contribution qu'aux
--  cases proches de sa distance (quelques largeurs d'enveloppe) : au-dela,
--  l'enveloppe gaussienne est negligeable et le calcul serait perdu.

package body Radar_Sar_Sim
  with SPARK_Mode => Off
is

   package FR renames Ada.Numerics.Float_Random;

   Ln2 : constant := 0.693_147_180_559_945_3;

   --  Tirage gaussien centre reduit (methode de Box-Muller).
   function Gaussian (Gen : FR.Generator) return Long_Float is
      U1 : constant Long_Float :=
        Long_Float'Max (1.0E-12, Long_Float (FR.Random (Gen)));
      U2 : constant Long_Float := Long_Float (FR.Random (Gen));
   begin
      return Sqrt (-2.0 * Log (U1)) * Cos (2.0 * Pi * U2);
   end Gaussian;

   --------------
   -- Simulate --
   --------------

   procedure Simulate
     (Cfg     : Sensor_Config;
      Targets : Target_Array;
      Angles  : Angle_Array;
      Errors  : Error_Model;
      Seed    : Integer;
      Data    : out Scan_Data)
   is
      Gen : FR.Generator;
      K4  : constant Long_Float := 4.0 * Pi / Lambda;
      --  Au-dela de 3 largeurs a mi-hauteur, l'enveloppe vaut moins de
      --  2E-11 : on n'y ajoute rien.
      Reach : constant Long_Float := 3.0 * Cfg.Envelope_Fwhm;
   begin
      FR.Reset (Gen, Seed);
      for N in Data'Range (1) loop
         declare
            Nominal : constant Long_Float :=
              Angles (Angles'First + (N - Data'First (1)));
            --  Ou la mecanique a vraiment mis l'antenne.
            Phi     : constant Long_Float :=
              Nominal + Errors.Angle_Rms * Gaussian (Gen);
            Rad     : constant Long_Float :=
              Cfg.Radius + Errors.Radial_Rms * Gaussian (Gen);
            Jitter  : constant Long_Float := Errors.Phase_Rms * Gaussian (Gen);
            Ux      : constant Long_Float := Cos (Phi);
            Uy      : constant Long_Float := Sin (Phi);
            Ax      : constant Long_Float := Rad * Ux;
            Ay      : constant Long_Float := Rad * Uy;
         begin
            --  Le bruit d'abord, sur toutes les cases.
            for K in Data'Range (2) loop
               Data (N, K) :=
                 (Re => Errors.Noise_Rms * Gaussian (Gen),
                  Im => Errors.Noise_Rms * Gaussian (Gen));
            end loop;

            --  Puis l'echo de chaque cible, sur les cases proches de sa
            --  distance.
            for T of Targets loop
               declare
                  Vx    : constant Long_Float := T.X - Ax;
                  Vy    : constant Long_Float := T.Y - Ay;
                  D     : constant Long_Float := Sqrt (Vx * Vx + Vy * Vy);
                  Theta : constant Long_Float :=
                    Arctan (Ux * Vy - Uy * Vx, Ux * Vx + Uy * Vy);
                  Beam  : constant Long_Float :=
                    Exp (-4.0 * Ln2 * (Theta / Cfg.Beam_Hpbw) ** 2);
                  Echo  : constant Complex :=
                    Compose_From_Polar (T.Amplitude * Beam / (D * D),
                                        -K4 * D + Jitter);
               begin
                  for K in Data'Range (2) loop
                     declare
                        R : constant Long_Float :=
                          Cfg.Range_Start
                          + Long_Float (K - Data'First (2)) * Cfg.Range_Step;
                     begin
                        if abs (R - D) <= Reach then
                           Data (N, K) := Data (N, K)
                             + Echo * Exp (-4.0 * Ln2
                                           * ((R - D) / Cfg.Envelope_Fwhm)
                                             ** 2);
                        end if;
                     end;
                  end loop;
               end;
            end loop;
         end;
      end loop;
   end Simulate;

   --------------------
   -- Uniform_Angles --
   --------------------

   function Uniform_Angles
     (First, Last, Step : Long_Float) return Angle_Array
   is
      Count  : constant Positive :=
        Natural (Long_Float'Floor ((Last - First) / Step + 1.0E-9)) + 1;
      Result : Angle_Array (1 .. Count);
   begin
      for I in Result'Range loop
         Result (I) := First + Long_Float (I - 1) * Step;
      end loop;
      return Result;
   end Uniform_Angles;

end Radar_Sar_Sim;
