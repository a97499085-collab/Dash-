------------------------------------------------------------------------------
--  Dash_Builtin -- body
------------------------------------------------------------------------------

package body Dash_Builtin is

   ------------------------------------------------------------------
   --  Arity
   ------------------------------------------------------------------

   function Arity (B : Builtin_Id) return Integer is
   begin
      case B is
         when B_None     => return -1;
         when B_Print    => return 1;
         when B_Println  => return 1;
         when B_Text     => return 1;
         when B_Concat   => return 2;
         when B_Len      => return 1;
         when B_Read     => return 0;
         when B_ReadInt  => return 0;
         when B_Abs      => return 1;
         when B_Not      => return 1;
         when B_And      => return 2;
         when B_Or       => return 2;
         when B_Eq       => return 2;
         when B_Ne       => return 2;
         when B_Min      => return 2;
         when B_Max      => return 2;
         when B_Ret      => return 1;
      end case;
   end Arity;

   ------------------------------------------------------------------
   --  Result_Type
   ------------------------------------------------------------------

   function Result_Type (B : Builtin_Id) return Dash_Ast.Dash_Type is
   begin
      case B is
         when B_Print | B_Println | B_Ret =>
            return Dash_Ast.T_Unknown;

         when B_Text | B_Concat | B_Read =>
            return Dash_Ast.T_String;

         when B_Len | B_ReadInt | B_Abs | B_Min | B_Max =>
            return Dash_Ast.T_Int;

         when B_Not | B_And | B_Or | B_Eq | B_Ne =>
            return Dash_Ast.T_Bool;

         when B_None =>
            return Dash_Ast.T_Unknown;
      end case;
   end Result_Type;

   ------------------------------------------------------------------
   --  Is_Statement
   ------------------------------------------------------------------

   function Is_Statement (B : Builtin_Id) return Boolean is
   begin
      return B = B_Print or else B = B_Println or else B = B_Ret;
   end Is_Statement;

   ------------------------------------------------------------------
   --  Lookup
   ------------------------------------------------------------------

   function Lookup (Name : String) return Builtin_Id is
   begin
      if Name = "print" then
         return B_Print;
      elsif Name = "println" then
         return B_Println;
      elsif Name = "text" then
         return B_Text;
      elsif Name = "concat" then
         return B_Concat;
      elsif Name = "len" then
         return B_Len;
      elsif Name = "read" then
         return B_Read;
      elsif Name = "readint" then
         return B_ReadInt;
      elsif Name = "abs" then
         return B_Abs;
      elsif Name = "not" then
         return B_Not;
      elsif Name = "and" then
         return B_And;
      elsif Name = "or" then
         return B_Or;
      elsif Name = "eq" then
         return B_Eq;
      elsif Name = "ne" then
         return B_Ne;
      elsif Name = "min" then
         return B_Min;
      elsif Name = "max" then
         return B_Max;
      elsif Name = "ret" then
         return B_Ret;
      else
         return B_None;
      end if;
   end Lookup;

end Dash_Builtin;
