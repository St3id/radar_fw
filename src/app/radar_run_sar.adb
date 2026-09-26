with Ada.Text_IO;                            use Ada.Text_IO;
with Ada.Numerics;                           use Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
use  Ada.Numerics.Long_Elementary_Functions;
with Radar_Sar;                              use Radar_Sar;
with Radar_Sar_Sim;                          use Radar_Sar_Sim;

--  Mode sar : la porte G0 du guide materiel, jouee en simulation.
--
--  Une mire ponctuelle a 3 m, vue par un A121 decentre sur une tourelle.
--  On mesure ce que la synthese d'ouverture apporte (finesse en azimut
--  contre faisceau reel) et ce qu'elle exige (faux-rond, angle, gigue de
--  phase, pas d'echantillonnage). Aucun materiel : ce sont ces chiffres
--  qui disent s'il vaut la peine de construire la tourelle decentree.
procedure Radar_Run_Sar is

   Deg : constant := Pi / 180.0;

   --  Une liste de valeurs a essayer, dans leur unite d'affichage.
   type Values is array (Positive range <>) of Long_Float;

   --  L'A121 nu : 65 deg a mi-puissance dans le plan horizontal, profil 2
   --  (80 mm), echantillons de 10 mm de 2,5 a 3,5 m autour de la mire.
   Base : constant Sensor_Config :=
     (Radius        => 0.060,
      Beam_Hpbw     => 65.0 * Deg,
      Envelope_Fwhm => 0.080,
      Range_Start   => 2.50,
      Range_Step    => 0.010);
   Points : constant := 101;

   Mire : constant Target_Array :=
     (1 => (X => 3.0, Y => 0.0, Amplitude => 1.0));

   --  Grille fine autour de la mire : +/-10 deg au pas de 0,05 deg.
   Fine : constant Polar_Grid :=
     (Az_First  => -10.0 * Deg, Az_Step  => 0.05 * Deg, Num_Az  => 401,
      Rho_First => 2.90,        Rho_Step => 0.005,      Num_Rho => 41);

   --  Nombre a deux decimales, avec la virgule francaise.
   function Fmt (V : Long_Float) return String is
      C : constant Integer := Integer (V * 100.0);
      S : constant String := Integer'Image (abs C);
      U : constant String := S (S'First + 1 .. S'Last);
      P : constant String :=
        (if U'Length < 3 then (1 .. 3 - U'Length => '0') & U else U);
   begin
      return (if C < 0 then "-" else "")
        & P (P'First .. P'Last - 2) & "," & P (P'Last - 1 .. P'Last);
   end Fmt;

   --  Rapport d'amplitudes en decibels.
   function Db (Ratio : Long_Float) return Long_Float is
     (20.0 * Log (Ratio, 10.0));

   --  Image SAR de la mire et mesure de son pic. Seed ne compte que si
   --  Errors tire des erreurs aleatoires.
   function Point_Sar
     (Cfg    : Sensor_Config;
      Beta   : Long_Float;
      Step   : Long_Float;
      Errors : Error_Model;
      Grid   : Polar_Grid;
      Seed   : Integer := 42) return Peak_Info
   is
      Angles : constant Angle_Array :=
        Uniform_Angles (-90.0 * Deg, 90.0 * Deg, Step);
      Data   : Scan_Data (Angles'Range, 1 .. Points);
      Img    : Image (1 .. Grid.Num_Az, 1 .. Grid.Num_Rho);
   begin
      Simulate (Cfg, Mire, Angles, Errors, Seed, Data);
      Backproject (Cfg, Angles, Data, Grid, Beta, Img);
      return Measure_Peak (Grid, Img);
   end Point_Sar;

begin
   Put_Line ("SAR simule : mire a 3 m, A121 nu (65 deg), profil 2 (80 mm)");
   New_Line;

   --  ----- 1. Finesse obtenue contre theorie -----
   for Beta_Deg of Values'(60.0, 90.0) loop
      declare
         P : constant Peak_Info :=
           Point_Sar (Base, Beta_Deg * Deg, 1.5 * Deg, No_Errors, Fine);
         T : constant Long_Float :=
           Theoretical_Resolution (Base.Radius, Beta_Deg * Deg);
      begin
         Put_Line ("r = 60 mm, ouverture traitee " & Fmt (Beta_Deg)
                   & " deg : largeur a -3 dB " & Fmt (P.Width_Az / Deg)
                   & " deg (premier zero theorique " & Fmt (T / Deg)
                   & " deg) ; pic a " & Fmt (P.Az / Deg) & " deg et "
                   & Fmt (P.Rho * 100.0) & " cm");
      end;
   end loop;

   --  ----- 2. Faisceau reel -----
   declare
      Wide   : constant Polar_Grid :=
        (Az_First  => -60.0 * Deg, Az_Step  => 0.25 * Deg, Num_Az  => 481,
         Rho_First => 2.90,        Rho_Step => 0.01,       Num_Rho => 21);
      Angles : constant Angle_Array :=
        Uniform_Angles (-90.0 * Deg, 90.0 * Deg, 1.5 * Deg);
      Data   : Scan_Data (Angles'Range, 1 .. Points);
      Img    : Image (1 .. Wide.Num_Az, 1 .. Wide.Num_Rho);
      P      : Peak_Info;
   begin
      Simulate (Base, Mire, Angles, No_Errors, 42, Data);
      Real_Beam (Base, Angles, Data, Wide, Img);
      P := Measure_Peak (Wide, Img);
      Put_Line ("faisceau reel (sans synthese) : largeur a -3 dB "
                & Fmt (P.Width_Az / Deg) & " deg");
   end;
   New_Line;

   --  ----- 3. Tolerances : perte au pic par rapport a zero erreur -----
   --  Un seul tirage peut etre chanceux : chaque valeur est rejouee sur
   --  Draws graines, et l'on garde la moyenne et le pire cas. La grille
   --  est resserree autour de la mire pour que ces images restent rapides.
   declare
      Near  : constant Polar_Grid :=
        (Az_First  => -3.0 * Deg, Az_Step  => 0.05 * Deg, Num_Az  => 121,
         Rho_First => 2.95,       Rho_Step => 0.005,      Num_Rho => 21);
      Draws : constant := 30;
      Ref   : constant Peak_Info :=
        Point_Sar (Base, 60.0 * Deg, 1.5 * Deg, No_Errors, Near);

      procedure Report (Label : String; Errors : Error_Model) is
         Sum   : Long_Float := 0.0;
         Worst : Long_Float := 0.0;
      begin
         for Seed in 1 .. Draws loop
            declare
               L : constant Long_Float :=
                 Db (Point_Sar (Base, 60.0 * Deg, 1.5 * Deg, Errors, Near,
                                Seed).Value / Ref.Value);
            begin
               Sum := Sum + L;
               Worst := Long_Float'Min (Worst, L);
            end;
         end loop;
         Put_Line (Label & " : perte moyenne "
                   & Fmt (Sum / Long_Float (Draws)) & " dB, pire "
                   & Fmt (Worst) & " dB");
      end Report;
   begin
      Put_Line ("tolerances, perte au pic sur" & Integer'Image (Draws)
                & " tirages :");
      for Mm of Values'(0.05, 0.10, 0.14, 0.20, 0.30, 0.50) loop
         Report ("faux-rond " & Fmt (Mm) & " mm RMS",
                 (Radial_Rms => Mm / 1000.0, others => 0.0));
      end loop;
      for A of Values'(0.05, 0.10, 0.20, 0.50, 1.00) loop
         Report ("erreur d'angle " & Fmt (A) & " deg RMS",
                 (Angle_Rms => A * Deg, others => 0.0));
      end loop;
      for Ph of Values'(5.0, 10.0, 20.0, 45.0) loop
         Report ("gigue de phase " & Fmt (Ph) & " deg RMS",
                 (Phase_Rms => Ph * Deg, others => 0.0));
      end loop;
   end;
   New_Line;

   --  ----- 4. Pas d'echantillonnage : lobes de reseau -----
   --  Toute la moitie avant balayee (+/-90 deg) : un fantome peut tomber
   --  loin du vrai point, vers 47 deg pour un pas de 3 deg.
   declare
      Band : constant Polar_Grid :=
        (Az_First  => -90.0 * Deg, Az_Step  => 0.25 * Deg, Num_Az  => 721,
         Rho_First => 2.95,        Rho_Step => 0.005,      Num_Rho => 21);
   begin
      for Step of Values'(1.0, 1.5, 2.0, 3.0, 5.0) loop
         declare
            Angles : constant Angle_Array :=
              Uniform_Angles (-90.0 * Deg, 90.0 * Deg, Step * Deg);
            Data   : Scan_Data (Angles'Range, 1 .. Points);
            Img    : Image (1 .. Band.Num_Az, 1 .. Band.Num_Rho);
            L      : Lobe_Info;
         begin
            Simulate (Base, Mire, Angles, No_Errors, 42, Data);
            Backproject (Base, Angles, Data, Band, 60.0 * Deg, Img);
            L := Worst_Lobe (Band, Img, Measure_Peak (Band, Img), 5.0 * Deg);
            Put_Line ("pas " & Fmt (Step) & " deg : plus fort lobe hors"
                      & " +/-5 deg a " & Fmt (Db (L.Ratio)) & " dB du pic,"
                      & " azimut " & Fmt (L.Az / Deg) & " deg");
         end;
      end loop;
   end;
   New_Line;

   --  ----- 5. Rayon de la tete -----
   for R_Mm of Values'(40.0, 60.0, 80.0) loop
      declare
         Cfg : constant Sensor_Config :=
           (Radius        => R_Mm / 1000.0,
            Beam_Hpbw     => Base.Beam_Hpbw,
            Envelope_Fwhm => Base.Envelope_Fwhm,
            Range_Start   => Base.Range_Start,
            Range_Step    => Base.Range_Step);
         P   : constant Peak_Info :=
           Point_Sar (Cfg, 60.0 * Deg, 1.0 * Deg, No_Errors, Fine);
      begin
         Put_Line ("rayon " & Fmt (R_Mm) & " mm : largeur a -3 dB "
                   & Fmt (P.Width_Az / Deg) & " deg (theorie au premier"
                   & " zero " & Fmt (Theoretical_Resolution
                                       (R_Mm / 1000.0, 60.0 * Deg) / Deg)
                   & " deg)");
      end;
   end loop;
end Radar_Run_Sar;
