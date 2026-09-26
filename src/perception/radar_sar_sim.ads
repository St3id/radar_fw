with Radar_Sar;  use Radar_Sar;

--  Radar_Sar_Sim : echos complexes simules d'un capteur coherent monte
--  decentre sur une tourelle, pour eprouver la synthese d'ouverture
--  avant d'avoir le materiel (porte G0 du guide materiel).
--
--  Modele volontairement simple, a remplacer par des mesures :
--  - faisceau gaussien de largeur Beam_Hpbw a mi-puissance ; l'amplitude
--    aller-retour suit le diagramme en puissance de l'aller ;
--  - enveloppe d'impulsion gaussienne de largeur Envelope_Fwhm ;
--  - phase aller-retour -4 Pi d / Lambda, plate le long de l'enveloppe,
--    ce que donne l'option "phase enhancement" de l'A121 ;
--  - amplitude en 1 / d**2 pour une cible ponctuelle ;
--  - bruit complexe gaussien.
--
--  Les erreurs mecaniques s'injectent balayage par balayage : le
--  capteur simule est la ou la mecanique l'a vraiment mis, alors que le
--  traitement le croit la ou la consigne l'envoyait. C'est exactement
--  la situation reelle, et c'est ce qui fixe les tolerances.

package Radar_Sar_Sim
  with SPARK_Mode => Off
is

   type Point_Target is record
      X, Y      : Long_Float;  --  position dans le plan (m)
      Amplitude : Long_Float;  --  echo relatif, avant l'attenuation en 1/d**2
   end record;

   type Target_Array is array (Positive range <>) of Point_Target;

   --  Erreurs, en ecart-type par balayage.
   type Error_Model is record
      Radial_Rms : Long_Float;  --  faux-rond du rayon de la tete (m)
      Angle_Rms  : Long_Float;  --  erreur d'angle de la tourelle (rad)
      Phase_Rms  : Long_Float;  --  gigue de phase residuelle du capteur (rad)
      Noise_Rms  : Long_Float;  --  bruit, par composante I et Q
   end record;

   No_Errors : constant Error_Model := (others => 0.0);

   --  Un balayage par angle de Angles. Seed rend le tirage reproductible
   --  (R4 : un meme essai se rejoue a l'identique).
   procedure Simulate
     (Cfg     : Sensor_Config;
      Targets : Target_Array;
      Angles  : Angle_Array;
      Errors  : Error_Model;
      Seed    : Integer;
      Data    : out Scan_Data)
     with Pre => Valid (Cfg) and then Angles'Length = Data'Length (1);

   --  Angles regulierement espaces de First a Last inclus (rad).
   function Uniform_Angles
     (First, Last, Step : Long_Float) return Angle_Array
     with Pre => Step > 0.0 and then Last >= First;

end Radar_Sar_Sim;
