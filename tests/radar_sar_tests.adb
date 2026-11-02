with AUnit.Assertions;                      use AUnit.Assertions;
with Ada.Numerics;                           use Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
use  Ada.Numerics.Long_Elementary_Functions;
with Radar_Sar;                              use Radar_Sar;
with Radar_Sar_Sim;                          use Radar_Sar_Sim;

--  Corps de la suite 3. Une mire ponctuelle a 3 m, vue par un A121 nu
--  (65 deg, profil 2) decentre de 60 mm : le montage de la tour fine.

package body Radar_Sar_Tests is

   Deg : constant := Pi / 180.0;

   Base : constant Sensor_Config :=
     (Radius        => 0.060,
      Beam_Hpbw     => 65.0 * Deg,
      Envelope_Fwhm => 0.080,
      Range_Start   => 2.50,
      Range_Step    => 0.010);
   Points : constant := 101;

   Mire : constant Target_Array :=
     (1 => (X => 3.0, Y => 0.0, Amplitude => 1.0));

   --  +/-10 deg au pas de 0,05 deg, 2,9 a 3,1 m au pas de 5 mm.
   Fine : constant Polar_Grid :=
     (Az_First  => -10.0 * Deg, Az_Step  => 0.05 * Deg, Num_Az  => 401,
      Rho_First => 2.90,        Rho_Step => 0.005,      Num_Rho => 41);

   --  Image SAR de la mire (ouverture traitee de 60 deg) et son pic. Seed
   --  ne compte que si Errors tire des erreurs aleatoires.
   function Point_Sar
     (Step   : Long_Float;
      Errors : Error_Model;
      Grid   : Polar_Grid;
      Seed   : Integer := 42) return Peak_Info
   is
      Angles : constant Angle_Array :=
        Uniform_Angles (-90.0 * Deg, 90.0 * Deg, Step);
      Data   : Scan_Data (Angles'Range, 1 .. Points);
      Img    : Image (1 .. Grid.Num_Az, 1 .. Grid.Num_Rho);
   begin
      Simulate (Base, Mire, Angles, Errors, Seed, Data);
      Backproject (Base, Angles, Data, Grid, 60.0 * Deg, Img);
      return Measure_Peak (Grid, Img);
   end Point_Sar;

   --  Perte au pic en dB par rapport a un pic de reference.
   function Loss_Db (P, Ref : Peak_Info) return Long_Float is
     (20.0 * Log (P.Value / Ref.Value, 10.0));

   ----------
   -- Name --
   ----------

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Synthese d'ouverture en arc (SAR)");
   end Name;

   --  Test 1 : la mire est focalisee au bon endroit, avec la finesse que
   --  la theorie annonce. Mesure : 2,25 deg a -3 dB pour un premier zero
   --  theorique de 2,37 deg ; le pic tombe sur la mire.
   procedure Test_Sar_Focus
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P : constant Peak_Info := Point_Sar (1.5 * Deg, No_Errors, Fine);
      Th : constant Long_Float := Theoretical_Resolution (0.060, 60.0 * Deg);
   begin
      Assert (abs P.Az < 0.1 * Deg,
              "Le pic doit tomber sur l'azimut de la mire (0 deg)");
      Assert (abs (P.Rho - 3.0) < 0.01,
              "Le pic doit tomber a la distance de la mire (3 m)");
      Assert (P.Width_Az > 0.8 * Th and then P.Width_Az < 1.1 * Th,
              "La largeur a -3 dB doit valoir 0,8 a 1,1 fois le premier"
              & " zero theorique");
   end Test_Sar_Focus;

   --  Test 2 : ce que la synthese apporte. Sans elle, la tourelle ne
   --  distingue pas mieux que son faisceau (mesure : 43,6 deg) ; avec
   --  elle, ~19 fois mieux.
   procedure Test_Sar_Vs_Real_Beam
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Wide   : constant Polar_Grid :=
        (Az_First  => -60.0 * Deg, Az_Step  => 0.25 * Deg, Num_Az  => 481,
         Rho_First => 2.90,        Rho_Step => 0.01,       Num_Rho => 21);
      Angles : constant Angle_Array :=
        Uniform_Angles (-90.0 * Deg, 90.0 * Deg, 1.5 * Deg);
      Data   : Scan_Data (Angles'Range, 1 .. Points);
      Img    : Image (1 .. Wide.Num_Az, 1 .. Wide.Num_Rho);
      Real   : Peak_Info;
      Sar    : constant Peak_Info := Point_Sar (1.5 * Deg, No_Errors, Fine);
   begin
      Simulate (Base, Mire, Angles, No_Errors, 42, Data);
      Real_Beam (Base, Angles, Data, Wide, Img);
      Real := Measure_Peak (Wide, Img);
      Assert (Real.Width_Az > 35.0 * Deg,
              "Le faisceau reel doit rester large (plus de 35 deg)");
      Assert (Real.Width_Az > 15.0 * Sar.Width_Az,
              "La synthese doit affiner l'azimut d'au moins 15 fois");
   end Test_Sar_Vs_Real_Beam;

   --  Test 3 : les tolerances, en perte moyenne sur plusieurs tirages. Un
   --  seul tirage peut etre chanceux : sur 30, 0,5 deg d'erreur d'angle
   --  coute de -0,34 a -0,62 dB, et le seuil ne doit pas dependre de la
   --  suite exacte du generateur aleatoire. Moyennes sur 30 tirages : le
   --  faux-rond du rayon est la contrainte critique (0,14 mm RMS :
   --  -0,47 dB ; 0,5 mm : -6,2 dB) ; l'erreur d'angle l'est peu (0,5 deg
   --  RMS : -0,48 dB), car un decalage tangentiel change a peine la
   --  distance aux cibles proches de l'axe de visee ; la gigue de phase
   --  suit la loi des erreurs gaussiennes, -4,34 x sigma**2 dB (20 deg
   --  RMS : -0,53 dB, theorie -0,53).
   procedure Test_Sar_Tolerance
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Near  : constant Polar_Grid :=
        (Az_First  => -3.0 * Deg, Az_Step  => 0.05 * Deg, Num_Az  => 121,
         Rho_First => 2.95,       Rho_Step => 0.005,      Num_Rho => 21);
      Ref   : constant Peak_Info := Point_Sar (1.5 * Deg, No_Errors, Near);
      Draws : constant := 8;

      --  Perte moyenne au pic, en dB, sur les graines 1 a Draws.
      function Mean_Loss_Db (Errors : Error_Model) return Long_Float is
         Sum : Long_Float := 0.0;
      begin
         for Seed in 1 .. Draws loop
            Sum := Sum
              + Loss_Db (Point_Sar (1.5 * Deg, Errors, Near, Seed), Ref);
         end loop;
         return Sum / Long_Float (Draws);
      end Mean_Loss_Db;
   begin
      Assert (Mean_Loss_Db ((Radial_Rms => 0.14E-3, others => 0.0)) > -1.0,
              "0,14 mm RMS de faux-rond doit couter moins de 1 dB");
      Assert (Mean_Loss_Db ((Radial_Rms => 0.5E-3, others => 0.0)) < -4.0,
              "0,5 mm RMS de faux-rond doit couter plus de 4 dB");
      Assert (Mean_Loss_Db ((Angle_Rms => 0.5 * Deg, others => 0.0)) > -1.0,
              "0,5 deg RMS d'erreur d'angle doit couter moins de 1 dB");
      Assert (Mean_Loss_Db ((Phase_Rms => 20.0 * Deg, others => 0.0)) > -1.0,
              "20 deg RMS de gigue de phase doivent couter moins de 1 dB");
   end Test_Sar_Tolerance;

   --  Test 4 : le pas d'echantillonnage. A 60 mm et 60 deg d'ouverture,
   --  la limite de Nyquist est 2,37 deg par balayage. A 1,5 deg et a
   --  2 deg (180 balayages par tour, le reglage prevu), aucun lobe hors du
   --  pic ne depasse -15 dB (mesure : -20,6 et -20,5). Au-dela, une image
   --  fantome apparait : vers 47 deg a -10 dB pour un pas de 3 deg, vers
   --  27,5 deg a -3,6 dB pour 5 deg. D'ou la bande de +/-90 deg : a +/-40,
   --  le fantome du pas de 3 deg passait inapercu.
   procedure Test_Sar_Sampling
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Band : constant Polar_Grid :=
        (Az_First  => -90.0 * Deg, Az_Step  => 0.25 * Deg, Num_Az  => 721,
         Rho_First => 2.95,        Rho_Step => 0.005,      Num_Rho => 21);

      function Worst_Lobe_Db (Step : Long_Float) return Long_Float is
         Angles : constant Angle_Array :=
           Uniform_Angles (-90.0 * Deg, 90.0 * Deg, Step);
         Data   : Scan_Data (Angles'Range, 1 .. Points);
         Img    : Image (1 .. Band.Num_Az, 1 .. Band.Num_Rho);
      begin
         Simulate (Base, Mire, Angles, No_Errors, 42, Data);
         Backproject (Base, Angles, Data, Band, 60.0 * Deg, Img);
         return 20.0 * Log (Worst_Lobe (Band, Img,
                                        Measure_Peak (Band, Img),
                                        5.0 * Deg).Ratio, 10.0);
      end Worst_Lobe_Db;
   begin
      Assert (Worst_Lobe_Db (1.5 * Deg) < -15.0,
              "A 1,5 deg par balayage, aucun lobe au-dessus de -15 dB");
      Assert (Worst_Lobe_Db (2.0 * Deg) < -15.0,
              "A 2 deg par balayage, aucun lobe au-dessus de -15 dB");
      Assert (Worst_Lobe_Db (3.0 * Deg) > -15.0,
              "A 3 deg par balayage, un fantome doit apparaitre");
      Assert (Worst_Lobe_Db (5.0 * Deg) > -6.0,
              "A 5 deg par balayage, le fantome doit depasser -6 dB");
   end Test_Sar_Sampling;

   --------------------
   -- Register_Tests --
   --------------------

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Sar_Focus'Access,
         "SAR : mire focalisee, finesse conforme a la theorie");
      Register_Routine
        (T, Test_Sar_Vs_Real_Beam'Access,
         "SAR : au moins 15 fois plus fin que le faisceau reel");
      Register_Routine
        (T, Test_Sar_Tolerance'Access,
         "SAR : tolerances de faux-rond, d'angle et de phase");
      Register_Routine
        (T, Test_Sar_Sampling'Access,
         "SAR : repliement si l'on echantillonne trop peu");
   end Register_Tests;

end Radar_Sar_Tests;
