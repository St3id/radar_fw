with Radar_Source;  use Radar_Source;
with Radar_Sweep;   use Radar_Sweep;
with Radar_World;   use Radar_World;

package Radar_Sim_Source is

   --  Source SIMULEE : balaie une grille azimut x elevation (scan 3D),
   --  sur plusieurs tours ; entre chaque tour, le monde avance d'un pas.
   type Simulated_Source is new Source with private;

   function Make (Sweeps : Positive) return Simulated_Source;

   overriding
   procedure Next
     (Self      : in out Simulated_Source;
      Result    : out Measurement;
      Available : out Boolean);

   overriding
   function Has_More (Self : Simulated_Source) return Boolean;

private

   --  Grille de balayage : directions horizontales et verticales.
   Azimuth_Steps   : constant := 120;   --  azimut : tour complet
   Elevation_Steps : constant := 7;     --  elevation : de -30 a +30 deg

   type Simulated_Source is new Source with record
      Az_Step      : Natural := 0;   --  position azimut dans le tour
      El_Step      : Natural := 0;   --  position elevation dans le tour
      Current_Turn : Natural := 0;
      Max_Turns    : Positive := 1;
      Scene        : World;
   end record;

end Radar_Sim_Source;