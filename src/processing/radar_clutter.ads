with Radar_Sweep;  use Radar_Sweep;

package Radar_Clutter is

   --  Carte de CLUTTER : memorise, direction par direction, les cases
   --  de distance occupees par l'environnement STATIQUE (murs, meubles).
   --  En surveillance, tout echo qui retombe sur une case memorisee
   --  (a la marge pres) est supprime : ne restent que les objets
   --  MOBILES. C'est le principe du MTI (Moving Target Indication) par
   --  carte de clutter des radars de veille au sol.
   --
   --  Ce paquet est concu pour la cible embarquee : arithmetique simple,
   --  memoire statique bornee (~27 Ko une fois la carte compactee).

   --  Quantification des directions. DOIT correspondre a la grille de
   --  balayage de la source (grille par defaut du mode surveillance).
   Az_Cells : constant := 120;   --  0 .. 360 degres
   El_Cells : constant := 7;     --  -30 .. +30 degres

   El_Min_Deg : constant Float := -30.0;
   El_Max_Deg : constant Float := 30.0;

   --  Marge : une cible a moins de Guard_Bins d'une case de clutter est
   --  consideree comme du clutter (l'echo d'un mur "bave" un peu).
   Guard_Bins : constant := 2;

   type Clutter_Map is private;

   --  Carte vierge (aucune direction apprise).
   procedure Clear (C : out Clutter_Map);

   --  Apprentissage : memorise les cibles de D comme decor statique
   --  pour la direction visee. A appeler pendant un tour ou la scene
   --  est supposee immobile (ou en continu, a faible cadence, pour
   --  suivre les changements lents du decor).
   procedure Learn
     (C              : in out Clutter_Map;
      Az_Deg, El_Deg : Float;
      D              : Detection);

   --  Filtrage MTI : rend D prive de toute cible tombant sur (ou pres
   --  d')une case de clutter apprise pour cette direction.
   function Filter
     (C              : Clutter_Map;
      Az_Deg, El_Deg : Float;
      D              : Detection) return Detection;

private

   type Bin_Flags is array (Bin_Index) of Boolean with Pack;

   type Cell_Grid is
     array (0 .. Az_Cells - 1, 0 .. El_Cells - 1) of Bin_Flags;

   type Clutter_Map is record
      Cells : Cell_Grid;
   end record;

end Radar_Clutter;
