------------------------------------------------------------------------------
--  Dash_Sema -- body
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;
with Dash_Builtin;

package body Dash_Sema is

   use Ada.Strings.Unbounded;
   use Dash_Ast;
   use Dash_Builtin;

   ------------------------------------------------------------------
   --  Symbols and scopes
   ------------------------------------------------------------------

   type Sym_Entry;
   type Sym_Access is access all Sym_Entry;

   type Sym_Entry is record
      Name        : Unbounded_String := Null_Unbounded_String;
      Typ         : Dash_Type := T_Unknown;
      Func        : Node_Access := null;      --  set for a nested function
      Return_Type : Dash_Type := T_Unknown;   --  result type of a function
      Next        : Sym_Access := null;
   end record;

   type Scope;
   type Scope_Access is access all Scope;

   type Scope is record
      Parent  : Scope_Access := null;
      Symbols : Sym_Access := null;
   end record;

   type Func_Entry;
   type Func_Access is access all Func_Entry;

   type Func_Entry is record
      Name        : Unbounded_String := Null_Unbounded_String;
      Node        : Node_Access := null;
      Arity       : Natural := 0;
      Return_Type : Dash_Type := T_Unknown;
      Next        : Func_Access := null;
   end record;

   Current_Scope : Scope_Access := null;
   Funcs         : Func_Access := null;
   Lenient       : Boolean := False;
   Body_Return   : Dash_Type := T_Unknown;
   Body_Has_Ret  : Boolean := False;

   ------------------------------------------------------------------
   --  Diagnostics
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
      raise Sema_Error with "line" & Natural'Image (Line_Of (N)) & ": " & Msg;
   end Fail;

   ------------------------------------------------------------------
   --  Scope handling
   ------------------------------------------------------------------

   procedure Push_Scope is
   begin
      Current_Scope :=
        new Scope'(Parent => Current_Scope, Symbols => null);
   end Push_Scope;

   procedure Pop_Scope is
   begin
      if Current_Scope /= null then
         Current_Scope := Current_Scope.Parent;
      end if;
   end Pop_Scope;

   function Lookup_Local (Name : Unbounded_String) return Sym_Access is
      S : Sym_Access := null;
   begin
      if Current_Scope = null then
         return null;
      end if;
      S := Current_Scope.Symbols;
      while S /= null loop
         if S.Name = Name then
            return S;
         end if;
         S := S.Next;
      end loop;
      return null;
   end Lookup_Local;

   function Lookup (Name : Unbounded_String) return Sym_Access is
      Sc : Scope_Access := Current_Scope;
      S  : Sym_Access := null;
   begin
      while Sc /= null loop
         S := Sc.Symbols;
         while S /= null loop
            if S.Name = Name then
               return S;
            end if;
            S := S.Next;
         end loop;
         Sc := Sc.Parent;
      end loop;
      return null;
   end Lookup;

   procedure Declare_Var
     (N : Node_Access; Name : Unbounded_String; Typ : Dash_Type)
   is
   begin
      if Lookup_Local (Name) /= null then
         Fail (N, "'" & To_String (Name) & "' is already declared in this scope");
      end if;

      Current_Scope.Symbols :=
        new Sym_Entry'(Name        => Name,
                       Typ         => Typ,
                       Func        => null,
                       Return_Type => T_Unknown,
                       Next        => Current_Scope.Symbols);
   end Declare_Var;

   procedure Declare_Func (F : Node_Access) is
   begin
      if Lookup_Local (F.Name) /= null then
         Fail (F, "'" & To_String (F.Name) & "' is already declared in this scope");
      end if;

      Current_Scope.Symbols :=
        new Sym_Entry'(Name        => F.Name,
                       Typ         => T_Unknown,
                       Func        => F,
                       Return_Type => T_Unknown,
                       Next        => Current_Scope.Symbols);
   end Declare_Func;

   ------------------------------------------------------------------
   --  Function registry (top level functions)
   ------------------------------------------------------------------

   procedure Register_Function (F : Node_Access) is
      E : Func_Access := Funcs;
      New_E : Func_Access;
   begin
      while E /= null loop
         if E.Name = F.Name then
            Fail (F, "'" & To_String (F.Name) & "' is defined more than once");
         end if;
         E := E.Next;
      end loop;

      New_E :=
        new Func_Entry'(Name        => F.Name,
                        Node        => F,
                        Arity       => List_Count (F.Params),
                        Return_Type => T_Unknown,
                        Next        => null);

      if Funcs = null then
         Funcs := New_E;
      else
         E := Funcs;
         while E.Next /= null loop
            E := E.Next;
         end loop;
         E.Next := New_E;
      end if;
   end Register_Function;

   function Find_Function (Name : Unbounded_String) return Node_Access is
      S : constant Sym_Access := Lookup (Name);
      E : Func_Access := Funcs;
   begin
      if S /= null and then S.Func /= null then
         return S.Func;
      end if;

      while E /= null loop
         if E.Name = Name then
            return E.Node;
         end if;
         E := E.Next;
      end loop;
      return null;
   end Find_Function;

   function Return_Type_Of (Name : Unbounded_String) return Dash_Type is
      S : constant Sym_Access := Lookup (Name);
      E : Func_Access := Funcs;
   begin
      if S /= null and then S.Func /= null then
         return S.Return_Type;
      end if;

      while E /= null loop
         if E.Name = Name then
            return E.Return_Type;
         end if;
         E := E.Next;
      end loop;
      return T_Unknown;
   end Return_Type_Of;

   procedure Set_Return_Type (Name : Unbounded_String; T : Dash_Type) is
      S : Sym_Access := Lookup (Name);
      E : Func_Access := Funcs;
   begin
      if S /= null and then S.Func /= null then
         S.Return_Type := T;
         return;
      end if;

      while E /= null loop
         if E.Name = Name then
            E.Return_Type := T;
            return;
         end if;
         E := E.Next;
      end loop;
   end Set_Return_Type;

   ------------------------------------------------------------------
   --  Forward declarations
   ------------------------------------------------------------------

   function Check_Expr (E : Node_Access) return Dash_Type;

   procedure Check_Statement (S : Node_Access);

   procedure Check_Var_Decl (D : Node_Access);

   procedure Check_Function_Body (F : Node_Access);

   ------------------------------------------------------------------
   --  Builtin calls
   ------------------------------------------------------------------

   procedure Check_Builtin_Call
     (E : Node_Access; B : Dash_Builtin.Builtin_Id; Args : Natural)
   is
      Expected : constant Integer := Dash_Builtin.Arity (B);
      TL : Dash_Type := T_Unknown;
      Ignored : Dash_Type := T_Unknown;
      TR : Dash_Type := T_Unknown;
   begin
      if Expected >= 0 and then Args /= Natural (Expected) and then not Lenient then
         Fail (E, "'" & To_String (E.Name) & "' expects "
               & Natural'Image (Natural (Expected)) & " argument(s) but "
               & Natural'Image (Args) & " were given");
      end if;

      case B is
         when Dash_Builtin.B_Print | Dash_Builtin.B_Println =>
            if Args > 0 then
               Ignored := Check_Expr (Child_At (E, 1));
            end if;

         when Dash_Builtin.B_Text =>
            if Args > 0 then
               TL := Check_Expr (Child_At (E, 1));
               if TL = T_Void and then not Lenient then
                  Fail (E, "'text' needs a value to convert");
               end if;
            end if;

         when Dash_Builtin.B_Concat =>
            if Args >= 2 then
               TL := Check_Expr (Child_At (E, 1));
               TR := Check_Expr (Child_At (E, 2));
               if not Lenient then
                  if TL = T_String and then TR /= T_String then
                     Fail (E, "'concat' joins two strings");
                  elsif TR = T_String and then TL /= T_String then
                     Fail (E, "'concat' joins two strings");
                  end if;
               end if;
            end if;

         when Dash_Builtin.B_Len =>
            if Args > 0 then
               TL := Check_Expr (Child_At (E, 1));
               if TL /= T_String and then TL /= T_Unknown and then not Lenient then
                  Fail (E, "'len' needs a string");
               end if;
            end if;

         when Dash_Builtin.B_Abs =>
            if Args > 0 then
               TL := Check_Expr (Child_At (E, 1));
               if TL /= T_Int and then TL /= T_Unknown and then not Lenient then
                  Fail (E, "'abs' needs an int");
               end if;
            end if;

         when Dash_Builtin.B_Not =>
            if Args > 0 then
               TL := Check_Expr (Child_At (E, 1));
               if TL /= T_Bool and then TL /= T_Unknown and then not Lenient then
                  Fail (E, "'not' needs a bool");
               end if;
            end if;

         when Dash_Builtin.B_And | Dash_Builtin.B_Or =>
            if Args >= 2 then
               TL := Check_Expr (Child_At (E, 1));
               TR := Check_Expr (Child_At (E, 2));
               if not Lenient then
                  if TL /= T_Bool and then TL /= T_Unknown then
                     Fail (E, "'" & To_String (E.Name) & "' needs two bool values");
                  elsif TR /= T_Bool and then TR /= T_Unknown then
                     Fail (E, "'" & To_String (E.Name) & "' needs two bool values");
                  end if;
               end if;
            end if;

         when Dash_Builtin.B_Eq | Dash_Builtin.B_Ne =>
            if Args >= 2 then
               TL := Check_Expr (Child_At (E, 1));
               TR := Check_Expr (Child_At (E, 2));
               if TL /= T_Unknown and then TR /= T_Unknown
                 and then TL /= TR and then not Lenient
               then
                  Fail (E, "cannot compare a " & Type_Name (TL)
                        & " with a " & Type_Name (TR));
               end if;
            end if;

         when Dash_Builtin.B_Min | Dash_Builtin.B_Max =>
            if Args >= 2 then
               TL := Check_Expr (Child_At (E, 1));
               TR := Check_Expr (Child_At (E, 2));
               if not Lenient then
                  if TL /= T_Int and then TL /= T_Unknown then
                     Fail (E, "'" & To_String (E.Name) & "' needs two int values");
                  elsif TR /= T_Int and then TR /= T_Unknown then
                     Fail (E, "'" & To_String (E.Name) & "' needs two int values");
                  end if;
               end if;
            end if;

         when Dash_Builtin.B_Ret =>
            Body_Has_Ret := True;
            if Args > 0 then
               TL := Check_Expr (Child_At (E, 1));
               if Body_Return = T_Unknown then
                  Body_Return := TL;
               end if;
            end if;

         when others =>
            null;
      end case;
   end Check_Builtin_Call;

   ------------------------------------------------------------------
   --  Check_Expr
   ------------------------------------------------------------------

   function Check_Expr (E : Node_Access) return Dash_Type is
      L  : Node_Access;
      R  : Node_Access;
      TL : Dash_Type := T_Unknown;
      Ignored : Dash_Type := T_Unknown;
      TR : Dash_Type := T_Unknown;
      B  : Dash_Builtin.Builtin_Id;
      F  : Node_Access;
   begin
      if E = null then
         return T_Unknown;
      end if;

      case E.Kind is
         when K_Int_Lit =>
            E.Typ := T_Int;
            return T_Int;

         when K_Str_Lit =>
            E.Typ := T_String;
            return T_String;

         when K_Bool_Lit =>
            E.Typ := T_Bool;
            return T_Bool;

         when K_Var_Ref =>
            declare
               Sym : constant Sym_Access := Lookup (E.Name);
            begin
               if Sym = null or else Sym.Func /= null then
                  Fail (E, "'" & To_String (E.Name) & "' is not declared");
               end if;
               E.Typ := Sym.Typ;
               return Sym.Typ;
            end;

         when K_Call =>
            B := Dash_Builtin.Lookup (To_String (E.Name));

            if B /= Dash_Builtin.B_None then
               Check_Builtin_Call (E, B, Child_Count (E));
               E.Typ := Dash_Builtin.Result_Type (B);
               return E.Typ;
            end if;

            F := Find_Function (E.Name);
            if F = null then
               Fail (E, "'" & To_String (E.Name) & "' is not a known function");
            end if;

            declare
               Expected : constant Natural := List_Count (F.Params);
               C        : Child_List_Access := E.Children;
               P        : Child_List_Access := F.Params;
            begin
               if Expected /= Child_Count (E) and then not Lenient then
                  Fail (E, "'" & To_String (E.Name) & "' expects "
                        & Natural'Image (Expected) & " argument(s) but "
                        & Natural'Image (Child_Count (E)) & " were given");
               end if;

               --  The parameters of a Dash function are integers.
               while C /= null and then P /= null loop
                  declare
                     Arg_Type : constant Dash_Type := Check_Expr (C.Item);
                  begin
                     if Arg_Type /= T_Unknown and then Arg_Type /= T_Int and then not Lenient then
                        Fail (C.Item, "the parameter '" & To_String (P.Item.Name)
                              & "' is an int, but a " & Type_Name (Arg_Type)
                              & " was given");
                     end if;
                  end;
                  C := C.Next;
                  P := P.Next;
               end loop;
            end;

            declare
               RT : constant Dash_Type := Return_Type_Of (E.Name);
            begin
               E.Typ := RT;
               return RT;
            end;

         when K_Bin_Op =>
            L  := Child_At (E, 1);
            R  := Child_At (E, 2);
            TL := Check_Expr (L);
            TR := Check_Expr (R);

            if E.Op = '<' or else E.Op = '>' then
               if (TL = T_Int and TR = T_Int)
                 or else (TL = T_String and TR = T_String)
               then
                  E.Typ := T_Bool;
               elsif TL /= T_Unknown and TR /= T_Unknown and not Lenient then
                  Fail (E, "cannot compare " & Type_Name (TL)
                        & " with " & Type_Name (TR));
               else
                  E.Typ := T_Bool;
               end if;
               return E.Typ;

            elsif E.Op = '+' then
               if TL = T_Int and TR = T_Int then
                  E.Typ := T_Int;
               elsif TL = T_String and TR = T_String then
                  E.Typ := T_String;
               elsif TL /= T_Unknown and TR /= T_Unknown and not Lenient then
                  Fail (E, "cannot add " & Type_Name (TL)
                        & " and " & Type_Name (TR));
               else
                  E.Typ := T_Unknown;
               end if;
               return E.Typ;

            else
               --  '-', '*', '/', '%'
               if TL = T_Int and TR = T_Int then
                  E.Typ := T_Int;
               elsif TL /= T_Unknown and TR /= T_Unknown and not Lenient then
                  Fail (E, "cannot apply '" & E.Op & "' to "
                        & Type_Name (TL) & " and " & Type_Name (TR));
               else
                  E.Typ := T_Unknown;
               end if;
               return E.Typ;
            end if;

         when K_Un_Op =>
            TL := Check_Expr (E.Sub);
            if TL = T_Int then
               E.Typ := T_Int;
            elsif TL /= T_Unknown and then not Lenient then
               Fail (E, "cannot negate a " & Type_Name (TL));
            else
               E.Typ := T_Unknown;
            end if;
            return E.Typ;

         when others =>
            Fail (E, "internal error: unexpected expression");
            return T_Unknown;
      end case;
   end Check_Expr;

   ------------------------------------------------------------------
   --  Check_Var_Decl
   ------------------------------------------------------------------

   procedure Check_Var_Decl (D : Node_Access) is
      T : Dash_Type;
   begin
      T := Check_Expr (D.Sub);

      if D.Typ = T_Unknown then
         D.Typ := T;
      else
         if T /= T_Unknown and then T /= D.Typ and then not Lenient then
            Fail (D, "'" & To_String (D.Name) & "' is declared as "
                   & Type_Name (D.Typ) & " but the initialiser is a "
                   & Type_Name (T));
         end if;
      end if;

      Declare_Var (D, D.Name, D.Typ);
   end Check_Var_Decl;

   ------------------------------------------------------------------
   --  Check_Statement
   ------------------------------------------------------------------

   procedure Check_Statement (S : Node_Access) is
      T : Dash_Type;
      C : Child_List_Access;
   begin
      if S = null then
         return;
      end if;

      case S.Kind is
         when K_Var_Decl =>
            Check_Var_Decl (S);

         when K_Assign =>
            declare
               Sym : constant Sym_Access := Lookup (S.Name);
            begin
               if Sym = null or else Sym.Func /= null then
                  Fail (S, "'" & To_String (S.Name) & "' is not declared");
               end if;

               T := Check_Expr (S.Sub);

               if T /= T_Unknown and then Sym.Typ /= T_Unknown
                 and then Sym.Typ /= T and then not Lenient
               then
                  Fail (S, "cannot assign a " & Type_Name (T)
                        & " to '" & To_String (S.Name) & "', which is a "
                        & Type_Name (Sym.Typ));
               end if;

               S.Typ := Sym.Typ;
            end;

         when K_If | K_While =>
            T := Check_Expr (S.Sub);
            if T /= T_Unknown and then T /= T_Bool and then T /= T_Int
              and then not Lenient
            then
               Fail (S, "the condition must be a bool or an int, not a "
                     & Type_Name (T));
            end if;

            Push_Scope;
            C := S.Stmts;
            while C /= null loop
               Check_Statement (C.Item);
               C := C.Next;
            end loop;
            Pop_Scope;

         when K_Expr_Stmt =>
            S.Typ := Check_Expr (S.Sub);

         when K_Function =>
            Declare_Func (S);
            Check_Function_Body (S);

         when others =>
            Fail (S, "internal error: unexpected statement");
      end case;
   end Check_Statement;

   ------------------------------------------------------------------
   --  Check_Function_Body
   ------------------------------------------------------------------

   procedure Check_Function_Body (F : Node_Access) is
      Saved_Return : constant Dash_Type := Body_Return;
      Saved_Has    : constant Boolean := Body_Has_Ret;
      C            : Child_List_Access;
      Ret          : Dash_Type := T_Unknown;
      Has_Ret      : Boolean := False;
   begin
      Body_Return  := T_Unknown;
      Body_Has_Ret := False;

      Push_Scope;

      --  Parameters.
      C := F.Params;
      while C /= null loop
         Declare_Var (C.Item, C.Item.Name, T_Int);
         C := C.Next;
      end loop;

      --  Declarations, the part between 'is' and 'begin'.
      C := F.Decls;
      while C /= null loop
         Check_Var_Decl (C.Item);
         C := C.Next;
      end loop;

      --  Functions written inside this one.  They are declared before the
      --  body is looked at, so that the body may call them.
      C := F.Nested;
      while C /= null loop
         Declare_Func (C.Item);
         C := C.Next;
      end loop;

      C := F.Nested;
      while C /= null loop
         Check_Function_Body (C.Item);
         C := C.Next;
      end loop;

      --  Body.
      C := F.Stmts;
      while C /= null loop
         Check_Statement (C.Item);
         C := C.Next;
      end loop;

      Pop_Scope;

      Ret     := Body_Return;
      Has_Ret := Body_Has_Ret;

      Body_Return  := Saved_Return;
      Body_Has_Ret := Saved_Has;

      if F.Ann_Typ /= T_Unknown then
         --  The programmer wrote the result type out.
         if Has_Ret and then Ret /= T_Unknown and then Ret /= F.Ann_Typ
           and then not Lenient
         then
            Fail (F, "'" & To_String (F.Name) & "' returns a "
                  & Type_Name (Ret) & " but is declared as "
                  & Type_Name (F.Ann_Typ));
         end if;
         Ret := F.Ann_Typ;

      elsif Has_Ret then
         if Ret = T_Unknown and then not Lenient then
            Fail (F, "the result type of '" & To_String (F.Name)
                  & "' cannot be worked out; write ': int' after the header");
         end if;

      else
         --  A function without a 'ret' is a procedure.
         Ret := T_Void;
      end if;

      F.Typ := Ret;
      Set_Return_Type (F.Name, Ret);
   end Check_Function_Body;

   ------------------------------------------------------------------
   --  Check
   ------------------------------------------------------------------

   procedure Check (Program : Dash_Ast.Node_Access) is
      C   : Child_List_Access := Program.Children;
      Main : Node_Access;
   begin
      Funcs         := null;
      Current_Scope := null;
      Body_Return   := T_Unknown;
      Body_Has_Ret  := False;

      --  Pass 1: register the top level functions.
      while C /= null loop
         if C.Item.Kind = K_Function then
            Register_Function (C.Item);
         end if;
         C := C.Next;
      end loop;

      --  Pass 2: a lenient pass that works out the result types of the
      --  functions.  A recursive function cannot know its own type yet,
      --  so the first pass is allowed to be incomplete.
      Lenient := True;
      C := Program.Children;
      while C /= null loop
         if C.Item.Kind = K_Function then
            Push_Scope;
            Check_Function_Body (C.Item);
            Pop_Scope;
         end if;
         C := C.Next;
      end loop;

      --  Pass 3: the real check, now that the result types are known.
      Lenient := False;
      C := Program.Children;
      while C /= null loop
         if C.Item.Kind = K_Function then
            Push_Scope;
            Check_Function_Body (C.Item);
            Pop_Scope;
         end if;
         C := C.Next;
      end loop;

      Main := Main_Node (Program);
      if Main = null then
         raise Sema_Error with "the program has no 'main' function";
      end if;

      if List_Count (Main.Params) /= 0 then
         Fail (Main, "'main' must not take parameters");
      end if;
   end Check;

   ------------------------------------------------------------------
   --  Has_Main / Main_Node
   ------------------------------------------------------------------

   function Main_Node (Program : Dash_Ast.Node_Access) return Dash_Ast.Node_Access is
      C : Child_List_Access := null;
   begin
      if Program = null then
         return null;
      end if;
      C := Program.Children;
      while C /= null loop
         if C.Item.Kind = K_Function and then C.Item.Name = "main" then
            return C.Item;
         end if;
         C := C.Next;
      end loop;
      return null;
   end Main_Node;

   function Has_Main (Program : Dash_Ast.Node_Access) return Boolean is
   begin
      return Main_Node (Program) /= null;
   end Has_Main;

end Dash_Sema;
