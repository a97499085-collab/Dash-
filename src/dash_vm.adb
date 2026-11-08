------------------------------------------------------------------------------
--  Dash_Vm -- body
------------------------------------------------------------------------------

with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Text_IO.Unbounded_IO;
with Dash_Builtin;

package body Dash_Vm is

   use Ada.Strings.Unbounded;
   use Dash_Ast;
   use Dash_Builtin;

   ------------------------------------------------------------------
   --  Values
   ------------------------------------------------------------------

   type Value_Kind is (V_Int, V_Bool, V_String);

   type Value is record
      Kind : Value_Kind := V_Int;
      I    : Long_Long_Integer := 0;
      B    : Boolean := False;
      S    : Unbounded_String := Null_Unbounded_String;
   end record;

   Null_Value : constant Value :=
     (Kind => V_Int, I => 0, B => False, S => Null_Unbounded_String);

   ------------------------------------------------------------------
   --  Environments
   ------------------------------------------------------------------

   type Env;
   type Env_Access is access all Env;

   type Binding;
   type Binding_Access is access all Binding;

   type Binding is record
      Name    : Unbounded_String := Null_Unbounded_String;
      Val     : Value := Null_Value;
      Func    : Node_Access := null;      --  a nested function
      Closure : Env_Access := null;       --  environment it was born in
      Next    : Binding_Access := null;
   end record;

   type Env is record
      Parent : Env_Access := null;
      Vars   : Binding_Access := null;
   end record;

   Global_Env  : Env_Access := null;
   Return_Value : Value := Null_Value;

   --  Raised to unwind a 'ret'.
   Dash_Return : exception;

   ------------------------------------------------------------------
   --  Helpers
   ------------------------------------------------------------------

   function Line_Of (N : Node_Access) return Natural is
   begin
      if N = null then
         return 0;
      else
         return N.Line;
      end if;
   end Line_Of;

   procedure Fail (N : Node_Access; Msg : String) is
   begin
      raise Runtime_Error with "line" & Natural'Image (Line_Of (N)) & ": " & Msg;
   end Fail;

   function Image (V : Value) return String is
   begin
      case V.Kind is
         when V_Int =>
            return Ada.Strings.Fixed.Trim
              (Long_Long_Integer'Image (V.I), Ada.Strings.Both);
         when V_Bool =>
            if V.B then
               return "true";
            else
               return "false";
            end if;
         when V_String =>
            return To_String (V.S);
      end case;
   end Image;

   function New_Env (Parent : Env_Access) return Env_Access is
   begin
      return new Env'(Parent => Parent, Vars => null);
   end New_Env;

   function Lookup_Var (Env : Env_Access; Name : Unbounded_String)
                        return Binding_Access
   is
      E : Env_Access := Env;
      B : Binding_Access;
   begin
      while E /= null loop
         B := E.Vars;
         while B /= null loop
            if B.Name = Name then
               return B;
            end if;
            B := B.Next;
         end loop;
         E := E.Parent;
      end loop;
      return null;
   end Lookup_Var;

   procedure Bind_Var
     (Env : Env_Access; Name : Unbounded_String; V : Value)
   is
      B : Binding_Access := new Binding'(Name    => Name,
                                        Val     => V,
                                        Func    => null,
                                        Closure => null,
                                        Next    => Env.Vars);
   begin
      Env.Vars := B;
   end Bind_Var;

   procedure Bind_Func
     (Env : Env_Access; F : Node_Access; Closure : Env_Access)
   is
      B : Binding_Access := new Binding'(Name    => F.Name,
                                        Val     => Null_Value,
                                        Func    => F,
                                        Closure => Closure,
                                        Next    => Env.Vars);
   begin
      Env.Vars := B;
   end Bind_Func;

   procedure Assign_Var
     (Env : Env_Access; Name : Unbounded_String; V : Value)
   is
      B : constant Binding_Access := Lookup_Var (Env, Name);
   begin
      if B = null then
         Fail (null, "'" & To_String (Name) & "' is not declared");
      end if;
      B.Val := V;
   end Assign_Var;

   function Truth (V : Value; N : Node_Access) return Boolean is
   begin
      case V.Kind is
         when V_Bool    => return V.B;
         when V_Int     => return V.I /= 0;
         when V_String  => return Length (V.S) /= 0;
      end case;
   end Truth;

   --  A byte order mark at the start of a line is dropped.
   procedure Strip_BOM (S : in out Unbounded_String) is
   begin
      if Length (S) >= 3
        and then Element (S, 1) = Character'Val (16#EF#)
        and then Element (S, 2) = Character'Val (16#BB#)
        and then Element (S, 3) = Character'Val (16#BF#)
      then
         S := Unbounded_Slice (S, 4, Length (S));
      end if;
   end Strip_BOM;

   ------------------------------------------------------------------
   --  Forward declarations
   ------------------------------------------------------------------

   function Eval (E : Node_Access; Env : Env_Access) return Value;

   procedure Exec_Statement (S : Node_Access; Env : Env_Access);

   function Call_User
     (F : Node_Access; Closure : Env_Access; Args : Child_List_Access;
      Caller : Env_Access)
      return Value;

   ------------------------------------------------------------------
   --  Builtins
   ------------------------------------------------------------------

   function Eval_Builtin
     (E : Node_Access; B : Dash_Builtin.Builtin_Id; Env : Env_Access)
      return Value
   is
      A1 : Value := Null_Value;
      A2 : Value := Null_Value;
   begin
      if Child_Count (E) >= 1 then
         A1 := Eval (Child_At (E, 1), Env);
      end if;
      if Child_Count (E) >= 2 then
         A2 := Eval (Child_At (E, 2), Env);
      end if;

      case B is
         when Dash_Builtin.B_Print =>
            Ada.Text_IO.Put (Image (A1));
            return Null_Value;

         when Dash_Builtin.B_Println =>
            Ada.Text_IO.Put_Line (Image (A1));
            return Null_Value;

         when Dash_Builtin.B_Text =>
            return (Kind => V_String, I => 0, B => False,
                    S => To_Unbounded_String (Image (A1)));

         when Dash_Builtin.B_Concat =>
            return (Kind => V_String, I => 0, B => False,
                    S => A1.S & A2.S);

         when Dash_Builtin.B_Len =>
            return (Kind => V_Int, I => Long_Long_Integer (Length (A1.S)),
                    B => False, S => Null_Unbounded_String);

         when Dash_Builtin.B_Read =>
            declare
               Line : Unbounded_String := Null_Unbounded_String;
            begin
               if not Ada.Text_IO.End_Of_File (Ada.Text_IO.Standard_Input)
                 and then not Ada.Text_IO.End_Of_Line (Ada.Text_IO.Standard_Input)
               then
                  Ada.Text_IO.Unbounded_IO.Get_Line (Line);
               end if;
               Strip_BOM (Line);
               return (Kind => V_String, I => 0, B => False, S => Line);
            end;

         when Dash_Builtin.B_ReadInt =>
            declare
               Line : Unbounded_String := Null_Unbounded_String;
            begin
               if not Ada.Text_IO.End_Of_File (Ada.Text_IO.Standard_Input)
                 and then not Ada.Text_IO.End_Of_Line (Ada.Text_IO.Standard_Input)
               then
                  Ada.Text_IO.Unbounded_IO.Get_Line (Line);
               end if;
               Strip_BOM (Line);
               begin
                  return (Kind => V_Int,
                          I => Long_Long_Integer'Value
                            (Ada.Strings.Fixed.Trim
                               (To_String (Line), Ada.Strings.Both)),
                          B => False, S => Null_Unbounded_String);
               exception
                  when others =>
                     Fail (E, "'readint' expected a number");
                     return Null_Value;
               end;
            end;

         when Dash_Builtin.B_Abs =>
            if A1.I < 0 then
               return (Kind => V_Int, I => -A1.I, B => False,
                       S => Null_Unbounded_String);
            else
               return A1;
            end if;

         when Dash_Builtin.B_Not =>
            return (Kind => V_Bool, I => 0, B => not A1.B,
                    S => Null_Unbounded_String);

         when Dash_Builtin.B_And =>
            return (Kind => V_Bool, I => 0, B => A1.B and then A2.B,
                    S => Null_Unbounded_String);

         when Dash_Builtin.B_Or =>
            return (Kind => V_Bool, I => 0, B => A1.B or else A2.B,
                    S => Null_Unbounded_String);

         when Dash_Builtin.B_Eq =>
            declare
               Same : Boolean := False;
            begin
               if A1.Kind = A2.Kind then
                  case A1.Kind is
                     when V_Int    => Same := A1.I = A2.I;
                     when V_Bool   => Same := A1.B = A2.B;
                     when V_String => Same := A1.S = A2.S;
                  end case;
               end if;
               return (Kind => V_Bool, I => 0, B => Same,
                       S => Null_Unbounded_String);
            end;

         when Dash_Builtin.B_Ne =>
            declare
               Same : Boolean := False;
            begin
               if A1.Kind = A2.Kind then
                  case A1.Kind is
                     when V_Int    => Same := A1.I = A2.I;
                     when V_Bool   => Same := A1.B = A2.B;
                     when V_String => Same := A1.S = A2.S;
                  end case;
               end if;
               return (Kind => V_Bool, I => 0, B => not Same,
                       S => Null_Unbounded_String);
            end;

         when Dash_Builtin.B_Min =>
            if A1.I < A2.I then
               return A1;
            else
               return A2;
            end if;

         when Dash_Builtin.B_Max =>
            if A1.I > A2.I then
               return A1;
            else
               return A2;
            end if;

         when Dash_Builtin.B_Ret =>
            Return_Value := A1;
            raise Dash_Return;

         when Dash_Builtin.B_None =>
            Fail (E, "internal error: unknown builtin");
            return Null_Value;
      end case;
   end Eval_Builtin;

   ------------------------------------------------------------------
   --  Calls
   ------------------------------------------------------------------

   function Eval_Call (E : Node_Access; Env : Env_Access) return Value is
      B : constant Dash_Builtin.Builtin_Id :=
        Dash_Builtin.Lookup (To_String (E.Name));
      Binding : Binding_Access;
   begin
      if B /= Dash_Builtin.B_None then
         return Eval_Builtin (E, B, Env);
      end if;

      Binding := Lookup_Var (Env, E.Name);
      if Binding = null then
         Fail (E, "'" & To_String (E.Name) & "' is not a known function");
      end if;

      if Binding.Func = null then
         Fail (E, "'" & To_String (E.Name) & "' is a variable, not a function");
      end if;

      return Call_User (Binding.Func, Binding.Closure, E.Children, Env);
   end Eval_Call;

   ------------------------------------------------------------------
   --  Expressions
   ------------------------------------------------------------------

   function Eval (E : Node_Access; Env : Env_Access) return Value is
      L : Value;
      R : Value;
   begin
      if E = null then
         return Null_Value;
      end if;

      case E.Kind is
         when K_Int_Lit =>
            return (Kind => V_Int, I => E.Int_Value, B => False,
                    S => Null_Unbounded_String);

         when K_Str_Lit =>
            return (Kind => V_String, I => 0, B => False, S => E.Str_Value);

         when K_Bool_Lit =>
            return (Kind => V_Bool, I => 0, B => E.Bool_Value,
                    S => Null_Unbounded_String);

         when K_Var_Ref =>
            declare
               Binding : constant Binding_Access := Lookup_Var (Env, E.Name);
            begin
               if Binding = null or else Binding.Func /= null then
                  Fail (E, "'" & To_String (E.Name) & "' is not declared");
               end if;
               return Binding.Val;
            end;

         when K_Call =>
            return Eval_Call (E, Env);

         when K_Bin_Op =>
            L := Eval (Child_At (E, 1), Env);
            R := Eval (Child_At (E, 2), Env);

            if E.Op = '<' or else E.Op = '>' then
               declare
                  Less : Boolean := False;
               begin
                  if L.Kind = V_String and then R.Kind = V_String then
                     Less := (if E.Op = '<' then L.S < R.S else L.S > R.S);
                  else
                     Less := (if E.Op = '<' then L.I < R.I else L.I > R.I);
                  end if;
                  return (Kind => V_Bool, I => 0, B => Less,
                          S => Null_Unbounded_String);
               end;

            elsif E.Op = '+' then
               if L.Kind = V_String and then R.Kind = V_String then
                  return (Kind => V_String, I => 0, B => False, S => L.S & R.S);
               else
                  return (Kind => V_Int, I => L.I + R.I, B => False,
                          S => Null_Unbounded_String);
               end if;

            elsif E.Op = '-' then
               return (Kind => V_Int, I => L.I - R.I, B => False,
                       S => Null_Unbounded_String);

            elsif E.Op = '*' then
               return (Kind => V_Int, I => L.I * R.I, B => False,
                       S => Null_Unbounded_String);

            elsif E.Op = '/' then
               if R.I = 0 then
                  Fail (E, "division by zero");
               end if;
               --  Ada's '/' truncates towards zero, the same as 'rem'.
               return (Kind => V_Int, I => L.I rem R.I, B => False,
                       S => Null_Unbounded_String);

            else
               if R.I = 0 then
                  Fail (E, "division by zero");
               end if;
               return (Kind => V_Int, I => L.I mod R.I, B => False,
                       S => Null_Unbounded_String);
            end if;

         when K_Un_Op =>
            L := Eval (E.Sub, Env);
            return (Kind => V_Int, I => -L.I, B => False,
                    S => Null_Unbounded_String);

         when others =>
            Fail (E, "internal error: unexpected expression");
            return Null_Value;
      end case;
   end Eval;

   ------------------------------------------------------------------
   --  Statements
   ------------------------------------------------------------------

   procedure Exec_Statements (S : Node_Access; Env : Env_Access) is
      C : Child_List_Access := S.Stmts;
   begin
      while C /= null loop
         Exec_Statement (C.Item, Env);
         C := C.Next;
      end loop;
   end Exec_Statements;

   procedure Exec_Statement (S : Node_Access; Env : Env_Access) is
   begin
      if S = null then
         return;
      end if;

      case S.Kind is
         when K_Var_Decl =>
            Bind_Var (Env, S.Name, Eval (S.Sub, Env));

         when K_Assign =>
            Assign_Var (Env, S.Name, Eval (S.Sub, Env));

         when K_If =>
            if Truth (Eval (S.Sub, Env), S) then
               declare
                  Block : constant Env_Access := New_Env (Env);
               begin
                  Exec_Statements (S, Block);
               end;
            end if;

         when K_While =>
            loop
               exit when not Truth (Eval (S.Sub, Env), S);
               declare
                  Block : constant Env_Access := New_Env (Env);
               begin
                  Exec_Statements (S, Block);
               end;
            end loop;

         when K_Expr_Stmt =>
            if S.Sub /= null and then S.Sub.Kind = K_Call
              and then S.Sub.Name = "ret"
            then
               if Child_Count (S.Sub) >= 1 then
                  Return_Value := Eval (Child_At (S.Sub, 1), Env);
               end if;
               raise Dash_Return;
            else
               declare
                  V : constant Value := Eval (S.Sub, Env);
                  pragma Unreferenced (V);
               begin
                  null;
               end;
            end if;

         when K_Function =>
            Bind_Func (Env, S, Env);

         when others =>
            Fail (S, "internal error: unexpected statement");
      end case;
   end Exec_Statement;

   ------------------------------------------------------------------
   --  Calling a user function
   ------------------------------------------------------------------

   function Call_User
     (F : Node_Access; Closure : Env_Access; Args : Child_List_Access;
      Caller : Env_Access)
      return Value
   is
      Call_Env : constant Env_Access := New_Env (Closure);
      P        : Child_List_Access := F.Params;
      A        : Child_List_Access := Args;
      Result   : Value := Null_Value;
   begin
      --  Bind the parameters.  The arguments belong to the caller, so
      --  they are evaluated in the environment of the caller.
      while P /= null loop
         declare
            V : Value := Null_Value;
         begin
            if A /= null then
               V := Eval (A.Item, Caller);
               A := A.Next;
            end if;
            Bind_Var (Call_Env, P.Item.Name, V);
         end;
         P := P.Next;
      end loop;

      --  The declarations of the function live in the call environment.
      declare
         D : Child_List_Access := F.Decls;
      begin
         while D /= null loop
            Exec_Statement (D.Item, Call_Env);
            D := D.Next;
         end loop;
      end;

      --  The functions written inside this one.
      declare
         D : Child_List_Access := F.Nested;
      begin
         while D /= null loop
            Bind_Func (Call_Env, D.Item, Call_Env);
            D := D.Next;
         end loop;
      end;

      --  Run the body.
      begin
         Exec_Statements (F, Call_Env);
      exception
         when Dash_Return =>
            Result := Return_Value;
      end;

      return Result;
   end Call_User;

   ------------------------------------------------------------------
   --  Run
   ------------------------------------------------------------------

   procedure Run (Program : Dash_Ast.Node_Access) is
      Main : Node_Access;
      C    : Child_List_Access;
   begin
      Global_Env := New_Env (null);

      --  Bind the top level functions.
      C := Program.Children;
      while C /= null loop
         if C.Item.Kind = K_Function then
            Bind_Func (Global_Env, C.Item, Global_Env);
         end if;
         C := C.Next;
      end loop;

      Main := null;
      C := Program.Children;
      while C /= null loop
         if C.Item.Kind = K_Function and then C.Item.Name = "main" then
            Main := C.Item;
            exit;
         end if;
         C := C.Next;
      end loop;

      if Main = null then
         raise Runtime_Error with "the program has no 'main' function";
      end if;

      declare
         V : constant Value := Call_User (Main, Global_Env, null, Global_Env);
         pragma Unreferenced (V);
      begin
         null;
      end;
   end Run;

end Dash_Vm;
