with Radar_Sweep;  use Radar_Sweep;

package Radar_Sim is

   --  Une cible simulee : sa position (case) et sa force (amplitude du pic).
   type Target is record
      Position : Bin_Index;
      Strength : Amplitude;
   end record;

   --  Une liste de cibles a placer dans la scene.
   type Target_List is array (Positive range <>) of Target;

   --  Genere un balayage : bruit de fond aleatoire + les cibles demandees.
   --  Noise_Level fixe l'amplitude max du bruit (sous le seuil de detection
   --  si on veut des cibles bien nettes).
   function Generate
     (Targets     : Target_List;
      Noise_Level : Amplitude := 20)
      return Sweep;

end Radar_Sim;