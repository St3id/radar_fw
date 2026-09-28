package body Radar_Ld2450
  with SPARK_Mode => On
is

   --  Ecrit W sur deux octets a partir du rang At_Index, poids faible en
   --  premier. La precondition garantit que les deux octets tiennent dans
   --  la trame : le prouveur la verifie a chaque appel.
   procedure Put_Word
     (F        : in out Frame_Bytes;
      At_Index : Positive;
      W        : Word)
     with Pre => At_Index < Frame_Length
   is
   begin
      F (At_Index)     := Low_Byte (W);
      F (At_Index + 1) := High_Byte (W);
   end Put_Word;

   ------------------
   -- Encode_Frame --
   ------------------

   function Encode_Frame (R : Raw_Report) return Frame_Bytes is
      F : Frame_Bytes := (others => 0);
   begin
      for S in 1 .. R.Count loop
         declare
            T     : constant Raw_Target := R.Targets (S);
            First : constant Positive   := Slot_First (S);
         begin
            Put_Word (F, First,     Encode_Signed (T.X_Mm));
            Put_Word (F, First + 2, Encode_Signed (T.Y_Mm));
            Put_Word (F, First + 4, Encode_Signed (T.Speed_Cm_S));
            Put_Word (F, First + 6, T.Resolution_Mm);
         end;
      end loop;

      --  En-tete et fin ecrits en dernier : la boucle ne peut plus les
      --  toucher, et la postcondition se prouve sans invariant de boucle.
      F (1 .. Header_Length)          := Header;
      F (Tail_First .. Frame_Length) := Tail;
      return F;
   end Encode_Frame;

end Radar_Ld2450;
