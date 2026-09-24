with Ada.Numerics;                      use Ada.Numerics;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

--  Corps de Radar_World. Le mouvement est volontairement simple
--  (translation puis rebond sur les parois) : le simulateur doit etre
--  reproductible et lisible, pas physiquement exact.

package body Radar_World is

   -------------------
   -- Initial_World --
   -------------------

   function Initial_World return World is
      W : World := (Objects => (others => (Id => 1, others => 0.0)),
                    Count   => 0);
   begin
      --  Objet 1 : part a droite, avance vers la gauche.
      W.Objects (1) := (Id => 1,
                        X  => 3000.0, Y => 1000.0, Z => 0.0,
                        Vx => -120.0, Vy => 0.0,    Vz => 0.0);

      --  Objet 2 : part en bas a gauche, monte en diagonale.
      --  (Surtout pas colle a un mur : une cible qui rase un mur tombe
      --  dans les memes cases de distance que lui, et la carte de
      --  clutter la masque - comme sur un vrai radar.)
      W.Objects (2) := (Id => 2,
                        X  => -1200.0, Y => -900.0, Z => 400.0,
                        Vx => 50.0,    Vy => 80.0,  Vz => 0.0);

      W.Count := 2;
      return W;
   end Initial_World;

   -----------------
   -- Empty_World --
   -----------------

   function Empty_World return World is
   begin
      return (Objects => (others => (Id => 1, others => 0.0)),
              Count   => 0);
   end Empty_World;

   ------------------
   -- X_Wall_First --
   ------------------

   --  Le rayon de direction horizontale (Cos_A, Sin_A) touche-t-il
   --  d'abord un mur X (x = +/- Room_Half_X, normale selon X) plutot
   --  qu'un mur Y ? On compare Room_Half_X / |cos| a Room_Half_Y / |sin|
   --  en multipliant en croix : jamais de division par zero. Partagee par
   --  Wall_Distance et Wall_Incidence, qui doivent designer le MEME mur ;
   --  sinon l'echo serait calcule pour un mur et place a la distance de
   --  l'autre.
   function X_Wall_First (Cos_A, Sin_A : Float) return Boolean is
     (Room_Half_X * abs Sin_A <= Room_Half_Y * abs Cos_A);

   -------------------
   -- Wall_Distance --
   -------------------

   function Wall_Distance (Azimuth_Deg, Elevation_Deg : Float) return Float is
      Az_Rad : constant Float := Azimuth_Deg   * Pi / 180.0;
      El_Rad : constant Float := Elevation_Deg * Pi / 180.0;

      Cos_A : constant Float := Cos (Az_Rad);
      Sin_A : constant Float := Sin (Az_Rad);

      Horizontal : Float;
   begin
      --  Distance (vue de dessus) jusqu'au mur touche. Les divisions sont
      --  sures : X_Wall_First n'est vrai que si |cos| > 0 (sinon son
      --  membre droit serait nul), et faux que si |sin| > 0.
      if X_Wall_First (Cos_A, Sin_A) then
         Horizontal := Room_Half_X / abs Cos_A;
      else
         Horizontal := Room_Half_Y / abs Sin_A;
      end if;

      --  Viser haut ou bas allonge le trajet (elevation supposee < 90
      --  degres : cos > 0).
      return Horizontal / Cos (El_Rad);
   end Wall_Distance;

   --------------------
   -- Wall_Incidence --
   --------------------

   function Wall_Incidence
     (Azimuth_Deg, Elevation_Deg : Float) return Float
   is
      Az_Rad : constant Float := Azimuth_Deg   * Pi / 180.0;
      El_Rad : constant Float := Elevation_Deg * Pi / 180.0;

      Cos_A : constant Float := Cos (Az_Rad);
      Sin_A : constant Float := Sin (Az_Rad);

      --  Cosinus de l'incidence : produit scalaire du rayon
      --  (cos El cos A, cos El sin A, sin El) et de la normale du mur
      --  touche, (1, 0, 0) pour un mur X ou (0, 1, 0) pour un mur Y.
      Cos_H : constant Float :=
        (if X_Wall_First (Cos_A, Sin_A) then abs Cos_A else abs Sin_A);

      --  Borne a 1 : un arrondi flottant juste au-dessus ferait lever
      --  Argument_Error a Arccos.
      Cos_I : constant Float := Float'Min (1.0, abs Cos (El_Rad) * Cos_H);
   begin
      --  Cos_I est dans 0 .. 1, donc Arccos dans 0 .. Pi/2 ; le Min
      --  absorbe l'arrondi de la conversion en degres (Post).
      return Float'Min (90.0, Arccos (Cos_I) * 180.0 / Pi);
   end Wall_Incidence;

   ----------
   -- Step --
   ----------

   procedure Step (W : in out World) is
      --  Les objets rebondissent sur les murs de la piece : la scene
      --  reste vivante indefiniment (mode live) et les vecteurs vitesse
      --  changent a chaque rebond. La marge les garde a distance du mur
      --  pour que la carte de clutter ne les confonde pas avec lui.
      Margin : constant Float := 400.0;
      X_Lim  : constant Float := Room_Half_X - Margin;
      Y_Lim  : constant Float := Room_Half_Y - Margin;
   begin
      --  Chaque objet avance d'un pas : position += vitesse.
      for I in 1 .. W.Count loop
         declare
            O : Object renames W.Objects (I);
         begin
            O.X := O.X + O.Vx;
            O.Y := O.Y + O.Vy;
            O.Z := O.Z + O.Vz;

            if O.X > X_Lim and then O.Vx > 0.0 then
               O.Vx := -O.Vx;
            elsif O.X < -X_Lim and then O.Vx < 0.0 then
               O.Vx := -O.Vx;
            end if;

            if O.Y > Y_Lim and then O.Vy > 0.0 then
               O.Vy := -O.Vy;
            elsif O.Y < -Y_Lim and then O.Vy < 0.0 then
               O.Vy := -O.Vy;
            end if;
         end;
      end loop;
   end Step;

end Radar_World;
