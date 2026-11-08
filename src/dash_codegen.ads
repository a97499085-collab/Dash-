------------------------------------------------------------------------------
--  Dash_Codegen -- the native back end of the DCM.
--
--  A Dash program is translated into a single Ada source file which is then
--  handed to the Ada compiler.  The result is a real native executable, not
--  an interpreter loop: Dash is a compiled language.
--
--  The translation is direct:
--
--    * a Dash function  becomes an Ada function (or a procedure when it has
--      no 'ret');
--    * a Dash variable  becomes an Ada variable of the matching type,
--      Long_Long_Integer, Boolean or Unbounded_String;
--    * 'st' becomes "if ... then ... end if;",  'ut' becomes
--      "while ... loop ... end loop;";
--    * the builtins become calls to the small runtime that is written into
--      the head of the generated file.
--
--  No C is involved at any point.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;
with Dash_Ast;

package Dash_Codegen is

   use Ada.Strings.Unbounded;

   Codegen_Error : exception;

   --  Translate a whole program into Ada source.
   function Generate (Program : Dash_Ast.Node_Access) return Unbounded_String;

end Dash_Codegen;
