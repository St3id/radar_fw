with Radar_Source;  use Radar_Source;
with Radar_World;   use Radar_World;

package Radar_Sim_Source is

   --  Source SIMULEE : balaie une grille azimut x elevation (scan 3D),
   --  sur plusieurs tours ; entre chaque tour, le monde avance d'un pas.
   type Simulated_Source is new Source with private;

   --  Mode SURVEILLANCE : plusieurs tours d'un monde d'objets mobiles.
   function Make (Sweeps : Positive) return Simulated_Source;

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

      Scene        : World;
   end record;

end Radar_Sim_Source;