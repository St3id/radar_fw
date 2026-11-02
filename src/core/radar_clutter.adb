--  Corps de Radar_Clutter. Arithmetique entiere uniquement, tableaux de
--  taille fixe, aucune allocation : le code doit rester executable sur le
--  microcontrolleur, ou aucune de ces facilites n'existe.

package body Radar_Clutter is

   --  Quantifie une direction (angles en degres) vers les indices de la
   --  grille. L'azimut est cyclique (modulo) ; l'elevation est bornee.
   --  Valid = False pour un angle non fini : il n'a pas de case.
   --
   --  Aucune boucle. La version precedente retranchait 360 tant que
   --  l'azimut depassait 360 : au-dela d'environ 1E10, 360 passe sous la
   --  precision d'un Float, Az - 360.0 rend Az lui-meme, et la boucle ne
   --  finissait jamais. Un seul azimut aberrant venu d'un capteur aurait
   --  fige le microcontroleur. Float'Remainder ramene tout nombre fini
   --  dans [-180, 180] en une operation exacte.
   procedure To_Cell
     (Az_Deg, El_Deg : Float;
      Az_Idx         : out Natural;
      El_Idx         : out Natural;
      Valid          : out Boolean)
   is
      Az_Norm : Float;
      El      : Float;
   begin
      Az_Idx := 0;
      El_Idx := 0;

      --  'Valid est faux pour NaN et les infinis, qui n'ont pas de case.
      Valid := Az_Deg'Valid and then El_Deg'Valid;
      if not Valid then
         return;
      end if;

      --  Azimut dans [0, 360].
      Az_Norm := Float'Remainder (Az_Deg, 360.0);
      if Az_Norm < 0.0 then
         Az_Norm := Az_Norm + 360.0;
      end if;

      --  Un arrondi peut donner tout juste 360 : le mod le replie sur 0.
      Az_Idx :=
        Natural (Float'Floor (Az_Norm * Float (Az_Cells) / 360.0 + 0.5))
        mod Az_Cells;

      --  Elevation bornee AVANT la conversion en entier : convertir un
      --  angle demesure leverait Constraint_Error, et le coeur embarque
      --  ne doit propager aucune exception.
      El := Float'Min (El_Max_Deg, Float'Max (El_Min_Deg, El_Deg));
      El_Idx :=
        Natural (Float'Floor
          ((El - El_Min_Deg) * Float (El_Cells - 1)
           / (El_Max_Deg - El_Min_Deg) + 0.5));
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
      Valid          : Boolean;
   begin
      To_Cell (Az_Deg, El_Deg, Az_Idx, El_Idx, Valid);
      if not Valid then
         return;   --  direction inconnue : rien a apprendre
      end if;

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
      Valid          : Boolean;
      Result         : Detection := (Targets => (others => Bin_Index'First),
                                     Count   => 0);
   begin
      To_Cell (Az_Deg, El_Deg, Az_Idx, El_Idx, Valid);
      if not Valid then
         return Result;   --  mesure sans direction : inexploitable
      end if;

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
