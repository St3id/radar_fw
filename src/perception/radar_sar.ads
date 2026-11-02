with Ada.Numerics.Long_Complex_Types;  use Ada.Numerics.Long_Complex_Types;

--  Radar_Sar : synthese d'ouverture en arc pour un capteur coherent
--  (type Acconeer A121) monte decentre sur une tourelle qui tourne.
--
--  Le capteur, a la distance Radius de l'axe, decrit un arc de cercle.
--  Un seul balayage ne dit que la distance des echos ; mais d'un
--  balayage au suivant, la phase de l'echo d'un point fixe change de
--  facon previsible, selon 4 pi d / Lambda. En compensant cette phase
--  pour chaque position supposee du point, puis en sommant, les echos
--  s'ajoutent en phase au bon endroit et s'annulent ailleurs : on
--  synthetise une antenne de la taille de l'arc, bien plus grande que
--  la puce. La finesse en azimut passe de la largeur du faisceau reel
--  a environ Lambda / (4 Radius sin (Beta / 2)).
--
--  Paquet du PC, hors du coeur embarquable (R7) : flottants longs et
--  tableaux de plusieurs centaines de Ko. SPARK_Mode Off parce que les
--  complexes et la trigonometrie de la bibliotheque standard sont hors
--  du sous-ensemble prouve ; R2 l'admet pour du code neuf.
--
--  Unites : metres et radians. Repere : plan horizontal, axe de
--  rotation a l'origine, azimut 0 selon x.

package Radar_Sar
  with SPARK_Mode => Off
is

   --  Longueur d'onde a 60,5 GHz, frequence centrale de l'A121 (m).
   Lambda : constant := 299_792_458.0 / 60.5E9;

   --  Ce que le traitement doit savoir du capteur et de son montage.
   type Sensor_Config is record
      Radius        : Long_Float;  --  distance antenne - axe (m)
      Beam_Hpbw     : Long_Float;  --  faisceau reel a mi-puissance (rad)
      Envelope_Fwhm : Long_Float;  --  largeur de l'impulsion (m)
      Range_Start   : Long_Float;  --  distance du premier echantillon (m)
      Range_Step    : Long_Float;  --  pas entre echantillons (m)
   end record;

   --  Un balayage par ligne : Data (N, K) est l'echantillon complexe K
   --  du balayage N, a la distance Range_Start + (K - 1) * Range_Step.
   type Scan_Data is array (Positive range <>, Positive range <>)
     of Complex;

   --  Angle de la tourelle (rad) au moment de chaque balayage, tel que
   --  le traitement le croit : c'est la que se cachent les erreurs
   --  mecaniques.
   type Angle_Array is array (Positive range <>) of Long_Float;

   --  Grille polaire de l'image, centree sur l'axe de rotation.
   type Polar_Grid is record
      Az_First  : Long_Float;  --  azimut de la premiere colonne (rad)
      Az_Step   : Long_Float;
      Num_Az    : Positive;
      Rho_First : Long_Float;  --  distance a l'axe de la premiere ligne (m)
      Rho_Step  : Long_Float;
      Num_Rho   : Positive;
   end record;

   --  Image d'amplitudes : Img (A, R) pour l'azimut A et la distance R.
   type Image is array (Positive range <>, Positive range <>)
     of Long_Float;

   --  Rayon de la tete, faisceau et plage doivent avoir un sens.
   function Valid (Cfg : Sensor_Config) return Boolean is
     (Cfg.Radius >= 0.0 and then Cfg.Radius < 1.0
      and then Cfg.Beam_Hpbw > 0.0 and then Cfg.Envelope_Fwhm > 0.0
      and then Cfg.Range_Start >= 0.0 and then Cfg.Range_Step > 0.0);

   --  Image SAR par retroprojection : pour chaque pixel, somme coherente
   --  des balayages dont l'axe de visee passe a moins de Beta / 2 du
   --  pixel, apres compensation de la phase aller-retour.
   procedure Backproject
     (Cfg    : Sensor_Config;
      Angles : Angle_Array;
      Data   : Scan_Data;
      Grid   : Polar_Grid;
      Beta   : Long_Float;
      Result : out Image)
     with Pre => Valid (Cfg)
                 and then Angles'Length = Data'Length (1)
                 and then Result'Length (1) = Grid.Num_Az
                 and then Result'Length (2) = Grid.Num_Rho
                 and then Beta > 0.0;

   --  Image a faisceau reel, pour comparaison : chaque pixel prend
   --  l'amplitude du balayage dont l'axe de visee est le plus proche de
   --  lui. C'est ce que donnerait la tourelle sans synthese d'ouverture.
   procedure Real_Beam
     (Cfg    : Sensor_Config;
      Angles : Angle_Array;
      Data   : Scan_Data;
      Grid   : Polar_Grid;
      Result : out Image)
     with Pre => Valid (Cfg)
                 and then Angles'Length = Data'Length (1)
                 and then Result'Length (1) = Grid.Num_Az
                 and then Result'Length (2) = Grid.Num_Rho;

   --  Le pic le plus fort d'une image et sa largeur en azimut a -3 dB
   --  (amplitude divisee par racine de 2), mesuree sur sa ligne de
   --  distance, avec interpolation lineaire entre pixels.
   type Peak_Info is record
      Az       : Long_Float;  --  azimut du pic (rad)
      Rho      : Long_Float;  --  distance du pic a l'axe (m)
      Value    : Long_Float;  --  amplitude du pic
      Width_Az : Long_Float;  --  largeur a -3 dB (rad)
   end record;

   function Measure_Peak (Grid : Polar_Grid; Img : Image) return Peak_Info
     with Pre => Img'Length (1) = Grid.Num_Az
                 and then Img'Length (2) = Grid.Num_Rho;

   --  Le plus fort lobe de l'image hors de la bande de +/- Exclusion (rad)
   --  autour de l'azimut du pic, toutes distances confondues : lobes
   --  secondaires, et images fantomes (lobes de reseau) quand les
   --  balayages sont trop espaces.
   type Lobe_Info is record
      Az    : Long_Float;  --  azimut du lobe (rad)
      Ratio : Long_Float;  --  amplitude du lobe rapportee au pic
   end record;

   function Worst_Lobe
     (Grid      : Polar_Grid;
      Img       : Image;
      Peak      : Peak_Info;
      Exclusion : Long_Float) return Lobe_Info
     with Pre => Img'Length (1) = Grid.Num_Az
                 and then Img'Length (2) = Grid.Num_Rho
                 and then Peak.Value > 0.0;

   --  Finesse theorique au premier zero : Lambda / (4 Radius sin (Beta/2)).
   function Theoretical_Resolution
     (Radius : Long_Float;
      Beta   : Long_Float) return Long_Float
     with Pre => Radius > 0.0 and then Beta > 0.0;

end Radar_Sar;
