with Ada.Numerics.Discrete_Random;

package body Radar_Sim is

   --  Generateur de nombres aleatoires sur le type Amplitude.
   package Random_Amplitude is
     new Ada.Numerics.Discrete_Random (Amplitude);

   Gen : Random_Amplitude.Generator;

   --------------
   -- Generate --
   --------------

   function Generate
     (Targets     : Target_List;
      Noise_Level : Amplitude := 30)
      return Sweep
   is
      Result : Sweep;
   begin
      --  1. On remplit tout le balayage de bruit de fond aleatoire,
      --     borne entre 0 et Noise_Level.
      for I in Bin_Index loop
         Result (I) := Random_Amplitude.Random (Gen) mod (Noise_Level + 1);
      end loop;

      --  2. On pose chaque cible : on ecrit sa force a sa position.
      for T of Targets loop
         Result (T.Position) := T.Strength;
      end loop;

      return Result;
   end Generate;

begin
   --  Initialise le generateur aleatoire au demarrage du paquet.
   Random_Amplitude.Reset (Gen);
end Radar_Sim;