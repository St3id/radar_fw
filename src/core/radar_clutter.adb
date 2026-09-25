--  Corps de Radar_Clutter. Arithmetique entiere uniquement, tableaux de
--  taille fixe, aucune allocation : le code doit rester executable sur le
--  microcontrolleur, ou aucune de ces facilites n'existe.

package body Radar_Clutter is

   --  Quantifie une direction (angles en degres) vers les indices de la
   --  grille. L'azimut est cyclique (modulo) ; l'elevation est bornee.
   procedure To_Cell
     (Az_Deg, El_Deg : Float;
      Az_Idx         : out Natural;
      El_Idx         : out Natural)
   is
      Az_Norm : Float := Az_Deg;
      El_Raw  : Integer;
   begin
      --  Azimut dans [0, 360[.
      while Az_Norm < 0.0 loop
         Az_Norm := Az_Norm + 360.0;
      end loop;
      while Az_Norm >= 360.0 loop
         Az_Norm := Az_Norm - 360.0;
      end loop;

      Az_Idx :=
        Natural (Float'Floor (Az_Norm * Float (Az_Cells) / 360.0 + 0.5))
        mod Az_Cells;

      --  Elevation : position sur la grille El_Min .. El_Max, bornee.
      El_Raw :=
        Integer (Float'Floor
          ((El_Deg - El_Min_Deg) * Float (El_Cells - 1)
           / (El_Max_Deg - El_Min_Deg) + 0.5));
      if El_Raw < 0 then
         El_Idx := 0;
      elsif El_Raw > El_Cells - 1 then
         El_Idx := El_Cells - 1;
      else
         El_Idx := Natural (El_Raw);
      end if;
   end To_Cell;

   -----------
   -- Clear --
   -----------

   procedure Clear (C : out Clutter_Map) is
   begin
      C.Cells := (others => (others => (others => 0)));
   end Clear;

   -----------
   -- Learn --
   -----------

   procedure Learn
     (C              : in out Clutter_Map;
      Az_Deg, El_Deg : Float;
      D              : Detection)
   is
      Az_Idx, El_Idx : Natural;
   begin
      To_Cell (Az_Deg, El_Deg, Az_Idx, El_Idx);
      for K in 1 .. D.Count loop
         declare
            Cnt : Confidence renames
              C.Cells (Az_Idx, El_Idx) (D.Targets (K));
         begin
            --  Saturation : pas de retour a zero par debordement.
            if Cnt < Confidence'Last then
               Cnt := Cnt + 1;
            end if;
         end;
      end loop;
   end Learn;

   ---------
   -- Age --
   ---------

   procedure Age (C : in out Clutter_Map) is
   begin
      for Az in 0 .. Az_Cells - 1 loop
         for El in 0 .. El_Cells - 1 loop
            for B in Bin_Index loop
               if C.Cells (Az, El) (B) > 0 then
                  C.Cells (Az, El) (B) := C.Cells (Az, El) (B) - 1;
               end if;
            end loop;
         end loop;
      end loop;
   end Age;

   ------------
   -- Filter --
   ------------

   function Filter
     (C              : Clutter_Map;
      Az_Deg, El_Deg : Float;
      D              : Detection) return Detection
   is
      Az_Idx, El_Idx : Natural;
      Result         : Detection := (Targets => (others => Bin_Index'First),
                                     Count   => 0);
   begin
      To_Cell (Az_Deg, El_Deg, Az_Idx, El_Idx);

      for K in 1 .. D.Count loop
         declare
            B          : constant Bin_Index := D.Targets (K);
            Is_Clutter : Boolean := False;
            Lo         : constant Bin_Index :=
              Bin_Index'Max (Bin_Index'First, B - Guard_Bins);
            Hi         : constant Bin_Index :=
              Bin_Index'Min (Bin_Index'Last, B + Guard_Bins);
         begin
            --  Clutter si une case confirmee existe dans la marge.
            for G in Lo .. Hi loop
               if C.Cells (Az_Idx, El_Idx) (G) >= Confirm_Level then
                  Is_Clutter := True;
                  exit;
               end if;
            end loop;

            if not Is_Clutter then
               Result.Count := Result.Count + 1;
               Result.Targets (Result.Count) := B;
            end if;
         end;
      end loop;

      return Result;
   end Filter;

end Radar_Clutter;
