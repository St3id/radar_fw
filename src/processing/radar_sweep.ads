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

   --  Distance physique du debut de la tranche couverte par une case.
   --  On multiplie AVANT de diviser : 20_000/256 = 78,125 mm par case,
   --  tronquer d'abord (78) fausserait la distance de 110 mm en bout de
   --  portee. Ecrite en "expression function" : sa definition sert de
   --  contrat, le prouveur et les clients la voient.
   function Bin_Distance (B : Bin_Index) return Millimeters is
     (Millimeters ((Integer (B) - 1) * Max_Range_Mm / Sweep_Length));

   --  Conversion du pic en distance physique.
   --  Precondition : il doit y avoir une cible, sinon la distance n'a pas
   --  de sens. Postcondition FONCTIONNELLE : le resultat est exactement
   --  la distance de la case du pic (pas juste "dans les bornes", ce que
   --  le type garantit deja tout seul).
   function Peak_Distance (S : Sweep) return Millimeters
     with Pre  => Has_Target (S),
          Post => Peak_Distance'Result = Bin_Distance (Peak_Bin (S));
--  ----- Detection de plusieurs cibles -----

   --  Nombre maximum de cibles qu'on accepte de rapporter.
   Max_Targets : constant := 16;

   --  Combien de cibles au plus (0 a Max_Targets).
   subtype Target_Count is Natural range 0 .. Max_Targets;

   --  Liste de positions de cibles (cases ou un echo depasse le seuil).
   type Target_Array is array (1 .. Max_Targets) of Bin_Index;

   --  Resultat d'une detection multiple : les cibles trouvees + leur nombre.
   type Detection is record
      Targets : Target_Array;
      Count   : Target_Count;
   end record;

   --  Cherche toutes les cases dont l'amplitude >= Detection_Threshold.
   --  Contrat fonctionnel prouve : PAS DE FAUSSE ALARME - toute cible
   --  rapportee depasse reellement le seuil. (L'ancien contrat
   --  "Count <= Max_Targets" etait deja garanti par le sous-type
   --  Target_Count : il ne prouvait rien.)
   function Detect_All (S : Sweep) return Detection
     with Post =>
       (for all K in 1 .. Detect_All'Result.Count =>
          S (Detect_All'Result.Targets (K)) >= Detection_Threshold);

   --  Comme Detect_All, mais regroupe les cases consecutives au-dessus du
   --  seuil en UNE seule cible (le sommet du groupe). Plus realiste : un
   --  objet etale sur plusieurs cases voisines = une cible, pas plusieurs.
   --  Meme contrat fonctionnel : pas de fausse alarme.
   function Detect_Clustered (S : Sweep) return Detection
     with Post =>
       (for all K in 1 .. Detect_Clustered'Result.Count =>
          S (Detect_Clustered'Result.Targets (K)) >= Detection_Threshold);

   --  ----- Seuil adaptatif CFAR (ANALYSE_REALISME.md, point 2) -----
   --  Un seuil fixe ne survit pas au monde reel : trop bas, il noie le
   --  pistage de fausses alarmes ; trop haut, il rate les cibles
   --  faibles. CA-CFAR (Cell-Averaging Constant False Alarm Rate) : le
   --  seuil de CHAQUE case = bruit moyen de ses voisines x un facteur.

   CFAR_Window : constant := 8;  --  cases moyennees de chaque cote
   CFAR_Guard  : constant := 2;  --  cases ignorees autour de la testee
   CFAR_Factor : constant := 4;  --  seuil = 4 x bruit local (~12 dB)

   --  Plancher absolu : en zone parfaitement silencieuse, le seuil ne
   --  descend pas en dessous (sinon le moindre souffle detecterait).
   CFAR_Floor : constant Natural := 60;

   --  Bruit local autour d'une case : moyenne des cases voisines dans
   --  la fenetre, hors cases de garde, bornes du balayage respectees.
   function Noise_Estimate (S : Sweep; B : Bin_Index) return Amplitude;

   --  Seuil CFAR d'une case donnee.
   function CFAR_Threshold (S : Sweep; B : Bin_Index) return Natural is
     (Natural'Max (CFAR_Floor,
                   CFAR_Factor * Natural (Noise_Estimate (S, B))));

   --  Detection a seuil ADAPTATIF + regroupement des cases voisines.
   --  C'est elle que le pipeline utilise. Contrat prouve : toute cible
   --  rapportee depasse le seuil CFAR de SA case (pas de fausse alarme
   --  par rapport au bruit local).
   function Detect_Adaptive (S : Sweep) return Detection
     with Post =>
       (for all K in 1 .. Detect_Adaptive'Result.Count =>
          Natural (S (Detect_Adaptive'Result.Targets (K)))
            >= CFAR_Threshold (S, Detect_Adaptive'Result.Targets (K)));

end Radar_Sweep;