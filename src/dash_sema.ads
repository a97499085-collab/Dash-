------------------------------------------------------------------------------
--  Dash_Sema -- semantic analysis for Dash.
--
--  The analyser walks the tree produced by Dash_Parse and checks:
--
--    * every used variable is declared, and no name is declared twice;
--    * every expression has a type, and operators are applied to operands
--      of a type they accept;
--    * calls match the arity of the builtin or of the user function;
--    * the program has an entry point called 'main'.
--
--  The static type of every expression is written back into the tree, so
--  the code generator and the virtual machine can rely on it.
------------------------------------------------------------------------------

with Dash_Ast;

package Dash_Sema is

   --  Raised on a semantic error.  The message carries the position.
   Sema_Error : exception;

   --  Analyse a whole program.
   procedure Check (Program : Dash_Ast.Node_Access);

   --  True when the program defines the entry point.
   function Has_Main (Program : Dash_Ast.Node_Access) return Boolean;

   --  The node of the entry point, null when there is none.
   function Main_Node (Program : Dash_Ast.Node_Access) return Dash_Ast.Node_Access;

end Dash_Sema;
