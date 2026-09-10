with Radar_Source;  use Radar_Source;
with Radar_Sweep;
with Radar_World;   use Radar_World;

package Radar_Sim_Source is

   --  Source SIMULEE : balaie une grille azimut x elevation (scan 3D),
   --  sur plusieurs tours ; entre chaque tour, le monde avance d'un pas.
   type Simulated_Source is new Source with private;

   --  Mode SURVEILLANCE : plusieurs tours d'un monde d'objets mobiles.
   --  See_Room = True ajoute les murs de la piece a la scene : c'est le
   --  cas realiste (mode live), ou il faudra une carte de clutter pour
   --  distinguer les mobiles du decor.
   function Make
     (Sweeps   : Positive;
      See_Room : Boolean := False) return Simulated_Source;

   --  Nombre de mesures qui composent UN tour complet de cette source
   --  (tous les azimuts x toutes les elevations).
   overriding
   function Per_Turn (Self : Simulated_Source) return Positive;

   --  Nombre de pas d'une grille de balayage (au moins 2 : les formules
   --  d'interpolation divisent par Steps - 1).
   subtype Grid_Steps is Positive range 2 .. 1_024;

   --  Mode CARTOGRAPHIE : UN tour meticuleux d'un monde statique (les
   --  murs de la piece, sans objets mobiles), avec une grille fine.
   --  Meme interface, meme chaine de traitement : seul le contenu de la
   --  scene et la finesse du balayage changent.
   function Make_Room_Scan
     (Az_Steps : Grid_Steps := 180;
      El_Steps : Grid_Steps := 24) return Simulated_Source;

   overriding
   procedure Next
     (Self      : in out Simulated_Source;
      Result    : out Measurement;
      Available : out Boolean);

   overriding
   function Has_More (Self : Simulated_Source) return Boolean;

private

   --  Grille par defaut du mode surveillance : rapide (peu de pas en
   --  elevation) pour privilegier la cadence de rafraichissement.
   Default_Azimuth_Steps   : constant := 120;  --  azimut : tour complet
   Default_Elevation_Steps : constant := 7;    --  de -30 a +30 deg

   --  ----- Realisme des cibles (ARCHITECTURE.md, realisme point 1) ----
   --  Une cible reelle n'est pas un point : c'est un ensemble de
   --  reflecteurs (torse, membres...) dont l'echo FLUCTUE d'un tour a
   --  l'autre selon l'orientation (modeles de Swerling), avec de vrais
   --  trous de detection. Chaque objet est donc simule par
   --  Scatter_Count reflecteurs dont l'amplitude est retiree au sort a
   --  chaque tour (0 = eteint ce tour-ci).
   Scatter_Count : constant := 4;

   type Scatter_Amps is
     array (1 .. Max_Objects, 1 .. Scatter_Count) of Radar_Sweep.Amplitude;

   --  Multitrajet (point 5) : ce tour-ci, l'objet produit-il en plus un
   --  echo FANTOME derriere le mur (signal rebondi mur -> cible) ?
   type Object_Flags is array (1 .. Max_Objects) of Boolean;

   type Simulated_Source is new Source with record
      Az_Step      : Natural := 0;   --  position azimut dans le tour
      El_Step      : Natural := 0;   --  position elevation dans le tour
      Current_Turn : Natural := 0;
      Max_Turns    : Positive := 1;

      --  Finesse de la grille de balayage (fixee par le constructeur).
      Az_Steps     : Grid_Steps := Default_Azimuth_Steps;
      El_Steps     : Grid_Steps := Default_Elevation_Steps;

      --  La source percoit-elle les murs de la piece ? (cartographie)
      See_Room     : Boolean := False;

      --  Amplitudes des reflecteurs pour le tour en cours (retirees au
      --  sort a chaque nouveau tour ; 0 = reflecteur eteint ce tour).
      Echoes       : Scatter_Amps := (others => (others => 0));

      --  Fantomes multitrajet actifs ce tour-ci.
      Ghosting     : Object_Flags := (others => False);

      Scene        : World;
   end record;

end Radar_Sim_Source;