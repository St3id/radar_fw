with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Radar_Turret_Sim is

   use Radar_Dwell;

   Sector_Deg : constant Float := Float (Sector_Degrees);

   -------------
   -- Realise --
   -------------

   function Realise (Plan : Sector_Times) return Realised_Times is
      Result : Realised_Times;

      --  Vitesse a chaque frontiere de secteur. Sans rampe, la tete prend a
      --  chaque frontiere la plus lente des deux vitesses voisines.
      Speed : array (0 .. Sector_Count) of Float;

      function Cruise (S : Sector) return Float is
        (Sector_Deg * 1.0E6 / Float (Plan (S)));

      --  La vitesse la plus haute atteignable sur un secteur depuis V.
      function Reachable (V : Float) return Float is
        (Sqrt (V * V + 2.0 * Accel_Deg_S2 * Sector_Deg));
   begin
      Speed (0) := Cruise (Sector'First);
      Speed (Sector_Count) := Cruise (Sector'Last);
      for I in 1 .. Sector_Count - 1 loop
         Speed (I) := Float'Min (Cruise (I), Cruise (I + 1));
      end loop;

      --  Deux parcours : le premier borne les accelerations, le second les
      --  freinages, qui doivent commencer AVANT un secteur lent.
      for I in 1 .. Sector_Count loop
         Speed (I) := Float'Min (Speed (I), Reachable (Speed (I - 1)));
      end loop;
      for I in reverse 0 .. Sector_Count - 1 loop
         Speed (I) := Float'Min (Speed (I), Reachable (Speed (I + 1)));
      end loop;

      for S in Sector loop
         Result (S) := 2.0 * Sector_Deg / (Speed (S - 1) + Speed (S));
      end loop;
      return Result;
   end Realise;

   ------------------
   -- Pass_Seconds --
   ------------------

   function Pass_Seconds (Times : Realised_Times) return Float is
      Total : Float := 0.0;
   begin
      for S in Sector loop
         Total := Total + Times (S);
      end loop;
      return Total;
   end Pass_Seconds;

   --------------
   -- Angle_At --
   --------------

   function Angle_At (Times : Realised_Times; Seconds : Float) return Float is
      Left : Float := Float'Max (0.0, Seconds);
   begin
      for S in Sector loop
         if Left < Times (S) then
            return Float (S - 1) * Sector_Deg
              + Sector_Deg * Left / Times (S);
         end if;
         Left := Left - Times (S);
      end loop;
      return Float (Pass_Degrees);
   end Angle_At;

end Radar_Turret_Sim;
