package body Radar_Ld2450_Stream
  with SPARK_Mode => On
is

   --  Feed se decoupe en deux issues, chacune avec son contrat. Ce n'est pas
   --  du style : la preuve de chaque issue ne voit ainsi que ses propres
   --  hypotheses, et le prouveur n'a plus a les demeler.

   --  La suite "fenetre puis Octet", dans un tableau de 30 octets. Au-dela
   --  de cette suite, le contenu reste celui de l'ancienne fenetre : il ne
   --  sert a rien.
   function Joined (P : Parser; Octet : Byte) return Frame_Bytes
     with
       Post =>
         (for all I in 1 .. P.Used + 1 =>
            Joined'Result (I) = Joined_Byte (P, Octet, I))
   is
      W : Frame_Bytes := P.Window;
   begin
      W (P.Used + 1) := Octet;
      return W;
   end Joined;

   --  L'octet recu complete 30 rangs conformes : c'est une trame.
   procedure Deliver
     (P      : in out Parser;
      Octet  : Byte;
      Sortie : out Decoded_Frame)
     with
       Pre  =>
         Is_Consistent (P)
         and then P.Used = Frame_Length - 1
         and then Suffix_Is_Candidate (P, Octet, 0),
       Post =>
         Is_Consistent (P)
         and then P.Read = Plus (P.Read'Old, 1)
         and then P.Used = 0
         and then P.Delivered = Plus (P.Delivered'Old, 1)
         and then P.Discarded = P.Discarded'Old
         and then Has_Frame_Marks (Sortie.Bytes)
         and then Sortie.Bytes (Frame_Length) = Octet
         and then
         (for all I in Frame_Bytes'Range =>
            Sortie.Bytes (I) = Joined_Byte (P'Old, Octet, I))
         and then
         (for all S in Target_Slot =>
            Sortie.Targets (S) = Decode_Slot (Sortie.Bytes, S))
   is
      W : constant Frame_Bytes := Joined (P, Octet);
   begin
      pragma Assert (for all I in W'Range => Fits_Rank (I, W (I)));
      Sortie :=
        (Bytes   => W,
         Targets =>
           (1 => Decode_Slot (W, 1),
            2 => Decode_Slot (W, 2),
            3 => Decode_Slot (W, 3)));
      P :=
        (Window    => W,
         Used      => 0,
         Read      => Plus (P.Read, 1),
         Delivered => Plus (P.Delivered, 1),
         Discarded => P.Discarded);
   end Deliver;

   --  Pas de trame : on abandonne les Drop octets les plus anciens de la
   --  suite, qui ne pouvaient pas ouvrir une trame, et on garde le reste.
   procedure Keep
     (P     : in out Parser;
      Octet : Byte;
      Drop  : Natural)
     with
       Pre  =>
         Is_Consistent (P)
         and then Drop <= P.Used + 1
         and then P.Used + 1 - Drop < Frame_Length
         and then
         (for all D in 0 .. Drop - 1 =>
            not Suffix_Is_Candidate (P, Octet, D))
         and then
         (Drop > P.Used or else Suffix_Is_Candidate (P, Octet, Drop)),
       Post =>
         Is_Consistent (P)
         and then P.Read = Plus (P.Read'Old, 1)
         and then P.Delivered = P.Delivered'Old
         and then Keeps_Longest_Candidate (P'Old, Octet, P)
   is
      Kept : constant Natural := P.Used + 1 - Drop;
      W    : Frame_Bytes      := Joined (P, Octet);
   begin
      W (1 .. Kept) := W (Drop + 1 .. P.Used + 1);
      pragma Assert
        (for all I in 1 .. Kept => W (I) = Joined_Byte (P, Octet, I + Drop));
      pragma Assert
        (for all I in 1 .. Kept =>
           Fits_Rank (I, Joined_Byte (P, Octet, I + Drop)));
      pragma Assert (for all I in 1 .. Kept => Fits_Rank (I, W (I)));
      P :=
        (Window    => W,
         Used      => Kept,
         Read      => Plus (P.Read, 1),
         Delivered => P.Delivered,
         Discarded => Plus (P.Discarded, Drop));
   end Keep;

   ----------
   -- Feed --
   ----------

   procedure Feed
     (P           : in out Parser;
      Octet       : Byte;
      Sortie      : out Decoded_Frame;
      Trame_Prete : out Boolean)
   is
      --  Nombre d'octets de "fenetre puis Octet" que l'on abandonne.
      Drop : Natural range 0 .. Frame_Length := 0;
   begin
      Sortie      := (others => <>);
      Trame_Prete := False;

      --  Tant que la suite ne peut pas etre un debut de trame, on abandonne
      --  son premier octet, un seul, et on reexamine le reste : c'est ce
      --  decalage d'un octet qui retrouve un en-tete cache dans un faux
      --  candidat. Au pire 30 examens de 30 rangs pour un octet recu : le
      --  cout reste negligeable devant les 39 us d'un octet a 256 000 bauds.
      while Drop <= P.Used
        and then not Suffix_Is_Candidate (P, Octet, Drop)
      loop
         pragma Loop_Invariant
           (for all D in 0 .. Drop - 1 =>
              not Suffix_Is_Candidate (P, Octet, D));
         pragma Loop_Variant (Increases => Drop);
         Drop := Drop + 1;
      end loop;

      if Drop = 0 and then P.Used = Frame_Length - 1 then
         Deliver (P, Octet, Sortie);
         Trame_Prete := True;
      else
         Keep (P, Octet, Drop);
      end if;
   end Feed;

end Radar_Ld2450_Stream;
