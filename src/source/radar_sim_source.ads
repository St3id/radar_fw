with Radar_Source;  use Radar_Source;
with Radar_Sweep;   use Radar_Sweep;
with Radar_World;   use Radar_World;

package Radar_Sim_Source is

   --  Source SIMULEE : implemente le contrat Radar_Source.Source.
   --  Elle effectue plusieurs TOURS ; entre chaque tour, le monde avance
   --  d'un pas de temps (les objets se deplacent).
   type Simulated_Source is new Source with private;

   --  Cree une source simulee qui effectuera Sweeps tours complets.
   function Make (Sweeps : Positive) return Simulated_Source;

   overriding
   procedure Next
     (Self      : in out Simulated_Source;
      Result    : out Measurement;
      Available : out Boolean);

   overriding
   function Has_More (Self : Simulated_Source) return Boolean;

private

   --  Nombre de directions par tour (azimut).
   Total_Steps : constant := 120;

   type Simulated_Source is new Source with record
      Step         : Natural := 0;   --  direction courante dans le tour
      Current_Turn : Natural := 0;   --  numero du tour en cours
      Max_Turns    : Positive := 1;  --  nombre total de tours a faire
      Scene        : World;          --  le monde reel (verite terrain)
   end record;

end Radar_Sim_Source;