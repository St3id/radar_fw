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

   --  Case contenant l'amplitude la plus forte (le pic = la cible detectee).
   function Peak_Bin (S : Sweep) return Bin_Index
     with Post => (for all I in Bin_Index => S (I) <= S (Peak_Bin'Result));

   --  Conversion du pic en distance physique.
   function Peak_Distance (S : Sweep) return Millimeters
     with Post => Peak_Distance'Result <= Max_Range_Mm;

end Radar_Sweep;