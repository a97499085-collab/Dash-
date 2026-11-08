------------------------------------------------------------------------------
--  Dash_Parse -- recursive descent parser for Dash.
--
--  Grammar (informal):
--
--     program     := { function }
--     function    := "fs" name [ "(" { param } ")" ] "is" { let } "begin"
--                    { statement } "end"
--     param       := name [ ":" "int" ]
--     let         := "let" name [ ":" "int" ] "=" expr
--     statement   := let
--                  | name "=" expr
--                  | "st" "(" expr ")" "begin" { statement } "end"
--                  | "ut" "(" expr ")" "begin" { statement } "end"
--                  | function
--                  | call
--     expr        := comparison
--     comparison  := additive { ( "<" | ">" ) additive }
--     additive    := term { ( "+" | "-" ) term }
--     term        := factor { ( "*" | "/" | "%" ) factor }
--     factor      := [ "-" ] primary
--     primary     := integer | string | "true" | "false"
--                  | name [ "(" { expr } ")" ] | "(" expr ")"
--
--  A new line ends a statement; there is no ';' in the language.
------------------------------------------------------------------------------

with Dash_Ast;
with Dash_Lex;

package Dash_Parse is

   --  Raised on a syntax error.  The message carries the position.
   Parse_Error : exception;

   function Parse (Tokens : Dash_Lex.Token_List) return Dash_Ast.Node_Access;

end Dash_Parse;
