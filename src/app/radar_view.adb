with Ada.Numerics.Elementary_Functions;

package body Radar_View is

   use Ada.Numerics.Elementary_Functions;

   function Scale (P : Plan) return Float is
     (if P.Around
      then Float'Min (P.Width, P.Height) * 0.47 / P.Range_Mm
      else Float'Min (P.Width * 0.47, P.Height * 0.86) / P.Range_Mm);

   function Origin (P : Plan) return Screen_Point is
     (X => P.Width / 2.0,
      --  Demi-disque centre : sinon la hauteur libre reste vide au-dessus
      --  et une piste qui passe derriere le capteur sort de la vue.
      Y => (if P.Around then P.Height / 2.0
            else (P.Height + P.Range_Mm * Scale (P)) / 2.0));

   function To_Screen (P : Plan; X_Mm, Y_Mm : Float) return Screen_Point is
      O : constant Screen_Point := Origin (P);
      K : constant Float := Scale (P);
   begin
      return (X => O.X + X_Mm * K, Y => O.Y - Y_Mm * K);
   end To_Screen;

   --  Camera sur une sphere autour du capteur, regard vers l'origine.
   function Project
     (C : Camera; Width, Height : Float; P : Point_3D) return Projected
   is
      Cam_X : constant Float := C.Distance * Cos (C.Pitch) * Cos (C.Yaw);
      Cam_Y : constant Float := C.Distance * Cos (C.Pitch) * Sin (C.Yaw);
      Cam_Z : constant Float := C.Distance * Sin (C.Pitch);

      --  Axes de la camera : devant vers l'origine, droite = devant x Z,
      --  haut = droite x devant.
      Fx : constant Float := -Cos (C.Pitch) * Cos (C.Yaw);
      Fy : constant Float := -Cos (C.Pitch) * Sin (C.Yaw);
      Fz : constant Float := -Sin (C.Pitch);
      Rx : constant Float := -Sin (C.Yaw);
      Ry : constant Float := Cos (C.Yaw);
      Ux : constant Float := Ry * Fz;
      Uy : constant Float := -Rx * Fz;
      Uz : constant Float := Rx * Fy - Ry * Fx;

      Dx : constant Float := P.X - Cam_X;
      Dy : constant Float := P.Y - Cam_Y;
      Dz : constant Float := P.Z - Cam_Z;

      Depth : constant Float := Dx * Fx + Dy * Fy + Dz * Fz;
      Focal : constant Float := 0.9 * Height;
   begin
      if Depth < 100.0 then
         return (others => <>);
      end if;
      return
        (S       =>
           (X => Width / 2.0 + Focal * (Dx * Rx + Dy * Ry) / Depth,
            Y => Height / 2.0
                 - Focal * (Dx * Ux + Dy * Uy + Dz * Uz) / Depth),
         Depth   => Depth,
         Visible => True);
   end Project;

   function Distance_Sq (A, B : Screen_Point) return Float is
     ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2);

   function Nearest
     (Points : Screen_Array;
      Mouse  : Screen_Point;
      Max_Px : Float) return Natural
   is
      Best  : Natural := 0;
      Limit : Float   := Max_Px ** 2;
   begin
      for I in Points'Range loop
         declare
            D : constant Float := Distance_Sq (Points (I), Mouse);
         begin
            if D <= Limit then
               Limit := D;
               Best  := I;
            end if;
         end;
      end loop;
      return Best;
   end Nearest;

   function Crowded
     (Points : Screen_Array;
      Index  : Positive;
      Min_Px : Float) return Boolean is
   begin
      for I in Points'Range loop
         if I /= Index
           and then Distance_Sq (Points (I), Points (Index)) < Min_Px ** 2
         then
            return True;
         end if;
      end loop;
      return False;
   end Crowded;

end Radar_View;
