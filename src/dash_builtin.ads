------------------------------------------------------------------------------
--  Dash_Builtin -- the intrinsic functions of Dash.
--
--  Dash keeps a deliberately small reserved word set (fs is begin end let
--  int st ut).  Everything that would normally be a keyword -- printing,
--  reading, logical connectives, comparison against equality -- is provided
--  as a builtin whose name is an ordinary identifier.  The reserved word set
--  therefore stays exactly as specified, while the language still has the
--  operations a program needs.
--
--    print ( v )      write a value, no line break
--    println ( v )    write a value and a line break
--    text ( v )       int / bool -> string
--    concat ( s t )   string concatenation
--    len ( s )        length of a string
--    read ( )         read one line from standard input -> string
--    readint ( )      read one line from standard input -> int
--    abs ( n )        absolute value
--    not ( b )        logical negation
--    and ( a b )      logical conjunction
--    or ( a b )       logical disjunction
--    eq ( a b )       equality   ( '=' is reserved for assignment )
--    ne ( a b )       inequality
--    min ( a b )      smaller of two integers
--    max ( a b )      larger of two integers
--    ret ( v )        return from the enclosing function
------------------------------------------------------------------------------

with Dash_Ast;

package Dash_Builtin is

   type Builtin_Id is
     (B_None,
      B_Print,
      B_Println,
      B_Text,
      B_Concat,
      B_Len,
      B_Read,
      B_ReadInt,
      B_Abs,
      B_Not,
      B_And,
      B_Or,
      B_Eq,
      B_Ne,
      B_Min,
      B_Max,
      B_Ret);

   --  Number of arguments, -1 when the builtin accepts a variable count.
   function Arity (B : Builtin_Id) return Integer;

   --  Static result type of the builtin.
   function Result_Type (B : Builtin_Id) return Dash_Ast.Dash_Type;

   --  True when the builtin produces no value at all (a statement).
   function Is_Statement (B : Builtin_Id) return Boolean;

   --  Resolve a name, B_None when the name is not a builtin.
   function Lookup (Name : String) return Builtin_Id;

end Dash_Builtin;
