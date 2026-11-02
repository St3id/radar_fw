package body Radar_Ld2450_Plausibility
  with SPARK_Mode => On
is

   --  Compteur sature : un total faux au bout de 24 jours vaut mieux qu'un
   --  arret du capteur.
   procedure Increment (C : in out Counter)
     with Post => C >= C'Old
   is
   begin
      if C < Counter'Last then
         C := C + 1;
      end if;
   end Increment;

   --  Vrai si (X, Y) est a moins de Gate de (Ref_X, Ref_Y) sur chaque axe.
   function Near
     (X, Y, Ref_X, Ref_Y : Signed_Value;
      Gate               : Gate_Mm) return Boolean
   is
     (abs (Integer (X) - Integer (Ref_X)) <= Gate
      and then abs (Integer (Y) - Integer (Ref_Y)) <= Gate);

   --  Le jugement d'un emplacement, a part de la boucle : sa preuve ne voit
   --  pas les quantificateurs de l'invariant, ni la boucle les multiplications
   --  de Static_Verdict.
   procedure Judge
     (V      : in out Validator;
      S      : Target_Slot;
      T      : Raw_Target;
      Gate   : Gate_Mm;
      Retain : out Boolean)
     with
       Post =>
         (if Retain then
            Static_Verdict (T) = Plausible and then not Is_Absent (T))
         and then
         (if Is_Absent (T) then
            not Retain and then V.Rejected = V.Rejected'Old)
         and then V.Accepted >= V.Accepted'Old
         and then V.Absent >= V.Absent'Old
         and then
         (for all Why in Reject_Reason =>
            V.Rejected (Why) >= V.Rejected'Old (Why))
   is
   begin
      Retain := False;

      if Is_Absent (T) then
         Increment (V.Absent);
         V.Slots (S) := (others => <>);
         return;
      end if;

      case Static_Verdict (T) is
         when Not_In_Front =>
            Increment (V.Rejected (Reject_Not_In_Front));
         when Out_Of_Range =>
            Increment (V.Rejected (Reject_Out_Of_Range));
         when Too_Fast =>
            Increment (V.Rejected (Reject_Too_Fast));
         when Bad_Resolution =>
            Increment (V.Rejected (Reject_Bad_Resolution));
         when Plausible =>
            if V.Slots (S).Known
              and then not Near (T.X_Mm, T.Y_Mm,
                                 V.Slots (S).X_Mm, V.Slots (S).Y_Mm, Gate)
              and then not
                (V.Slots (S).Has_Pending
                 and then Near (T.X_Mm, T.Y_Mm,
                                V.Slots (S).Pending_X,
                                V.Slots (S).Pending_Y, Gate))
            then
               Increment (V.Rejected (Reject_Jump));
               V.Slots (S).Has_Pending := True;
               V.Slots (S).Pending_X   := T.X_Mm;
               V.Slots (S).Pending_Y   := T.Y_Mm;
            else
               Increment (V.Accepted);
               V.Slots (S) :=
                 (Known  => True,
                  X_Mm   => T.X_Mm,
                  Y_Mm   => T.Y_Mm,
                  others => <>);
               Retain := True;
            end if;
      end case;
   end Judge;

   --------------
   -- Validate --
   --------------

   procedure Validate
     (V          : in out Validator;
      Slots      : Raw_Target_Array;
      Elapsed_Ms : Natural;
      Result     : out Raw_Report)
   is
      Gate   : constant Gate_Mm := Jump_Gate (Elapsed_Ms);
      Retain : Boolean;
   begin
      Result := (others => <>);

      if Elapsed_Ms >= Jump_Forget_Ms then
         V.Slots := (others => <>);
      end if;

      for S in Target_Slot loop
         pragma Loop_Invariant (Result.Count <= S - 1);
         pragma Loop_Invariant
           (for all I in 1 .. Result.Count =>
              Static_Verdict (Result.Targets (I)) = Plausible
              and then not Is_Absent (Result.Targets (I))
              and then
              (for some K in 1 .. S - 1 => Result.Targets (I) = Slots (K)));
         pragma Loop_Invariant
           (for all I in Result.Count + 1 .. Max_Targets =>
              Is_Absent (Result.Targets (I)));
         pragma Loop_Invariant
           (if (for all K in 1 .. S - 1 => Is_Absent (Slots (K))) then
              Result.Count = 0
              and then V.Rejected = V.Rejected'Loop_Entry);
         pragma Loop_Invariant (V.Accepted >= V.Accepted'Loop_Entry);
         pragma Loop_Invariant (V.Absent >= V.Absent'Loop_Entry);
         pragma Loop_Invariant
           (for all Why in Reject_Reason =>
              V.Rejected (Why) >= V.Rejected'Loop_Entry (Why));

         Judge (V, S, Slots (S), Gate, Retain);
         if Retain then
            Result.Count := Result.Count + 1;
            Result.Targets (Result.Count) := Slots (S);
         end if;
      end loop;
   end Validate;

end Radar_Ld2450_Plausibility;
