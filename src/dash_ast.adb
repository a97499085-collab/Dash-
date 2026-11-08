------------------------------------------------------------------------------
--  Dash_Ast -- body
------------------------------------------------------------------------------

package body Dash_Ast is

   ------------------------------------------------------------------
   --  New_Node
   ------------------------------------------------------------------

   function New_Node (Kind : Node_Kind; Line : Natural := 0) return Node_Access is
      N : constant Node_Access := new Node;
   begin
      N.Line := Line;
      N.Kind := Kind;
      return N;
   end New_Node;

   ------------------------------------------------------------------
   --  Append_Child
   ------------------------------------------------------------------

   procedure Append_Child (Parent : Node_Access; Child : Node_Access) is
      C : Child_List_Access;
   begin
      if Parent = null or else Child = null then
         return;
      end if;

      if Parent.Children = null then
         Parent.Children := new Child_List'(Item => Child, Next => null);
         return;
      end if;

      C := Parent.Children;
      while C.Next /= null loop
         C := C.Next;
      end loop;
      C.Next := new Child_List'(Item => Child, Next => null);
   end Append_Child;

   ------------------------------------------------------------------
   --  Child_Count
   ------------------------------------------------------------------

   function Child_Count (N : Node_Access) return Natural is
      C  : Child_List_Access;
      Nc : Natural := 0;
   begin
      if N = null then
         return 0;
      end if;
      C := N.Children;
      while C /= null loop
         Nc := Nc + 1;
         C := C.Next;
      end loop;
      return Nc;
   end Child_Count;

   ------------------------------------------------------------------
   --  Child_At
   ------------------------------------------------------------------

   function Child_At (N : Node_Access; Index : Positive) return Node_Access is
      C  : Child_List_Access;
      Nc : Natural := 0;
   begin
      if N = null then
         return null;
      end if;
      C := N.Children;
      while C /= null loop
         Nc := Nc + 1;
         if Nc = Index then
            return C.Item;
         end if;
         C := C.Next;
      end loop;
      return null;
   end Child_At;

   ------------------------------------------------------------------
   --  Append_To
   ------------------------------------------------------------------

   procedure Append_To (List : in out Child_List_Access; Child : Node_Access) is
      C : Child_List_Access;
   begin
      if Child = null then
         return;
      end if;

      if List = null then
         List := new Child_List'(Item => Child, Next => null);
         return;
      end if;

      C := List;
      while C.Next /= null loop
         C := C.Next;
      end loop;
      C.Next := new Child_List'(Item => Child, Next => null);
   end Append_To;

   ------------------------------------------------------------------
   --  List_Count
   ------------------------------------------------------------------

   function List_Count (L : Child_List_Access) return Natural is
      C  : Child_List_Access := L;
      Nc : Natural := 0;
   begin
      while C /= null loop
         Nc := Nc + 1;
         C := C.Next;
      end loop;
      return Nc;
   end List_Count;

   ------------------------------------------------------------------
   --  List_At
   ------------------------------------------------------------------

   function List_At (L : Child_List_Access; Index : Positive) return Node_Access is
      C  : Child_List_Access := L;
      Nc : Natural := 0;
   begin
      while C /= null loop
         Nc := Nc + 1;
         if Nc = Index then
            return C.Item;
         end if;
         C := C.Next;
      end loop;
      return null;
   end List_At;

   ------------------------------------------------------------------
   --  Type_Name
   ------------------------------------------------------------------

   function Type_Name (T : Dash_Type) return String is
   begin
      case T is
         when T_Int     => return "int";
         when T_Bool    => return "bool";
         when T_String  => return "string";
         when T_Void    => return "void";
         when T_Unknown => return "unknown";
      end case;
   end Type_Name;

   ------------------------------------------------------------------
   --  Image
   ------------------------------------------------------------------

   function Image (N : Node_Access) return String is

      function Kind_Name (K : Node_Kind) return String is
      begin
         case K is
            when K_Program   => return "program";
            when K_Function  => return "function";
            when K_Var_Decl  => return "let";
            when K_Assign    => return "assign";
            when K_If        => return "st";
            when K_While     => return "ut";
            when K_Expr_Stmt => return "call";
            when K_Call      => return "call";
            when K_Bin_Op    => return "binop";
            when K_Un_Op     => return "unop";
            when K_Int_Lit   => return "int";
            when K_Str_Lit   => return "string";
            when K_Bool_Lit  => return "bool";
            when K_Var_Ref   => return "var";
         end case;
      end Kind_Name;

      function Arg_List (N : Node_Access) return String is
         C   : Child_List_Access := (if N = null then null else N.Children);
         Buf : Unbounded_String;
         Sep : constant Character := ' ';
      begin
         while C /= null loop
            Append (Buf, Sep & Image (C.Item));
            C := C.Next;
         end loop;
         return "(" & To_String (Buf) & ")";
      end Arg_List;

   begin
      if N = null then
         return "<null>";
      end if;

      case N.Kind is
         when K_Bin_Op =>
            return "(" & Image (Child_At (N, 1)) & " " & N.Op & " "
                   & Image (Child_At (N, 2)) & ")";

         when K_Un_Op =>
            return "(" & N.Op & Image (N.Sub) & ")";

         when K_Var_Ref =>
            return To_String (N.Name);

         when K_Int_Lit =>
            return Long_Long_Integer'Image (N.Int_Value);

         when K_Str_Lit =>
            return '"' & To_String (N.Str_Value) & '"';

         when K_Bool_Lit =>
            if N.Bool_Value then
               return "true";
            else
               return "false";
            end if;

         when K_Call =>
            return To_String (N.Name) & Arg_List (N);

         when K_Var_Decl | K_Assign =>
            return To_String (N.Name) & " = " & Image (N.Sub);

         when others =>
            if N.Name = Null_Unbounded_String then
               return Kind_Name (N.Kind);
            else
               return Kind_Name (N.Kind) & " " & To_String (N.Name);
            end if;
      end case;
   end Image;

end Dash_Ast;
