with Radar_Ld2450_Log;

--  Radar_Modes : quelles combinaisons source / activite ont un sens, et ce
--  que l'ecran a le droit d'en dire. Ici et pas dans la fenetre : R1, et ca
--  se teste sans GTK.

package Radar_Modes with SPARK_Mode => Off is

   type Source_Kind is
     (Sensor_Serial, Capture_File, Sim_Ld2450, Sim_Profiles);

   type Activity_Kind is (Watch, Mapping, Sar_Analysis);

   function Allowed (S : Source_Kind; A : Activity_Kind) return Boolean;

   --  Le motif affiche quand Allowed est faux, "" sinon.
   function Reason (S : Source_Kind; A : Activity_Kind) return String;

   function Source_Label (S : Source_Kind) return String;
   function Activity_Label (A : Activity_Kind) return String;

   --  L'origine des donnees, pas le mode de lecture : un fichier emule reste
   --  simule quand on le rejoue. Origin ne sert que pour Capture_File.
   function Is_Simulated
     (S      : Source_Kind;
      Origin : Radar_Ld2450_Log.Capture_Origin) return Boolean;

   function Source_Text
     (S      : Source_Kind;
      Origin : Radar_Ld2450_Log.Capture_Origin) return String;

end Radar_Modes;
