with Radar_Sweep;  use Radar_Sweep;

--  Radar_Clutter : la carte de clutter, qui memorise direction par
--  direction les cases de distance occupees par l'environnement statique.
--
--  En surveillance, tout echo retombant sur une case confirmee, a la
--  marge pres, est supprime : ne restent que les objets mobiles. C'est le
--  principe du MTI (Moving Target Indication) des radars de veille au
--  sol.
--
--  La carte est adaptative : chaque case porte un compteur de confiance
--  sur 2 bits plutot qu'un simple drapeau.
--    - Learn incremente en saturant : un echo repete devient du decor ;
--    - Age decremente l'ensemble, a appeler periodiquement : le decor qui
--      disparait finit par etre oublie ;
--    - une case ne compte comme clutter qu'a partir de Confirm_Level
--      observations, si bien qu'un mobile qui ne fait que passer, vu une
--      seule fois, n'empoisonne pas la carte.
--  Revers assume et conforme au comportement d'un vrai radar : un mobile
--  qui se gare finit par fondre dans le decor.
--
--  Concu pour la cible embarquee : arithmetique entiere, memoire statique
--  bornee (environ 54 Ko, compactee a 2 bits par case).

package Radar_Clutter is

   --  Quantification des directions. Elle doit correspondre a la grille
   --  de balayage de la source, convention que le compilateur ne verifie
   --  pas : c'est une dette connue du projet.
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
   --  d')une case de clutter confirmee pour cette direction.
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
