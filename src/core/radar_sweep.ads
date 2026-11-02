--  Radar_Sweep : traitement d'un balayage radar brut, du seuil de
--  detection simple au seuil adaptatif CFAR.
--
--  C'est le coeur prouve du projet, et le seul code destine au
--  microcontrolleur : ni entrees-sorties, ni horloge, ni exception
--  propagee, afin de rester cross-compilable (voir radar_core.gpr).
--
--  Le modele de balayage est un tableau de niveaux simules par case de
--  distance ; toutes les distances logicielles sont en millimetres. Ce
--  format n'est pas le flux natif d'un capteur particulier.

package Radar_Sweep
  with SPARK_Mode => On
is

   --  Plage maximale du modele, en millimetres (20 m), pas une config capteur.
   Max_Range_Mm : constant := 20_000;

   --  Distance du modele, bornee a 0..20 m.
   type Millimeters is range 0 .. Max_Range_Mm;

   --  Un balayage est decoupe en cases de distance ("range bins").
   Sweep_Length : constant := 256;
   type Bin_Index is range 1 .. Sweep_Length;

   --  Niveau d'echo abstrait sur 12 bits dans le simulateur ; il ne decrit
   --  ni l'ADC ni l'echelle de sortie d'un capteur reel.
   type Amplitude is range 0 .. 4_095;

   --  Le balayage complet : une amplitude par case.
   type Sweep is array (Bin_Index) of Amplitude;

   --  Seuil de detection : en dessous, l'echo est considere comme du bruit
   --  et on estime qu'il n'y a pas de cible.
   Detection_Threshold : constant Amplitude := 100;

   --  Case contenant l'amplitude la plus forte (le pic = la cible detectee).
   function Peak_Bin (S : Sweep) return Bin_Index
     with Post => (for all I in Bin_Index => S (I) <= S (Peak_Bin'Result));

   --  Presence d'une cible : le pic depasse-t-il le seuil ?
   function Has_Target (S : Sweep) return Boolean;

   --  Distance simulee du debut de la tranche couverte par une case.
   --  On multiplie avant de diviser : 20_000/256 = 78,125 mm par case,
   --  tronquer d'abord (78) fausserait la distance de 110 mm en bout de
   --  portee. Ce pas de quantification ne definit pas la resolution de
   --  distance d'un radar physique. Ecrite en "expression function" : sa
   --  definition sert de contrat, le prouveur et les clients la voient.
   function Bin_Distance (B : Bin_Index) return Millimeters is
     (Millimeters ((Integer (B) - 1) * Max_Range_Mm / Sweep_Length));

   --  Conversion du pic en distance du modele.
   --  Precondition : il doit y avoir une cible, sinon la distance n'a pas
   --  de sens. Postcondition fonctionnelle : le resultat est exactement
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

   --  Cherche toutes les cases dont l'amplitude atteint le seuil.
   --  Contrat fonctionnel prouve : toute case rapportee depasse le seuil
   --  calcule par le code. Cela ne garantit ni un taux de fausse alarme
   --  physique, ni qu'une case au-dessus du seuil est une cible reelle. Une
   --  postcondition du genre "Count <= Max_Targets" ne prouverait rien :
   --  le sous-type Target_Count la garantit deja.
   function Detect_All (S : Sweep) return Detection
     with Post =>
       (for all K in 1 .. Detect_All'Result.Count =>
          S (Detect_All'Result.Targets (K)) >= Detection_Threshold);

   --  Comme Detect_All, mais regroupe les cases consecutives au-dessus du
   --  seuil en une seule cible (le sommet du groupe). Plus realiste : un
   --  objet etale sur plusieurs cases voisines = une cible, pas plusieurs.
   --  Meme contrat fonctionnel : chaque case rapportee depasse le seuil.
   function Detect_Clustered (S : Sweep) return Detection
     with Post =>
       (for all K in 1 .. Detect_Clustered'Result.Count =>
          S (Detect_Clustered'Result.Targets (K)) >= Detection_Threshold);

   --  ----- Seuil adaptatif CFAR (ARCHITECTURE.md, realisme point 2) -----
   --  Un seuil fixe ne survit pas au monde reel : trop bas, il noie le
   --  pistage de fausses alarmes ; trop haut, il rate les cibles
   --  faibles. Le modele CA-CFAR (Cell-Averaging Constant False Alarm Rate)
   --  estime ici le bruit local ; son taux de fausse alarme n'est pas calibre.

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

   --  Zone ignoree par le modele (8 cases, soit 625 mm) : les premieres
   --  cases ne sont jamais declarees cibles. Cette valeur ne represente
   --  pas une distance aveugle mesuree d'un module 24 GHz ou A121. Sur un
   --  vrai radar, les limites proches dependent du capteur et du profil ;
   --  ici, les fausses alarmes CFAR ont en plus
   --  un vice geometrique : a courte distance, tous les azimuts se
   --  retrouvent proches de l'origine, donc les fausses alarmes s'y
   --  regroupent tour apres tour et fabriquent une piste fantome
   --  persistante au pied du radar, comportement observe en simulation.
   --  Au-dela de 625 mm, deux fausses alarmes ne se regroupent que si leurs
   --  azimuts coincident : le hasard ne le refait pas deux tours de
   --  suite, et la regle M-sur-N les elimine.
   Blind_Bins : constant := 8;

   --  Detection a seuil adaptatif + regroupement des cases voisines.
   --  C'est elle que le pipeline utilise. Contrats prouves : toute
   --  case rapportee depasse le seuil CFAR calcule pour cette case et se
   --  trouve au-dela de la zone ignoree par le modele.
   function Detect_Adaptive (S : Sweep) return Detection
     with Post =>
       (for all K in 1 .. Detect_Adaptive'Result.Count =>
          Natural (S (Detect_Adaptive'Result.Targets (K)))
            >= CFAR_Threshold (S, Detect_Adaptive'Result.Targets (K))
          and then Detect_Adaptive'Result.Targets (K) > Blind_Bins);

end Radar_Sweep;
