with Radar_Source;  use Radar_Source;
with Radar_Sweep;   use Radar_Sweep;
with Radar_World;   use Radar_World;

package Radar_Sim_Source is

   --  Source SIMULEE : implemente le contrat Radar_Source.Source.
   --  Elle balaie l'espace direction par direction et fabrique les echos
   --  a partir des objets reels du monde simule (la verite terrain).
   type Simulated_Source is new Source with private;

   --  Cree une source simulee prete a balayer.
   function Make return Simulated_Source;

   --  Implementations OBLIGATOIRES du contrat :
   overriding
   procedure Next
     (Self      : in out Simulated_Source;
      Result    : out Measurement;
      Available : out Boolean);

   overriding
   function Has_More (Self : Simulated_Source) return Boolean;

private

   --  Nombre de directions a balayer (azimut) pour un tour complet.
   Total_Steps : constant := 120;

   type Simulated_Source is new Source with record
      Step  : Natural := 0;        --  ou en est-on dans le balayage
      Scene : World;               --  le monde reel (verite terrain)
   end record;

end Radar_Sim_Source;