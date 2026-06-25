package Radar_Sweep
  with SPARK_Mode => On
is

   --  Portee maximale du capteur, en millimetres (20 m).
   Max_Range_Mm : constant := 20_000;

   --  Distance physique : type borne, impossible de sortir de 0..20 m.
   type Millimeters is range 0 .. Max_Range_Mm;

   --  Un balayage est decoupe en cases de distance ("range bins").
   Sweep_Length : constant := 256;
   type Bin_Index is range 1 .. Sweep_Length;

   --  Amplitude de l'echo dans une case : valeur d'un ADC 12 bits.
   type Amplitude is range 0 .. 4_095;

   --  Le balayage complet : une amplitude par case.
   type Sweep is array (Bin_Index) of Amplitude;

   --  Seuil de detection : en dessous, l'echo est considere comme du bruit
   --  et on estime qu'il n'y a pas de cible.
   Detection_Threshold : constant Amplitude := 100;

   --  Case contenant l'amplitude la plus forte (le pic = la cible detectee).
   function Peak_Bin (S : Sweep) return Bin_Index
     with Post => (for all I in Bin_Index => S (I) <= S (Peak_Bin'Result));

   --  Y a-t-il une cible ? (le pic depasse-t-il le seuil de detection ?)
   function Has_Target (S : Sweep) return Boolean;

   --  Conversion du pic en distance physique.
   --  Precondition : il doit y avoir une cible, sinon la distance n'a pas
   --  de sens.
   function Peak_Distance (S : Sweep) return Millimeters
     with Pre  => Has_Target (S),
          Post => Peak_Distance'Result <= Max_Range_Mm;
--  ----- Detection de plusieurs cibles -----

   --  Nombre maximum de cibles qu'on accepte de rapporter.
   Max_Targets : constant := 16;

   --  Combien de cibles au plus (0 a Max_Targets).
   subtype Target_Count is Natural range 0 .. Max_Targets;

   --  Une liste de positions de cibles (les cases ou un echo depasse le seuil).
   type Target_Array is array (1 .. Max_Targets) of Bin_Index;

   --  Resultat d'une detection multiple : les cibles trouvees + leur nombre.
   type Detection is record
      Targets : Target_Array;
      Count   : Target_Count;
   end record;

   --  Cherche toutes les cases dont l'amplitude >= Detection_Threshold.
   function Detect_All (S : Sweep) return Detection
     with Post => Detect_All'Result.Count <= Max_Targets;
     
   --  Comme Detect_All, mais regroupe les cases consecutives au-dessus du
   --  seuil en UNE seule cible (le sommet du groupe). Plus realiste : un
   --  objet etale sur plusieurs cases voisines = une cible, pas plusieurs.
   function Detect_Clustered (S : Sweep) return Detection
     with Post => Detect_Clustered'Result.Count <= Max_Targets;
     
end Radar_Sweep;