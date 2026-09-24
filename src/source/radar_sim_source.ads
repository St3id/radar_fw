with Radar_Source;  use Radar_Source;
with Radar_Sweep;
with Radar_World;   use Radar_World;

--  Radar_Sim_Source : la source simulee, qui balaie une grille azimut par
--  elevation et fait avancer le monde d'un pas entre deux tours.
--
--  Elle n'est pas un bouche-trou en attendant le materiel : c'est le banc
--  de test du projet, et elle le restera. Sa graine aleatoire est fixe,
--  donc un defaut de detection ou de pistage se rejoue a l'identique,
--  autant de fois qu'il le faut, sans rebrancher quoi que ce soit.
--
--  Les imperfections qu'elle simule (bruit, echos fluctuants, trous de
--  detection, fantomes multitrajet, murs speculaires et coins brillants)
--  sont decrites dans documentation/public/ARCHITECTURE.md, section 1.

package Radar_Sim_Source is

   type Simulated_Source is new Source with private;

   --  Mode surveillance : plusieurs tours d'un monde d'objets mobiles.
   --  See_Room = True ajoute les murs de la piece a la scene : c'est le
   --  cas realiste (mode live), ou il faudra une carte de clutter pour
   --  distinguer les mobiles du decor.
   function Make
     (Sweeps   : Positive;
      See_Room : Boolean := False) return Simulated_Source;

   --  Nombre de mesures qui composent un tour complet de cette source
   --  (tous les azimuts x toutes les elevations).
   overriding
   function Per_Turn (Self : Simulated_Source) return Positive;

   overriding
   function Per_Azimuth (Self : Simulated_Source) return Positive;

   --  Nombre de pas d'une grille de balayage (au moins 2 : les formules
   --  d'interpolation divisent par Steps - 1).
   subtype Grid_Steps is Positive range 2 .. 1_024;

   --  Mode cartographie : un tour meticuleux d'un monde statique (les
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

   --  ----- Realisme des cibles (ARCHITECTURE.md, realisme point 1) -----
   --  Une cible reelle n'est pas un point : c'est un ensemble de
   --  reflecteurs (torse, membres...) dont le niveau fluctue d'un tour a
   --  l'autre. Le tirage uniforme s'inspire du fading Swerling, sans en
   --  reprendre la loi statistique. Chaque objet est donc simule par
   --  Scatter_Count reflecteurs dont l'amplitude est retiree au sort a
   --  chaque tour (0 = eteint ce tour-ci).
   Scatter_Count : constant := 4;

   --  Duree simulee dune mesure. Avec la grille de veille par defaut
   --  (120 x 7 = 840 mesures), un tour dure donc 840 ms - proche des
   --  800 ms que le mode live utilisait en dur avant la base de temps.
   Default_Ms_Per_Step : constant Time_Ms := 1;

   type Scatter_Amps is
     array (1 .. Max_Objects, 1 .. Scatter_Count) of Radar_Sweep.Amplitude;

   --  Multitrajet (point 5) : ce tour-ci, l'objet produit-il en plus un
   --  echo fantome derriere le mur (signal rebondi mur -> cible) ?
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

      --  Horloge VIRTUELLE : avancee de Ms_Per_Step a chaque mesure
      --  rendue. Volontairement pas l horloge reelle, sinon deux
      --  executions de la meme graine ne donneraient plus les memes
      --  horodatages et le banc de test cesserait d etre reproductible
      --  (regle R4).
      Clock        : Time_Ms := 0;
      Ms_Per_Step  : Time_Ms := Default_Ms_Per_Step;

      Scene        : World;
   end record;

end Radar_Sim_Source;
