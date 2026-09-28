with Radar_Source; use Radar_Source;

--  Radar_Planar_Source : entree des capteurs qui ne mesurent qu'une
--  position PLANAIRE, comme le LD2450 (x lateral, y vers l'avant, pas
--  d'altitude).
--
--  C'est le contrat 2D qu'exige la regle R3. Un tel capteur n'entre ni
--  par Radar_Source (il ne livre pas de profil de distance), ni par
--  Radar_Target_Source (sa Frame est 3D, et poser z = 0 ferait passer
--  une convention de dessin pour une mesure d'altitude : ARCHITECTURE.md,
--  section 1.7).
--
--  Un rapport = UN capteur a UN instant, dans le repere de CE capteur.
--  Le passage au repere commun (pose calibree de chaque module d'une
--  couronne) et la fusion de plusieurs capteurs sont une etape
--  d'orchestration, pas une propriete de ce contrat.

package Radar_Planar_Source is

   --  Une detection planaire, dans le repere du capteur, en mm : X
   --  lateral, Y vers l'avant (l'axe du capteur).
   --
   --  Ce que ces nombres valent physiquement : le module mesure une
   --  distance OBLIQUE et un angle horizontal, puis en deduit X et Y. Une
   --  cible plus haute ou plus basse que lui parait donc plus loin qu'elle
   --  n'est a l'horizontale : a 1 m devant et 1 m de denivele, Y vaut
   --  1,41 m. Modele attendu d'un capteur a deux antennes de reception
   --  horizontales, a confirmer sur le module reel.
   --
   --  Speed_Mm_S : la vitesse radiale mesuree par le module (effet
   --  Doppler), convertie en mm/s. Son signe est celui du module ; quel
   --  sens il designe reste a verifier sur le materiel.
   type Detection_2D is record
      X_Mm       : Float := 0.0;
      Y_Mm       : Float := 0.0;
      Speed_Mm_S : Float := 0.0;
   end record;

   --  8 : le LD2450 rend au plus 3 cibles ; la marge couvre un module plus
   --  riche sans changer le contrat.
   Max_Planar_Detections : constant := 8;

   subtype Planar_Count is Natural range 0 .. Max_Planar_Detections;

   type Detection_2D_List is array (1 .. Max_Planar_Detections)
     of Detection_2D;

   --  Ce qu'un capteur planaire a vu a un instant.
   --
   --  Stamp est l'heure de CAPTURE, pas celle de lecture : c'est elle qui
   --  donnera le dt du pistage. Sensor dit QUEL module a vu, pour la
   --  fusion d'une couronne. Min_Range_Mm dit jusqu'ou le capteur etait
   --  aveugle, comme Frame.Min_Range dans Radar_Detect : en deca, une
   --  absence de cible ne prouve pas qu'il n'y a rien.
   type Planar_Report is record
      Items        : Detection_2D_List;
      Count        : Planar_Count := 0;
      Stamp        : Time_Ms      := 0;
      Sensor       : Positive     := 1;
      Min_Range_Mm : Float        := 0.0;
   end record;

   type Planar_Source is interface;

   --  Fournit le prochain rapport. Un rapport vide est valide : il dit
   --  "rien vu a cet instant" et fait avancer le temps du pistage.
   --  Available = False : pas de rapport disponible (source epuisee, ou
   --  module muet) ; Result n'a alors aucun sens.
   procedure Next_Report
     (Self      : in out Planar_Source;
      Result    : out Planar_Report;
      Available : out Boolean) is abstract;

   --  Vrai tant que la source peut encore produire des rapports. Une
   --  source materielle continue peut repondre toujours True.
   function Has_More (Self : Planar_Source) return Boolean is abstract;

end Radar_Planar_Source;
