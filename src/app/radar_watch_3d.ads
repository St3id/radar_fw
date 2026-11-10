with Radar_Clutter;    use Radar_Clutter;
with Radar_Cloud;      use Radar_Cloud;
with Radar_Detect;     use Radar_Detect;
with Radar_Settings;
with Radar_Sim_Source; use Radar_Sim_Source;
with Radar_Source;     use Radar_Source;
with Radar_Track;      use Radar_Track;

--  Radar_Watch_3D : la veille sur profils simules, sans serveur. Meme chaine
--  que le mode live (decor appris, clutter soustrait, pistes 3D), decoupee en
--  petits morceaux : un tour entier sur le fil de l'interface la figerait.

package Radar_Watch_3D with SPARK_Mode => Off is

   type Watch is limited record
      Src         : Simulated_Source;
      Trk         : Tracker;
      Clut        : Clutter_Map;
      F           : Frame;
      Decor       : Point_Cloud;
      Turn        : Natural := 0;
      In_Turn     : Natural := 0;
      Virtual     : Time_Ms := 0;
      Recal_Asked : Boolean := False;
      Calib       : Positive := 8;
      Learn_Every : Positive := 4;
      Age_Every   : Positive := 32;
   end record;

   procedure Start (W : in out Watch; S : Radar_Settings.Settings);

   --  Traite les mesures dues a l'heure Now, bornees par appel. Now sur
   --  l'horloge virtuelle de la source (1 ms par mesure).
   procedure Step (W : in out Watch; Now : Time_Ms);

   --  Oublie le decor et recommence la calibration a la fin du tour courant :
   --  au milieu, la carte ne couvrirait qu'une partie des directions.
   procedure Recalibrate (W : in out Watch);

   function Calibrating (W : Watch) return Boolean is (W.Turn < W.Calib);

end Radar_Watch_3D;
