--  Corps de Radar_Sweep. Les boucles portent des invariants explicites :
--  ce sont eux qui permettent au prouveur d'etablir les postconditions
--  fonctionnelles, et non la seule absence d'erreur d'execution.

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
   begin
      --  Case 1 -> distance la plus proche, case 256 -> la plus lointaine.
      --  Le calcul lui-meme vit dans Bin_Distance (partage avec les
      --  clients qui convertissent d'autres cases que le pic).
      return Bin_Distance (Peak_Bin (S));
   end Peak_Distance;

   ----------------
   -- Detect_All --
   ----------------

   function Detect_All (S : Sweep) return Detection is
      Result : Detection := (Targets => (others => Bin_Index'First),
                             Count   => 0);
   begin
      for I in Bin_Index loop
         --  Si l'echo depasse le seuil et qu'il reste de la place, on note.
         if S (I) >= Detection_Threshold and then Result.Count < Max_Targets
         then
            Result.Count := Result.Count + 1;
            Result.Targets (Result.Count) := I;
         end if;

         --  Invariants : le compte reste borne, et tout ce qui a ete
         --  enregistre jusqu'ici depasse reellement le seuil (c'est ce
         --  second invariant qui porte la postcondition fonctionnelle).
         pragma Loop_Invariant (Result.Count <= Max_Targets);
         pragma Loop_Invariant
           (for all K in 1 .. Result.Count =>
              S (Result.Targets (K)) >= Detection_Threshold);
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
            --  Sous le seuil : si on sortait d'un groupe, on l'enregistre.
            if In_Group and then Result.Count < Max_Targets then
               Result.Count := Result.Count + 1;
               Result.Targets (Result.Count) := Best_Pos;
            end if;
            In_Group := False;
         end if;

         pragma Loop_Invariant (Result.Count <= Max_Targets);
         --  Si on est dans un groupe, son sommet depasse le seuil : c'est
         --  ce qui garantit qu'on n'enregistrera jamais une fausse alarme.
         pragma Loop_Invariant
           (if In_Group then S (Best_Pos) >= Detection_Threshold);
         pragma Loop_Invariant
           (for all K in 1 .. Result.Count =>
              S (Result.Targets (K)) >= Detection_Threshold);
      end loop;

      --  Cas particulier : un groupe qui va jusqu'a la toute derniere case.
      if In_Group and then Result.Count < Max_Targets then
         Result.Count := Result.Count + 1;
         Result.Targets (Result.Count) := Best_Pos;
      end if;

      return Result;
   end Detect_Clustered;

   --------------------
   -- Noise_Estimate --
   --------------------

   function Noise_Estimate (S : Sweep; B : Bin_Index) return Amplitude is
      --  Deux fenetres : avant et apres la case testee, en sautant les
      --  cases de garde (l'echo d'une vraie cible "bave" sur elles et
      --  fausserait l'estimation du bruit).
      Lo1 : constant Integer := Integer (B) - CFAR_Guard - CFAR_Window;
      Hi1 : constant Integer := Integer (B) - CFAR_Guard - 1;
      Lo2 : constant Integer := Integer (B) + CFAR_Guard + 1;
      Hi2 : constant Integer := Integer (B) + CFAR_Guard + CFAR_Window;

      Sum   : Natural := 0;
      Cells : Natural := 0;
   begin
      for I in Lo1 .. Hi1 loop
         if I >= Integer (Bin_Index'First)
           and then I <= Integer (Bin_Index'Last)
         then
            Sum   := Sum + Natural (S (Bin_Index (I)));
            Cells := Cells + 1;
         end if;

         pragma Loop_Invariant (Cells <= Natural (I - Lo1 + 1));
         pragma Loop_Invariant (Cells <= CFAR_Window);
         pragma Loop_Invariant (Sum <= Cells * Natural (Amplitude'Last));
      end loop;

      for I in Lo2 .. Hi2 loop
         if I >= Integer (Bin_Index'First)
           and then I <= Integer (Bin_Index'Last)
         then
            Sum   := Sum + Natural (S (Bin_Index (I)));
            Cells := Cells + 1;
         end if;

         pragma Loop_Invariant (Cells <= CFAR_Window + Natural (I - Lo2 + 1));
         pragma Loop_Invariant (Cells <= 2 * CFAR_Window);
         pragma Loop_Invariant (Sum <= Cells * Natural (Amplitude'Last));
      end loop;

      --  Au moins une fenetre existe toujours (le balayage fait 256
      --  cases, la fenetre 8) ; ce garde-fou couvre le cas theorique.
      if Cells = 0 then
         return Amplitude'Last;
      end if;

      --  Sum <= Cells * Amplitude'Last donc la moyenne tient dans le
      --  type ; la borne defensive rend ce fait trivial a prouver (et
      --  c'est le style attendu en embarque critique : jamais de
      --  conversion non gardee).
      declare
         Avg : constant Natural := Sum / Cells;
      begin
         if Avg > Natural (Amplitude'Last) then
            return Amplitude'Last;
         end if;
         return Amplitude (Avg);
      end;
   end Noise_Estimate;

   ---------------------
   -- Detect_Adaptive --
   ---------------------

   function Detect_Adaptive (S : Sweep) return Detection is
      Result   : Detection := (Targets => (others => Bin_Index'First),
                               Count   => 0);
      In_Group : Boolean   := False;
      Best_Pos : Bin_Index := Bin_Index'First;
      Best_Amp : Amplitude := 0;
   begin
      --  Meme regroupement que Detect_Clustered, mais chaque case est
      --  comparee a son seuil CFAR au lieu d'un seuil global fixe.
      --  Les cases de la distance aveugle ne sont jamais des cibles.
      for I in Bin_Index loop
         if I > Blind_Bins
           and then Natural (S (I)) >= CFAR_Threshold (S, I)
         then
            if not In_Group then
               In_Group := True;
               Best_Pos := I;
               Best_Amp := S (I);
            elsif S (I) > Best_Amp then
               Best_Pos := I;
               Best_Amp := S (I);
            end if;
         else
            if In_Group and then Result.Count < Max_Targets then
               Result.Count := Result.Count + 1;
               Result.Targets (Result.Count) := Best_Pos;
            end if;
            In_Group := False;
         end if;

         pragma Loop_Invariant (Result.Count <= Max_Targets);
         pragma Loop_Invariant
           (if In_Group
            then Natural (S (Best_Pos)) >= CFAR_Threshold (S, Best_Pos)
                 and then Best_Pos > Blind_Bins);
         pragma Loop_Invariant
           (for all K in 1 .. Result.Count =>
              Natural (S (Result.Targets (K)))
                >= CFAR_Threshold (S, Result.Targets (K))
              and then Result.Targets (K) > Blind_Bins);
      end loop;

      if In_Group and then Result.Count < Max_Targets then
         Result.Count := Result.Count + 1;
         Result.Targets (Result.Count) := Best_Pos;
      end if;

      return Result;
   end Detect_Adaptive;

end Radar_Sweep;
