------------------------------------------------------------------------------
--  Dash_Ast -- Abstract syntax tree for the Dash programming language.
--
--  Dash is a small systems-level language whose surface syntax is Ada
--  flavoured and whose implementation (the DCM -- Dash Compiler Machine) is
--  written in pure Ada.
--
--  The tree is intentionally flat: a single record carries every field the
--  different node kinds need, and the child collections are intrusive
--  linked lists.  That keeps the tree free of any controlled (finalizable)
--  component, so nodes can be allocated on the heap without the accessibility
--  and finalization corner cases of Ada.Containers.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;

package Dash_Ast is

   use Ada.Strings.Unbounded;

   ------------------------------------------------------------------
   --  Node kinds
   ------------------------------------------------------------------

   type Node_Kind is
     (K_Program,      --  root, children = top level functions
      K_Function,     --  Name, Params, Decls, Stmts
      K_Var_Decl,     --  Name, Sub = initialiser
      K_Assign,       --  Name, Sub = value
      K_If,           --  Sub = condition, Stmts = body   (st)
      K_While,        --  Sub = condition, Stmts = body   (ut)
      K_Expr_Stmt,    --  Sub = expression
      K_Call,         --  Name, Children = arguments
      K_Bin_Op,       --  Op, Children (1) = left, (2) = right
      K_Un_Op,        --  Op, Sub = operand
      K_Int_Lit,      --  Int_Value
      K_Str_Lit,      --  Str_Value
      K_Bool_Lit,     --  Bool_Value
      K_Var_Ref);     --  Name

   ------------------------------------------------------------------
   --  Dash types
   ------------------------------------------------------------------

   type Dash_Type is (T_Int, T_Bool, T_String, T_Void, T_Unknown);

   ------------------------------------------------------------------
   --  Tree nodes
   ------------------------------------------------------------------

   type Node;
   type Node_Access is access all Node;

   type Child_List;
   type Child_List_Access is access all Child_List;

   type Child_List is record
      Item : Node_Access := null;
      Next : Child_List_Access := null;
   end record;

   type Node is record
      Line       : Natural := 0;
      Kind       : Node_Kind := K_Program;

      --  Static type, filled in by the semantic analyser.
      Typ        : Dash_Type := T_Unknown;

      --  The result type written by the programmer, for a function.
      Ann_Typ    : Dash_Type := T_Unknown;

      Name       : Unbounded_String := Null_Unbounded_String;
      Op         : Character := ' ';
      Int_Value  : Long_Long_Integer := 0;
      Str_Value  : Unbounded_String := Null_Unbounded_String;
      Bool_Value : Boolean := False;

      --  Children: K_Bin_Op operands, K_Call arguments.
      Children   : Child_List_Access := null;

      --  Parameters of a function (K_Function).
      Params     : Child_List_Access := null;

      --  Declarations of a function (K_Function), the part before 'begin'.
      Decls      : Child_List_Access := null;

      --  Functions written inside a function, before its 'begin'.
      Nested     : Child_List_Access := null;

      --  Statement sequence of a function, an 'st' block or an 'ut' block.
      Stmts      : Child_List_Access := null;

      --  Single sub node: initialiser, value, condition, operand.
      Sub        : Node_Access := null;
   end record;

   ------------------------------------------------------------------
   --  Helpers
   ------------------------------------------------------------------

   function New_Node (Kind : Node_Kind; Line : Natural := 0) return Node_Access;

   procedure Append_Child (Parent : Node_Access; Child : Node_Access);

   function Child_Count (N : Node_Access) return Natural;

   function Child_At (N : Node_Access; Index : Positive) return Node_Access;

   --  Append to, and walk, any of the child lists of a node.
   procedure Append_To (List : in out Child_List_Access; Child : Node_Access);

   function List_Count (L : Child_List_Access) return Natural;

   function List_At (L : Child_List_Access; Index : Positive) return Node_Access;

   function Type_Name (T : Dash_Type) return String;

   function Image (N : Node_Access) return String;

end Dash_Ast;
