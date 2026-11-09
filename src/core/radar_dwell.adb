--  Corps de Radar_Dwell. Les sommes se prouvent par recurrence : un lemme
--  ghost n'est que du raisonnement, il disparait du code executable.

package body Radar_Dwell
  with SPARK_Mode => On
is

   --  Modifier un seul secteur change la somme de ce seul ecart, a partir de
   --  ce secteur.
   procedure Lemma_Bump
     (Before, After : Sector_Times;
      Changed       : Sector;
      Amount        : Natural;
      Last          : Natural)
     with
       Ghost,
       Pre                =>
         Last <= Sector_Count
         and then Amount <= Bonus_Us
         and then After (Changed) = Before (Changed) + Amount
         and then
         (for all S in Sector =>
            (if S /= Changed then After (S) = Before (S))),
       Post               =>
         Sum_To (After, Last)
           = Sum_To (Before, Last)
             + (if Changed <= Last then Amount else 0),
       Subprogram_Variant => (Decreases => Last)
   is
   begin
      if Last > 0 then
         Lemma_Bump (Before, After, Changed, Amount, Last - 1);
      end if;
   end Lemma_Bump;

   --  La somme d'un plan uniforme. Deux lemmes aux valeurs constantes plutot
   --  qu'un seul parametre : le prouveur reste dans l'arithmetique lineaire.
   procedure Lemma_Flat_Min (Times : Sector_Times; Last : Natural)
     with
       Ghost,
       Pre                =>
         Last <= Sector_Count
         and then (for all S in Sector => Times (S) = Min_Sector_Us),
       Post               => Sum_To (Times, Last) = Last * Min_Sector_Us,
       Subprogram_Variant => (Decreases => Last)
   is
   begin
      if Last > 0 then
         Lemma_Flat_Min (Times, Last - 1);
      end if;
   end Lemma_Flat_Min;

   procedure Lemma_Flat_Nominal (Times : Sector_Times; Last : Natural)
     with
       Ghost,
       Pre                =>
         Last <= Sector_Count
         and then (for all S in Sector => Times (S) = Nominal_Sector_Us),
       Post               => Sum_To (Times, Last) = Last * Nominal_Sector_Us,
       Subprogram_Variant => (Decreases => Last)
   is
   begin
      if Last > 0 then
         Lemma_Flat_Nominal (Times, Last - 1);
      end if;
   end Lemma_Flat_Nominal;

   --  Isole la copie ghost du plan : GNATprove refuse un tableau declare dans
   --  le corps d'une boucle, avant son invariant.
   procedure Bump (Times : in out Sector_Times; S : Sector; Amount : Natural)
     with
       Pre  => Amount <= Bonus_Us and then Times (S) + Amount <= Pass_Us,
       Post =>
         Times (S) = Times'Old (S) + Amount
         and then
         (for all K in Sector =>
            (if K /= S then Times (K) = Times'Old (K)))
         and then
         Sum_To (Times, Sector_Count)
           = Sum_To (Times'Old, Sector_Count) + Amount
   is
      Previous : constant Sector_Times := Times with Ghost;
   begin
      Times (S) := Times (S) + Amount;
      Lemma_Bump (Previous, Times, S, Amount, Sector_Count);
   end Bump;

   ---------------
   -- Add_Share --
   ---------------

   procedure Add_Share
     (Times  : in out Sector_Times;
      Cue    : Sector;
      Amount : Natural)
   is
      First  : constant Sector := Window_First (Cue);
      Last   : constant Sector := Window_Last (Cue);
      Before : constant Sector_Times := Times with Ghost;
      Given  : Natural := 0;
   begin
      --  Diviser ce qui reste par les secteurs restants : le dernier secteur
      --  recoit donc tout le reliquat, et rien ne se perd en arrondi.
      for S in First .. Last loop
         declare
            Part : constant Natural := (Amount - Given) / (Last - S + 1);
         begin
            Bump (Times, S, Part);
            Given := Given + Part;
         end;

         pragma Loop_Invariant (Given <= Amount);
         pragma Loop_Invariant (if S = Last then Given = Amount);
         pragma Loop_Invariant
           (Sum_To (Times, Sector_Count)
              = Sum_To (Before, Sector_Count) + Given);
         pragma Loop_Invariant
           (for all K in Sector =>
              (if K in First .. S
               then Times (K) in Before (K) .. Before (K) + Given
               else Times (K) = Before (K)));
      end loop;
   end Add_Share;

   -----------
   -- Build --
   -----------

   procedure Build
     (Cues  : Cue_List;
      Count : Cue_Count;
      Plan  : out Sector_Times)
   is
   begin
      if Count = 0 then
         Plan := (others => Nominal_Sector_Us);
         Lemma_Flat_Nominal (Plan, Sector_Count);
         return;
      end if;

      Plan := (others => Min_Sector_Us);
      Lemma_Flat_Min (Plan, Sector_Count);

      declare
         Part  : constant Natural := Share (Count);
         Given : Natural := 0;
      begin
         pragma Assert (Count * Part <= Bonus_Us);
         pragma Assert (Count * Part > Bonus_Us - Count);

         for I in 1 .. Count loop
            pragma Assert (I * Part <= Count * Part);
            Add_Share (Plan, Cues (I), Part);
            Given := Given + Part;

            pragma Loop_Invariant (Given = I * Part);
            pragma Loop_Invariant
              (Sum_To (Plan, Sector_Count)
                 = Sector_Count * Min_Sector_Us + Given);
            pragma Loop_Invariant
              (for all S in Sector => Plan (S) <= Min_Sector_Us + Given);
         end loop;
      end;
   end Build;

end Radar_Dwell;
