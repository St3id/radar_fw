package body Radar_Sweep
  with SPARK_Mode => On
is

   --------------
   -- Peak_Bin --
   --------------

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

   ----------------
   -- Has_Target --
   ----------------

   function Has_Target (S : Sweep) return Boolean is
   begin
      --  Une cible existe si le pic depasse le seuil de detection.
      return S (Peak_Bin (S)) >= Detection_Threshold;
   end Has_Target;

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

----------------
   -- Detect_All --
   ----------------

   function Detect_All (S : Sweep) return Detection is
      Result : Detection := (Targets => (others => Bin_Index'First),
                             Count   => 0);
   begin
      for I in Bin_Index loop
         --  Si l'echo depasse le seuil ET qu'il reste de la place, on note.
         if S (I) >= Detection_Threshold and then Result.Count < Max_Targets
         then
            Result.Count := Result.Count + 1;
            Result.Targets (Result.Count) := I;
         end if;

         --  Invariant : le compte ne depasse jamais le maximum.
         pragma Loop_Invariant (Result.Count <= Max_Targets);
      end loop;

      return Result;
   end Detect_All;
   
----------------------
   -- Detect_Clustered --
   ----------------------

   function Detect_Clustered (S : Sweep) return Detection is
      Result    : Detection := (Targets => (others => Bin_Index'First),
                                Count   => 0);
      In_Group  : Boolean   := False;        --  sommes-nous dans un echo ?
      Best_Pos  : Bin_Index := Bin_Index'First;  --  sommet du groupe courant
      Best_Amp  : Amplitude := 0;
   begin
      for I in Bin_Index loop
         if S (I) >= Detection_Threshold then
            --  Case au-dessus du seuil : on est dans un groupe.
            if not In_Group then
               --  Debut d'un nouveau groupe.
               In_Group := True;
               Best_Pos := I;
               Best_Amp := S (I);
            elsif S (I) > Best_Amp then
               --  On suit le sommet du groupe en cours.
               Best_Pos := I;
               Best_Amp := S (I);
            end if;
         else
            --  Case sous le seuil : si on sortait d'un groupe, on l'enregistre.
            if In_Group and then Result.Count < Max_Targets then
               Result.Count := Result.Count + 1;
               Result.Targets (Result.Count) := Best_Pos;
            end if;
            In_Group := False;
         end if;

         pragma Loop_Invariant (Result.Count <= Max_Targets);
      end loop;

      --  Cas particulier : un groupe qui va jusqu'a la toute derniere case.
      if In_Group and then Result.Count < Max_Targets then
         Result.Count := Result.Count + 1;
         Result.Targets (Result.Count) := Best_Pos;
      end if;

      return Result;
   end Detect_Clustered;

end Radar_Sweep;