with Ada.Strings.Unbounded;

--  Radar_Settings : ce que la console laisse regler, borne et valide ici.
--  Les valeurs par defaut reproduisent les constantes du code (teste).
--
--  Les seuils CFAR, la grille du clutter, la plausibilite et la graine ne
--  sont pas exposes : recales sur la simulation ou prouves, un curseur les
--  ferait passer pour des reglages mesures.

package Radar_Settings with SPARK_Mode => Off is

   subtype Confirm_Range  is Integer range 2 .. 5;
   subtype Coast_Range    is Integer range 1_000 .. 10_000;
   subtype Speed_Range    is Integer range 1_000 .. 6_000;
   subtype Replay_Range   is Integer range 50 .. 800;
   subtype Learn_Range    is Integer range 1 .. 16;
   subtype Age_Range      is Integer range 8 .. 128;
   subtype Calib_Range    is Integer range 2 .. 32;
   subtype Az_Steps_Range is Integer range 60 .. 360;
   subtype El_Steps_Range is Integer range 8 .. 32;

   type Settings is record
      Confirm_Hits      : Confirm_Range  := 3;
      Coast_Ms          : Coast_Range    := 2_500;
      Max_Speed_Mm_S    : Speed_Range    := 3_000;
      Replay_Percent    : Replay_Range   := 100;
      Learn_Period      : Learn_Range    := 4;
      Age_Period        : Age_Range      := 32;
      Calibration_Turns : Calib_Range    := 8;
      Map_Az_Steps      : Az_Steps_Range := 180;
      Map_El_Steps      : El_Steps_Range := 24;
   end record;

   Defaults : constant Settings := (others => <>);

   --  Une case de decor n'est apprise que si elle est vue plus souvent que
   --  ce pourcentage des tours (voir Age_Period dans radar_run_live).
   function Learn_Threshold_Percent (S : Settings) return Natural is
     (100 * S.Learn_Period / S.Age_Period);

   procedure Save (S : Settings; Path : String; Ok : out Boolean);

   --  Fichier absent : les defauts, sans message. Valeur invalide : le
   --  defaut de ce champ, et Message le dit.
   procedure Load
     (S       : out Settings;
      Path    : String;
      Message : out Ada.Strings.Unbounded.Unbounded_String);

end Radar_Settings;
