------------------------------------------------------------------------------
--  Dash_Vm -- the Dash virtual machine.
--
--  A tree walking interpreter for Dash programs.  The DCM uses it for
--  'dcm run', which needs no external tool chain, and as the reference
--  semantics against which the native code generator is checked.
--
--  Values are integers (64 bit), booleans and strings.
------------------------------------------------------------------------------

with Dash_Ast;

package Dash_Vm is

   --  Raised on a runtime error.  The message carries the position.
   Runtime_Error : exception;

   --  Run the entry point of a program.
   procedure Run (Program : Dash_Ast.Node_Access);

end Dash_Vm;
