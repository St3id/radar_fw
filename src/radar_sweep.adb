package body Radar_Sweep
  with SPARK_Mode => On
is

   ----------------
   -- Peak_Bin --
   ----------------

   function Peak_Bin (S : Sweep) return Bin_Index is
      Best : Bin_Index := Bin_Index'First;
   begin
      --  On parcourt toutes les cases ; on garde l'indice du maximum.
      for I in Bin_Index loop
         if S (I) > S (Best) then
            Best := I;
         end if;

         --  Invariant : a ce stade, Best est le max des cases deja vues.
         pragma Loop_Invariant
           (for all J in Bin_Index'First .. I => S (J) <= S (Best));
      end loop;

      return Best;
   end Peak_Bin;

   -------------------
   -- Peak_Distance --
   -------------------

   function Peak_Distance (S : Sweep) return Millimeters is
      Peak : constant Bin_Index := Peak_Bin (S);

      --  Chaque case couvre une tranche de distance constante.
      --  20 000 mm repartis sur 256 cases.
      Mm_Per_Bin : constant := Max_Range_Mm / Sweep_Length;
   begin
      --  Case 1 -> distance la plus proche, case 256 -> la plus lointaine.
      return Millimeters ((Integer (Peak) - 1) * Mm_Per_Bin);
   end Peak_Distance;

end Radar_Sweep;