------------------------------------------------------------------------------
--  Dash_Codegen -- body
------------------------------------------------------------------------------

with Ada.Strings.Fixed;
with Dash_Builtin;

package body Dash_Codegen is

   use Dash_Ast;
   use Dash_Builtin;

   Buf : Unbounded_String;

   ------------------------------------------------------------------
   --  Small helpers
   ------------------------------------------------------------------

   procedure Put_Line (S : String) is
   begin
      Append (Buf, S);
      Append (Buf, ASCII.LF);
   end Put_Line;

   function Pad (N : Natural) return String is
   begin
      return String'(1 .. N * 3 => ' ');
   end Pad;

   function Capitalize (S : String) return String is
   begin
      if S'Length = 0 then
         return S;
      elsif S'Length = 1 then
         return String'(1 => Character'Val (Character'Pos (S (S'First)) - 32));
      else
         return String'(1 => Character'Val (Character'Pos (S (S'First)) - 32))
           & S (S'First + 1 .. S'Last);
      end if;
   end Capitalize;

   --  An Ada string literal for a Dash string.
   function Ada_String (S : String) return String is
      R : Unbounded_String;
      C : Character;
   begin
      Append (R, '"');
      for I in S'Range loop
         C := S (I);
         if C = '"' then
            Append (R, """");
         end if;
         Append (R, String'(1 => C));
      end loop;
      Append (R, '"');
      return To_String (R);
   end Ada_String;

   function Ada_Type_Name (T : Dash_Type) return String is
   begin
      case T is
         when T_Int    => return "Long_Long_Integer";
         when T_Bool   => return "Boolean";
         when T_String => return "Unbounded_String";
         when others   => return "Long_Long_Integer";
      end case;
   end Ada_Type_Name;

   function Ada_Default (T : Dash_Type) return String is
   begin
      case T is
         when T_Int    => return "0";
         when T_Bool   => return "False";
         when T_String => return "Null_Unbounded_String";
         when others   => return "0";
      end case;
   end Ada_Default;

   function Ada_Zero (T : Dash_Type) return String is
   begin
      case T is
         when T_Int    => return "0";
         when T_Bool   => return "False";
         when T_String => return "Null_Unbounded_String";
         when others   => return "0";
      end case;
   end Ada_Zero;

   ------------------------------------------------------------------
   --  Name mangling:  V_ for variables, F_ for functions
   ------------------------------------------------------------------

   type Name_Entry;
   type Name_Access is access all Name_Entry;

   type Name_Entry is record
      Dash : Unbounded_String := Null_Unbounded_String;
      Ada  : Unbounded_String := Null_Unbounded_String;
      Next : Name_Access := null;
   end record;

   Names : Name_Access := null;

   function Ada_Name (Dash : Unbounded_String; Prefix : String) return String is
      E     : Name_Access := Names;
      Base  : constant String := Prefix & Capitalize (To_String (Dash));
      Cand  : String := Base;
      Count : Natural := 0;
      Found : Boolean := False;
   begin
      while E /= null loop
         if E.Dash = Dash then
            return To_String (E.Ada);
         end if;
         E := E.Next;
      end loop;

      loop
         E := Names;
         Found := False;
         while E /= null loop
            if E.Ada = Cand then
               Found := True;
            end if;
            E := E.Next;
         end loop;

         exit when not Found;

         Count := Count + 1;
         Cand  := Base & "_" & Ada.Strings.Fixed.Trim
           (Natural'Image (Count), Ada.Strings.Both);
      end loop;

      Names := new Name_Entry'(Dash => Dash,
                              Ada  => To_Unbounded_String (Cand),
                              Next => Names);
      return Cand;
   end Ada_Name;

   ------------------------------------------------------------------
   --  Forward declarations
   ------------------------------------------------------------------

   function Emit_Expr (E : Node_Access) return String;

   procedure Emit_Statements (Stmts : Child_List_Access; Indent : Natural);

   procedure Emit_Statement (S : Node_Access; Indent : Natural;
                             Ret_Type : Dash_Type);

   procedure Emit_Function (F : Node_Access; Indent : Natural);

   ------------------------------------------------------------------
   --  Collect the variables of a function
   ------------------------------------------------------------------

   procedure Collect_Vars (S : Node_Access; Into : in out Child_List_Access) is
      C : Child_List_Access;
   begin
      if S = null then
         return;
      end if;

      case S.Kind is
         when K_Var_Decl =>
            Append_To (Into, S);

         when K_If | K_While =>
            C := S.Stmts;
            while C /= null loop
               Collect_Vars (C.Item, Into);
               C := C.Next;
            end loop;

         when others =>
            null;              --  a nested function has its own scope
      end case;
   end Collect_Vars;

   ------------------------------------------------------------------
   --  Expressions
   ------------------------------------------------------------------

   function Emit_Args (Args : Child_List_Access) return String is
      R : Unbounded_String;
      C : Child_List_Access := Args;
      Sep : constant String := ", ";
   begin
      while C /= null loop
         if Length (R) > 0 then
            Append (R, Sep);
         end if;
         Append (R, Emit_Expr (C.Item));
         C := C.Next;
      end loop;
      return To_String (R);
   end Emit_Args;

   --  An expression wrapped into the universal runtime value.
   function Emit_Value (E : Node_Access) return String is
   begin
      if E = null then
         return "D_Of_Int (0)";
      end if;

      case E.Typ is
         when T_Bool   => return "D_Of_Bool (" & Emit_Expr (E) & ")";
         when T_String => return "D_Of_Str (" & Emit_Expr (E) & ")";
         when others   => return "D_Of_Int (" & Emit_Expr (E) & ")";
      end case;
   end Emit_Value;

   function Emit_Expr (E : Node_Access) return String is
      L : Unbounded_String;
      R : Unbounded_String;
      B : Builtin_Id;
   begin
      if E = null then
         return "0";
      end if;

      case E.Kind is
         when K_Int_Lit =>
            return Ada.Strings.Fixed.Trim
              (Long_Long_Integer'Image (E.Int_Value), Ada.Strings.Both);

         when K_Str_Lit =>
            return "To_Unbounded_String (" & Ada_String (To_String (E.Str_Value))
              & ")";

         when K_Bool_Lit =>
            if E.Bool_Value then
               return "True";
            else
               return "False";
            end if;

         when K_Var_Ref =>
            return Ada_Name (E.Name, "V_");

         when K_Un_Op =>
            return "(- (" & Emit_Expr (E.Sub) & "))";

         when K_Bin_Op =>
            L := To_Unbounded_String (Emit_Expr (Child_At (E, 1)));
            R := To_Unbounded_String (Emit_Expr (Child_At (E, 2)));

            if E.Op = '<' or else E.Op = '>' then
               if Child_At (E, 1).Typ = T_String then
                  return "(To_String (" & To_String (L) & ") " & E.Op
                    & " To_String (" & To_String (R) & "))";
               else
                  return "(" & To_String (L) & " " & E.Op & " "
                    & To_String (R) & ")";
               end if;
            elsif E.Op = '+' and then Child_At (E, 1).Typ = T_String then
               return "(" & To_String (L) & " & " & To_String (R) & ")";
            elsif E.Op = '%' then
               --  Ada spells the remainder operator 'mod'.
               return "(" & To_String (L) & " mod " & To_String (R) & ")";
            else
               return "(" & To_String (L) & " " & E.Op & " "
                 & To_String (R) & ")";
            end if;

         when K_Call =>
            B := Lookup (To_String (E.Name));

            if B = B_None then
               --  A function written in Dash.
               return Ada_Name (E.Name, "F_") & " (" & Emit_Args (E.Children) & ")";
            end if;

            case B is
               when B_Text =>
                  return "D_Text (" & Emit_Value (Child_At (E, 1)) & ")";

               when B_Concat =>
                  return "(" & Emit_Expr (Child_At (E, 1)) & " & "
                    & Emit_Expr (Child_At (E, 2)) & ")";

               when B_Len =>
                  return "Long_Long_Integer (Length ("
                    & Emit_Expr (Child_At (E, 1)) & "))";

               when B_Read =>
                  return "D_Read_Line";

               when B_ReadInt =>
                  return "D_Read_Int";

               when B_Abs =>
                  return "abs (" & Emit_Expr (Child_At (E, 1)) & ")";

               when B_Not =>
                  return "(not (" & Emit_Expr (Child_At (E, 1)) & "))";

               when B_And =>
                  return "((" & Emit_Expr (Child_At (E, 1)) & ") and then ("
                    & Emit_Expr (Child_At (E, 2)) & "))";

               when B_Or =>
                  return "((" & Emit_Expr (Child_At (E,  1)) & ") or else ("
                    & Emit_Expr (Child_At (E, 2)) & "))";

               when B_Eq =>
                  return "((" & Emit_Expr (Child_At (E, 1)) & ") = ("
                    & Emit_Expr (Child_At (E, 2)) & "))";

               when B_Ne =>
                  return "((" & Emit_Expr (Child_At (E, 1)) & ") /= ("
                    & Emit_Expr (Child_At (E, 2)) & "))";

               when B_Min =>
                  return "Long_Long_Integer'Min ("
                    & Emit_Expr (Child_At (E, 1)) & ", "
                    & Emit_Expr (Child_At (E, 2)) & ")";

               when B_Max =>
                  return "Long_Long_Integer'Max ("
                    & Emit_Expr (Child_At (E, 1)) & ", "
                    & Emit_Expr (Child_At (E, 2)) & ")";

               when others =>
                  --  print, println and ret are statements, not expressions.
                  return "0";
            end case;

         when others =>
            return "0";
      end case;
   end Emit_Expr;

   ------------------------------------------------------------------
   --  Statements
   ------------------------------------------------------------------

   procedure Emit_Call_Statement (E : Node_Access; Indent : Natural;
                                  Ret_Type : Dash_Type)
   is
      B : constant Builtin_Id := Lookup (To_String (E.Name));
   begin
      if B = B_Print then
         Put_Line (Pad (Indent) & "D_Print (" & Emit_Value (Child_At (E, 1)) & ");");

      elsif B = B_Println then
         Put_Line (Pad (Indent) & "D_Print_Line ("
                  & Emit_Value (Child_At (E, 1)) & ");");

      elsif B = B_Ret then
         if Ret_Type = T_Void then
            Put_Line (Pad (Indent) & "return;");
         else
            Put_Line (Pad (Indent) & "return "
                      & Emit_Expr (Child_At (E, 1)) & ";");
         end if;

      else
         --  A call whose result is thrown away.  A procedure is simply
         --  called, a function is wrapped so that Ada accepts it.
         if E.Typ = T_Void then
            Put_Line (Pad (Indent) & Emit_Expr (E) & ";");
         else
            Put_Line (Pad (Indent) & "D_Discard (" & Emit_Expr (E) & ");");
         end if;
      end if;
   end Emit_Call_Statement;

   procedure Emit_Statement (S : Node_Access; Indent : Natural;
                             Ret_Type : Dash_Type)
   is
      Cond : Unbounded_String;
   begin
      if S = null then
         return;
      end if;

      case S.Kind is
         when K_Var_Decl =>
            Put_Line (Pad (Indent) & Ada_Name (S.Name, "V_") & " := "
                      & Emit_Expr (S.Sub) & ";");

         when K_Assign =>
            Put_Line (Pad (Indent) & Ada_Name (S.Name, "V_") & " := "
                      & Emit_Expr (S.Sub) & ";");

         when K_If =>
            Cond := To_Unbounded_String (Emit_Expr (S.Sub));
            if S.Sub.Typ = T_Int then
               Cond := To_Unbounded_String ("(" & To_String (Cond) & " /= 0)");
            end if;
            Put_Line (Pad (Indent) & "if " & To_String (Cond) & " then");
            Emit_Statements (S.Stmts, Indent + 1);
            Put_Line (Pad (Indent) & "end if;");

         when K_While =>
            Cond := To_Unbounded_String (Emit_Expr (S.Sub));
            if S.Sub.Typ = T_Int then
               Cond := To_Unbounded_String ("(" & To_String (Cond) & " /= 0)");
            end if;
            Put_Line (Pad (Indent) & "while " & To_String (Cond) & " loop");
            Emit_Statements (S.Stmts, Indent + 1);
            Put_Line (Pad (Indent) & "end loop;");

         when K_Expr_Stmt =>
            if S.Sub /= null and then S.Sub.Kind = K_Call then
               Emit_Call_Statement (S.Sub, Indent, Ret_Type);
            end if;

         when K_Function =>
            null;              --  emitted with the declarations

         when others =>
            null;
      end case;
   end Emit_Statement;

   procedure Emit_Statements (Stmts : Child_List_Access; Indent : Natural) is
      C : Child_List_Access := Stmts;
   begin
      while C /= null loop
         Emit_Statement (C.Item, Indent, T_Unknown);
         C := C.Next;
      end loop;
   end Emit_Statements;

   ------------------------------------------------------------------
   --  Functions
   ------------------------------------------------------------------

   function Emit_Params (Params : Child_List_Access) return String is
      R  : Unbounded_String;
      C  : Child_List_Access := Params;
   begin
      while C /= null loop
         if Length (R) > 0 then
            Append (R, "; ");
         end if;
         Append (R, Ada_Name (C.Item.Name, "V_") & " : Long_Long_Integer");
         C := C.Next;
      end loop;
      return To_String (R);
   end Emit_Params;

   procedure Emit_Function (F : Node_Access; Indent : Natural) is
      Vars     : Child_List_Access := null;
      C        : Child_List_Access;
      Ret_Type : constant Dash_Type := F.Typ;

      function Header return String is
         P : constant String := Emit_Params (F.Params);
      begin
         if Ret_Type = T_Void then
            if P = "" then
               return "procedure " & Ada_Name (F.Name, "F_");
            else
               return "procedure " & Ada_Name (F.Name, "F_") & " (" & P & ")";
            end if;
         else
            if P = "" then
               return "function " & Ada_Name (F.Name, "F_")
                 & " return " & Ada_Type_Name (Ret_Type);
            else
               return "function " & Ada_Name (F.Name, "F_")
                 & " (" & P & ") return " & Ada_Type_Name (Ret_Type);
            end if;
         end if;
      end Header;

   begin
      --  Every variable of the function is declared once, in the
      --  declarative part; the statements then assign to them.  The
      --  parameters are not repeated, they are already in the signature.
      C := F.Decls;
      while C /= null loop
         Append_To (Vars, C.Item);
         C := C.Next;
      end loop;

      C := F.Stmts;
      while C /= null loop
         Collect_Vars (C.Item, Vars);
         C := C.Next;
      end loop;

      --  The signature.
      Put_Line (Pad (Indent) & Header & " is");

      --  The declarations.
      C := Vars;
      while C /= null loop
         Put_Line (Pad (Indent + 1) & Ada_Name (C.Item.Name, "V_") & " : "
                   & Ada_Type_Name (C.Item.Typ) & " := "
                   & Ada_Default (C.Item.Typ) & ";");
         C := C.Next;
      end loop;

      --  Nested functions become nested subprograms.
      C := F.Nested;
      while C /= null loop
         Emit_Function (C.Item, Indent + 1);
         C := C.Next;
      end loop;

      C := F.Stmts;
      while C /= null loop
         if C.Item.Kind = K_Function then
            Emit_Function (C.Item, Indent + 1);
         end if;
         C := C.Next;
      end loop;

      Put_Line (Pad (Indent) & "begin");

      --  The declarations of the function itself.
      C := F.Decls;
      while C /= null loop
         Put_Line (Pad (Indent + 1) & Ada_Name (C.Item.Name, "V_") & " := "
                   & Emit_Expr (C.Item.Sub) & ";");
         C := C.Next;
      end loop;

      --  The body.
      C := F.Stmts;
      while C /= null loop
         Emit_Statement (C.Item, Indent + 1, Ret_Type);
         C := C.Next;
      end loop;

      --  A function that can fall off its end still needs a value.
      if Ret_Type /= T_Void then
         declare
            Last : Node_Access := null;
         begin
            C := F.Stmts;
            while C /= null loop
               Last := C.Item;
               C := C.Next;
            end loop;

            if Last = null
              or else Last.Kind /= K_Expr_Stmt
              or else Last.Sub = null
              or else Last.Sub.Kind /= K_Call
              or else Last.Sub.Name /= "ret"
            then
               Put_Line (Pad (Indent + 1) & "return " & Ada_Zero (Ret_Type) & ";");
            end if;
         end;
      end if;

      if Ret_Type = T_Void then
         Put_Line (Pad (Indent) & "end " & Ada_Name (F.Name, "F_") & ";");
      else
         Put_Line (Pad (Indent) & "end " & Ada_Name (F.Name, "F_") & ";");
      end if;
   end Emit_Function;

   ------------------------------------------------------------------
   --  The runtime that is written into the head of the file
   ------------------------------------------------------------------

   procedure Emit_Runtime is
   begin
      Put_Line ("with Ada.Text_IO;");
      Put_Line ("with Ada.Text_IO.Unbounded_IO;");
      Put_Line ("with Ada.Strings.Unbounded;");
      Put_Line ("with Ada.Strings.Fixed;");
      Put_Line ("");
      Put_Line ("procedure Dash_Main is");
      Put_Line ("");
      Put_Line ("   use Ada.Strings.Unbounded;");
      Put_Line ("");
      Put_Line ("   type Dash_Value_Kind is (D_Int, D_Bool, D_String);");
      Put_Line ("");
      Put_Line ("   type Dash_Value is record");
      Put_Line ("      Kind : Dash_Value_Kind := D_Int;");
      Put_Line ("      I    : Long_Long_Integer := 0;");
      Put_Line ("      B    : Boolean := False;");
      Put_Line ("      S    : Unbounded_String := Null_Unbounded_String;");
      Put_Line ("   end record;");
      Put_Line ("");
      Put_Line ("   function D_Of_Int (V : Long_Long_Integer) return Dash_Value is");
      Put_Line ("     (Kind => D_Int, I => V, B => False, S => Null_Unbounded_String);");
      Put_Line ("");
      Put_Line ("   function D_Of_Bool (V : Boolean) return Dash_Value is");
      Put_Line ("     (Kind => D_Bool, I => 0, B => V, S => Null_Unbounded_String);");
      Put_Line ("");
      Put_Line ("   function D_Of_Str (V : Unbounded_String) return Dash_Value is");
      Put_Line ("     (Kind => D_String, I => 0, B => False, S => V);");
      Put_Line ("");
      Put_Line ("   function D_Text (V : Dash_Value) return Unbounded_String is");
      Put_Line ("   begin");
      Put_Line ("      case V.Kind is");
      Put_Line ("         when D_Int =>");
      Put_Line ("            return To_Unbounded_String");
      Put_Line ("              (Ada.Strings.Fixed.Trim");
      Put_Line ("                 (Long_Long_Integer'Image (V.I), Ada.Strings.Both));");
      Put_Line ("         when D_Bool =>");
      Put_Line ("            if V.B then");
      Put_Line ("               return To_Unbounded_String (""true"");");
      Put_Line ("            else");
      Put_Line ("               return To_Unbounded_String (""false"");");
      Put_Line ("            end if;");
      Put_Line ("         when D_String =>");
      Put_Line ("            return V.S;");
      Put_Line ("      end case;");
      Put_Line ("   end D_Text;");
      Put_Line ("");
      Put_Line ("   procedure D_Print (V : Dash_Value) is");
      Put_Line ("   begin");
      Put_Line ("      Ada.Text_IO.Put (To_String (D_Text (V)));");
      Put_Line ("   end D_Print;");
      Put_Line ("");
      Put_Line ("   procedure D_Print_Line (V : Dash_Value) is");
      Put_Line ("   begin");
      Put_Line ("      Ada.Text_IO.Put_Line (To_String (D_Text (V)));");
      Put_Line ("   end D_Print_Line;");
      Put_Line ("");
      Put_Line ("   procedure D_Discard (V : Long_Long_Integer) is");
      Put_Line ("      pragma Unreferenced (V);");
      Put_Line ("   begin");
      Put_Line ("      null;");
      Put_Line ("   end D_Discard;");
      Put_Line ("");
      Put_Line ("   procedure D_Discard (V : Boolean) is");
      Put_Line ("      pragma Unreferenced (V);");
      Put_Line ("   begin");
      Put_Line ("      null;");
      Put_Line ("   end D_Discard;");
      Put_Line ("");
      Put_Line ("   procedure D_Discard (V : Unbounded_String) is");
      Put_Line ("      pragma Unreferenced (V);");
      Put_Line ("   begin");
      Put_Line ("      null;");
      Put_Line ("   end D_Discard;");
      Put_Line ("");
      Put_Line ("   function D_Read_Line return Unbounded_String is");
      Put_Line ("      L : Unbounded_String := Null_Unbounded_String;");
      Put_Line ("   begin");
      Put_Line ("      if not Ada.Text_IO.End_Of_File (Ada.Text_IO.Standard_Input)");
      Put_Line ("        and then not Ada.Text_IO.End_Of_Line (Ada.Text_IO.Standard_Input)");
      Put_Line ("      then");
      Put_Line ("         Ada.Text_IO.Unbounded_IO.Get_Line (L);");
      Put_Line ("      end if;");
      Put_Line ("      if Length (L) >= 3");
      Put_Line ("        and then Element (L, 1) = Character'Val (16#EF#)");
      Put_Line ("        and then Element (L, 2) = Character'Val (16#BB#)");
      Put_Line ("        and then Element (L, 3) = Character'Val (16#BF#)");
      Put_Line ("      then");
      Put_Line ("         L := Unbounded_Slice (L, 4, Length (L));");
      Put_Line ("      end if;");
      Put_Line ("      return L;");
      Put_Line ("   end D_Read_Line;");
      Put_Line ("");
      Put_Line ("   function D_Read_Int return Long_Long_Integer is");
      Put_Line ("   begin");
      Put_Line ("      return Long_Long_Integer'Value");
      Put_Line ("        (Ada.Strings.Fixed.Trim");
      Put_Line ("           (To_String (D_Read_Line), Ada.Strings.Both));");
      Put_Line ("   end D_Read_Int;");
      Put_Line ("");
   end Emit_Runtime;

   ------------------------------------------------------------------
   --  Generate
   ------------------------------------------------------------------

   function Generate (Program : Dash_Ast.Node_Access) return Unbounded_String is
      C : Child_List_Access;
      Main : Node_Access := null;
   begin
      Buf  := Null_Unbounded_String;
      Names := null;

      Put_Line ("--  Generated by the DCM, the Dash Compiler Machine.");
      Put_Line ("--  Do not edit: this file is rebuilt from the .dh source.");
      Put_Line ("");
      Emit_Runtime;

      --  The functions of the program.
      C := Program.Children;
      while C /= null loop
         if C.Item.Kind = K_Function then
            Emit_Function (C.Item, 1);
            Put_Line ("");
            if C.Item.Name = "main" then
               Main := C.Item;
            end if;
         end if;
         C := C.Next;
      end loop;

      if Main = null then
         raise Codegen_Error with "the program has no 'main' function";
      end if;

      Put_Line ("begin");
      if Main.Typ = T_Void then
         Put_Line ("   " & Ada_Name (Main.Name, "F_") & ";");
      else
         Put_Line ("   D_Discard (" & Ada_Name (Main.Name, "F_") & ");");
      end if;
      Put_Line ("end Dash_Main;");

      return Buf;
   end Generate;

end Dash_Codegen;
