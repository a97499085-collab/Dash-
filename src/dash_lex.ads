------------------------------------------------------------------------------
--  Dash_Lex -- lexical analyser for the Dash programming language.
--
--  Dash source is tokenised into the eight reserved words
--
--      fs   is   begin   end   let   int   st   ut
--
--  the punctuation set
--
--      (   )   <   >   :   =   "
--
--  the arithmetic operators
--
--      +   -   *   /   %
--
--  and the literal forms: identifiers, decimal / hexadecimal / binary
--  integers and double quoted strings.
--
--  Two conventions are worth pointing out:
--
--    * A new line terminates a statement.  Dash has no ';' and the line
--      break plays that role, which keeps the punctuation set small.
--    * '--' starts a comment up to the end of the line, exactly like Ada.
--      A double quote inside a string is written twice ("say ""hi""")
--      which is also the Ada convention.
--
--  New lines inside parentheses are not significant: a call or an
--  expression may be spread over several lines.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;

package Dash_Lex is

   use Ada.Strings.Unbounded;

   type Token_Kind is
     (Tk_EOF,
      Tk_Newline,
      Tk_Fs,
      Tk_Is,
      Tk_Begin,
      Tk_End,
      Tk_Let,
      Tk_Int,
      Tk_St,
      Tk_Ut,
      Tk_Ident,
      Tk_Int_Lit,
      Tk_Str_Lit,
      Tk_LParen,
      Tk_RParen,
      Tk_Lt,
      Tk_Gt,
      Tk_Colon,
      Tk_Assign,
      Tk_Plus,
      Tk_Minus,
      Tk_Star,
      Tk_Slash,
      Tk_Percent,
      Tk_Comma);

   type Token is record
      Kind      : Token_Kind := Tk_EOF;
      Text      : Unbounded_String := Null_Unbounded_String;
      Int_Value : Long_Long_Integer := 0;
      Line      : Natural := 0;
      Column    : Natural := 0;
   end record;

   type Token_Node;
   type Token_Node_Access is access all Token_Node;

   type Token_Node is record
      Tok  : Token;
      Next : Token_Node_Access := null;
   end record;

   type Token_List is record
      Head : Token_Node_Access := null;
      Tail : Token_Node_Access := null;
   end record;

   --  Raised when the source text cannot be tokenised.  The exception
   --  message carries the offending position.
   Lex_Error : exception;

   procedure Lex (Source : String; Tokens : out Token_List);

   function Kind_Image (K : Token_Kind) return String;

end Dash_Lex;
