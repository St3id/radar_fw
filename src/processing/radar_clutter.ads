with Radar_Sweep;  use Radar_Sweep;

package Radar_Clutter is

   --  Carte de CLUTTER ADAPTATIVE : memorise, direction par direction,
   --  les cases de distance occupees par l'environnement STATIQUE.
   --  En surveillance, tout echo qui retombe sur une case confirmee
   --  (a la marge pres) est supprime : ne restent que les objets
   --  MOBILES. C'est le principe du MTI des radars de veille au sol.
   --
   --  ADAPTATIVE : chaque case porte un petit compteur de confiance
   --  (2 bits) au lieu d'un simple drapeau.
   --    - Learn incremente (sature) : un echo repete devient du decor ;
   --    - Age decremente tout (a appeler periodiquement) : le decor
   --      qui disparait finit par etre oublie ;
   --    - une case n'est traitee en clutter qu'a partir de
   --      Confirm_Level observations : un mobile qui ne fait que
   --      passer (1 observation) n'empoisonne pas la carte. Revers
   --      realiste : un mobile qui se GARE finit par fondre dans le
   --      decor, comme sur un vrai radar.
   --
   --  Concu pour la cible embarquee : arithmetique simple, memoire
   --  statique bornee (~54 Ko compactee a 2 bits par case).

   --  Quantification des directions. DOIT correspondre a la grille de
   --  balayage de la source (grille par defaut du mode surveillance).
   Az_Cells : constant := 120;   --  0 .. 360 degres
   El_Cells : constant := 7;     --  -30 .. +30 degres

   El_Min_Deg : constant Float := -30.0;
   El_Max_Deg : constant Float := 30.0;

   --  Marge : une cible a moins de Guard_Bins d'une case de clutter est
   --  consideree comme du clutter (l'echo d'un mur "bave" un peu).
   Guard_Bins : constant := 2;

   --  Nombre d'observations pour qu'une case devienne du clutter.
   Confirm_Level : constant := 2;

   type Clutter_Map is private;

   --  Carte vierge (aucune direction apprise).
   procedure Clear (C : out Clutter_Map);

   --  Apprentissage : chaque cible de D renforce (sature) sa case pour
   --  la direction visee. A appeler a chaque tour pendant la
   --  calibration, puis a faible cadence en tache de fond.
   procedure Learn
     (C              : in out Clutter_Map;
      Az_Deg, El_Deg : Float;
      D              : Detection);

   --  Oubli lent : decremente toutes les cases d'un cran. A appeler
   --  periodiquement (toutes les N tours) : le decor disparu s'efface.
   procedure Age (C : in out Clutter_Map);

   --  Filtrage MTI : rend D prive de toute cible tombant sur (ou pres
   --  d')une case de clutter CONFIRMEE pour cette direction.
   function Filter
     (C              : Clutter_Map;
      Az_Deg, El_Deg : Float;
      D              : Detection) return Detection;

private

   --  Compteur de confiance par case, compacte sur 2 bits.
   type Confidence is mod 4;

   type Bin_Counts is array (Bin_Index) of Confidence with Pack;

   type Cell_Grid is
     array (0 .. Az_Cells - 1, 0 .. El_Cells - 1) of Bin_Counts;

   type Clutter_Map is record
      Cells : Cell_Grid;
   end record;

end Radar_Clutter;
