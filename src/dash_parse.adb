------------------------------------------------------------------------------
--  Dash_Parse -- body
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;

package body Dash_Parse is

   use Ada.Strings.Unbounded;
   use Dash_Ast;
   use Dash_Lex;

   ------------------------------------------------------------------
   --  Token cursor
   ------------------------------------------------------------------

   Cur : Dash_Lex.Token_Node_Access := null;
   Nxt : Dash_Lex.Token_Node_Access := null;

   function Kind return Dash_Lex.Token_Kind is
   begin
      if Cur = null then
         return Dash_Lex.Tk_EOF;
      else
         return Cur.Tok.Kind;
      end if;
   end Kind;

   function Peek_Kind return Dash_Lex.Token_Kind is
   begin
      if Nxt = null then
         return Dash_Lex.Tk_EOF;
      else
         return Nxt.Tok.Kind;
      end if;
   end Peek_Kind;

   function Here return Natural is
   begin
      if Cur = null then
         return 0;
      else
         return Cur.Tok.Line;
      end if;
   end Here;

   function Here_Column return Natural is
   begin
      if Cur = null then
         return 0;
      else
         return Cur.Tok.Column;
      end if;
   end Here_Column;

   procedure Advance is
   begin
      if Nxt = null then
         Cur := null;
      else
         Cur := Nxt;
         Nxt := Cur.Next;
      end if;
   end Advance;

   procedure Fail (Msg : String) is
   begin
      raise Parse_Error with "line" & Natural'Image (Here) & ", column"
        & Natural'Image (Here_Column) & ": " & Msg;
   end Fail;

   procedure Skip_Newlines is
   begin
      while Kind = Dash_Lex.Tk_Newline loop
         Advance;
      end loop;
   end Skip_Newlines;

   procedure Expect (K : Dash_Lex.Token_Kind; What : String := "") is
      Wanted : constant String :=
        (if What = "" then Dash_Lex.Kind_Image (K) else What);
   begin
      if Kind /= K then
         Fail ("expected " & Wanted & " but found "
               & Dash_Lex.Kind_Image (Kind));
      end if;
      Advance;
   end Expect;

   ------------------------------------------------------------------
   --  Forward declarations (the statement and function rules recurse)
   ------------------------------------------------------------------

   function Parse_Expr return Node_Access;
   function Parse_Primary return Node_Access;
   function Parse_Statement return Node_Access;
   function Parse_Function return Node_Access;

   procedure Parse_Statements
     (Stop : Dash_Lex.Token_Kind; Into : out Child_List_Access);

   ------------------------------------------------------------------
   --  Parse_Args
   ------------------------------------------------------------------

   procedure Parse_Args (Into : out Child_List_Access) is
      E : Node_Access;
   begin
      --  The opening parenthesis has already been consumed.
      if Kind = Dash_Lex.Tk_RParen then
         Advance;
         return;
      end if;

      loop
         E := Parse_Expr;
         Append_To (Into, E);

         if Kind = Dash_Lex.Tk_Comma then
            Advance;
         elsif Kind = Dash_Lex.Tk_RParen then
            Advance;
            exit;
         elsif Kind = Dash_Lex.Tk_EOF then
            Fail ("unterminated argument list");
         end if;
         --  Otherwise the arguments are separated by white space only.
      end loop;
   end Parse_Args;

   ------------------------------------------------------------------
   --  Parse_Primary
   ------------------------------------------------------------------

   function Parse_Primary return Node_Access is
      L : constant Natural := Here;
   begin
      case Kind is
         when Dash_Lex.Tk_Int_Lit =>
            declare
               N : constant Node_Access := New_Node (K_Int_Lit, L);
            begin
               N.Int_Value := Cur.Tok.Int_Value;
               Advance;
               return N;
            end;

         when Dash_Lex.Tk_Str_Lit =>
            declare
               N : constant Node_Access := New_Node (K_Str_Lit, L);
            begin
               N.Str_Value := Cur.Tok.Text;
               Advance;
               return N;
            end;

         when Dash_Lex.Tk_Ident =>
            declare
               Name : constant Unbounded_String := Cur.Tok.Text;
            begin
               Advance;

               if Kind = Dash_Lex.Tk_LParen then
                  declare
                     N : constant Node_Access := New_Node (K_Call, L);
                     Args : Child_List_Access := null;
                  begin
                     N.Name := Name;
                     Advance;
                     Parse_Args (Args);
                     N.Children := Args;
                     return N;
                  end;

               elsif Name = "true" then
                  declare
                     N : constant Node_Access := New_Node (K_Bool_Lit, L);
                  begin
                     N.Bool_Value := True;
                     return N;
                  end;

               elsif Name = "false" then
                  declare
                     N : constant Node_Access := New_Node (K_Bool_Lit, L);
                  begin
                     N.Bool_Value := False;
                     return N;
                  end;

               else
                  declare
                     N : constant Node_Access := New_Node (K_Var_Ref, L);
                  begin
                     N.Name := Name;
                     return N;
                  end;
               end if;
            end;

         when Dash_Lex.Tk_LParen =>
            declare
               E : Node_Access;
            begin
               Advance;
               E := Parse_Expr;
               Expect (Dash_Lex.Tk_RParen, "')'");
               return E;
            end;

         when others =>
            Fail ("unexpected " & Dash_Lex.Kind_Image (Kind)
                  & " in expression");
            return null;
      end case;
   end Parse_Primary;

   ------------------------------------------------------------------
   --  Parse_Unary
   ------------------------------------------------------------------

   function Parse_Unary return Node_Access is
      L : constant Natural := Here;
   begin
      if Kind = Dash_Lex.Tk_Minus then
         declare
            N : constant Node_Access := New_Node (K_Un_Op, L);
         begin
            N.Op := '-';
            Advance;
            N.Sub := Parse_Unary;
            return N;
         end;
      else
         return Parse_Primary;
      end if;
   end Parse_Unary;

   ------------------------------------------------------------------
   --  Parse_Term
   ------------------------------------------------------------------

   function Parse_Term return Node_Access is
      Left : Node_Access := Parse_Unary;
   begin
      while Kind = Dash_Lex.Tk_Star
        or else Kind = Dash_Lex.Tk_Slash
        or else Kind = Dash_Lex.Tk_Percent
      loop
         declare
            N : constant Node_Access := New_Node (K_Bin_Op, Here);
         begin
            if Kind = Dash_Lex.Tk_Star then
               N.Op := '*';
            elsif Kind = Dash_Lex.Tk_Slash then
               N.Op := '/';
            else
               N.Op := '%';
            end if;

            Advance;
            Append_Child (N, Left);
            Append_Child (N, Parse_Unary);
            Left := N;
         end;
      end loop;
      return Left;
   end Parse_Term;

   ------------------------------------------------------------------
   --  Parse_Additive
   ------------------------------------------------------------------

   function Parse_Additive return Node_Access is
      Left : Node_Access := Parse_Term;
   begin
      while Kind = Dash_Lex.Tk_Plus or else Kind = Dash_Lex.Tk_Minus loop
         declare
            N : constant Node_Access := New_Node (K_Bin_Op, Here);
         begin
            if Kind = Dash_Lex.Tk_Plus then
               N.Op := '+';
            else
               N.Op := '-';
            end if;

            Advance;
            Append_Child (N, Left);
            Append_Child (N, Parse_Term);
            Left := N;
         end;
      end loop;
      return Left;
   end Parse_Additive;

   ------------------------------------------------------------------
   --  Parse_Comparison
   ------------------------------------------------------------------

   function Parse_Comparison return Node_Access is
      Left : Node_Access := Parse_Additive;
   begin
      while Kind = Dash_Lex.Tk_Lt or else Kind = Dash_Lex.Tk_Gt loop
         declare
            N : constant Node_Access := New_Node (K_Bin_Op, Here);
         begin
            if Kind = Dash_Lex.Tk_Lt then
               N.Op := '<';
            else
               N.Op := '>';
            end if;

            Advance;
            Append_Child (N, Left);
            Append_Child (N, Parse_Additive);
            Left := N;
         end;
      end loop;
      return Left;
   end Parse_Comparison;

   ------------------------------------------------------------------
   --  Parse_Expr
   ------------------------------------------------------------------

   function Parse_Expr return Node_Access is
      Left : Node_Access := Parse_Comparison;
   begin
      return Left;
   end Parse_Expr;

   ------------------------------------------------------------------
   --  Parse_Var_Decl
   ------------------------------------------------------------------

   function Parse_Var_Decl return Node_Access is
      L : constant Natural := Here;
      D : constant Node_Access := New_Node (K_Var_Decl, L);
   begin
      Advance;                                     --  'let'

      if Kind /= Dash_Lex.Tk_Ident then
         Fail ("expected a variable name after 'let'");
      end if;
      D.Name := Cur.Tok.Text;
      Advance;

      if Kind = Dash_Lex.Tk_Colon then
         Advance;
         if Kind /= Dash_Lex.Tk_Int then
            Fail ("only the type 'int' may be written here");
         end if;
         D.Typ := T_Int;
         Advance;
      end if;

      if Kind /= Dash_Lex.Tk_Assign then
         Fail ("expected '=' in the declaration of '"
               & To_String (D.Name) & "'");
      end if;
      Advance;

      D.Sub := Parse_Expr;
      return D;
   end Parse_Var_Decl;

   ------------------------------------------------------------------
   --  Parse_If
   ------------------------------------------------------------------

   function Parse_If return Node_Access is
      L : constant Natural := Here;
      N : constant Node_Access := New_Node (K_If, L);
   begin
      Advance;                                     --  'st'

      if Kind /= Dash_Lex.Tk_LParen then
         Fail ("expected '(' after 'st'");
      end if;
      Advance;

      N.Sub := Parse_Expr;

      if Kind /= Dash_Lex.Tk_RParen then
         Fail ("expected ')' after the condition");
      end if;
      Advance;

      Skip_Newlines;
      if Kind /= Dash_Lex.Tk_Begin then
         Fail ("expected 'begin' after the condition");
      end if;
      Advance;

      Parse_Statements (Dash_Lex.Tk_End, N.Stmts);

      if Kind /= Dash_Lex.Tk_End then
         Fail ("expected 'end' to close the block");
      end if;
      Advance;
      return N;
   end Parse_If;

   ------------------------------------------------------------------
   --  Parse_While
   ------------------------------------------------------------------

   function Parse_While return Node_Access is
      L : constant Natural := Here;
      N : constant Node_Access := New_Node (K_While, L);
   begin
      Advance;                                     --  'ut'

      if Kind /= Dash_Lex.Tk_LParen then
         Fail ("expected '(' after 'ut'");
      end if;
      Advance;

      N.Sub := Parse_Expr;

      if Kind /= Dash_Lex.Tk_RParen then
         Fail ("expected ')' after the condition");
      end if;
      Advance;

      Skip_Newlines;
      if Kind /= Dash_Lex.Tk_Begin then
         Fail ("expected 'begin' after the condition");
      end if;
      Advance;

      Parse_Statements (Dash_Lex.Tk_End, N.Stmts);

      if Kind /= Dash_Lex.Tk_End then
         Fail ("expected 'end' to close the block");
      end if;
      Advance;
      return N;
   end Parse_While;

   ------------------------------------------------------------------
   --  Parse_Statements
   ------------------------------------------------------------------

   procedure Parse_Statements
     (Stop : Dash_Lex.Token_Kind; Into : out Child_List_Access)
   is
      S : Node_Access;
   begin
      loop
         Skip_Newlines;
         exit when Kind = Stop;

         if Kind = Dash_Lex.Tk_EOF then
            Fail ("unexpected end of file, '"
                  & Dash_Lex.Kind_Image (Stop) & "' expected");
         end if;

         S := Parse_Statement;
         Append_To (Into, S);

         if Kind = Dash_Lex.Tk_Newline then
            Advance;
         elsif Kind /= Stop and then Kind /= Dash_Lex.Tk_EOF then
            Fail ("expected the end of the statement");
         end if;
      end loop;
   end Parse_Statements;

   ------------------------------------------------------------------
   --  Parse_Statement
   ------------------------------------------------------------------

   function Parse_Statement return Node_Access is
      L : constant Natural := Here;
   begin
      case Kind is
         when Dash_Lex.Tk_Let =>
            return Parse_Var_Decl;

         when Dash_Lex.Tk_St =>
            return Parse_If;

         when Dash_Lex.Tk_Ut =>
            return Parse_While;

         when Dash_Lex.Tk_Fs =>
            return Parse_Function;

         when Dash_Lex.Tk_Ident =>
            if Peek_Kind = Dash_Lex.Tk_Assign then
               declare
                  A : constant Node_Access := New_Node (K_Assign, L);
               begin
                  A.Name := Cur.Tok.Text;
                  Advance;                             --  name
                  Advance;                             --  '='
                  A.Sub := Parse_Expr;
                  return A;
               end;

            elsif Peek_Kind = Dash_Lex.Tk_LParen then
               declare
                  S : constant Node_Access := New_Node (K_Expr_Stmt, L);
               begin
                  S.Sub := Parse_Primary;
                  return S;
               end;

            else
               Fail ("'" & To_String (Cur.Tok.Text)
                     & "' is not a statement");
               return null;
            end if;

         when others =>
            Fail ("unexpected " & Dash_Lex.Kind_Image (Kind)
                  & " in statement");
            return null;
      end case;
   end Parse_Statement;

   ------------------------------------------------------------------
   --  Parse_Function
   ------------------------------------------------------------------

   function Parse_Function return Node_Access is
      L : constant Natural := Here;
      F : constant Node_Access := New_Node (K_Function, L);
   begin
      Advance;                                     --  'fs'

      if Kind /= Dash_Lex.Tk_Ident then
         Fail ("expected a function name after 'fs'");
      end if;
      F.Name := Cur.Tok.Text;
      Advance;

      if Kind = Dash_Lex.Tk_LParen then
         Advance;
         loop
            exit when Kind = Dash_Lex.Tk_RParen;

            if Kind /= Dash_Lex.Tk_Ident then
               Fail ("expected a parameter name");
            end if;

            declare
               P : constant Node_Access := New_Node (K_Var_Decl, Here);
            begin
               P.Name := Cur.Tok.Text;
               Advance;

               if Kind = Dash_Lex.Tk_Colon then
                  Advance;
                  if Kind /= Dash_Lex.Tk_Int then
                     Fail ("only the type 'int' may be used for a parameter");
                  end if;
                  Advance;
               end if;

               P.Typ := T_Int;
               Append_To (F.Params, P);
            end;

            if Kind = Dash_Lex.Tk_Comma then
               Advance;
            end if;
         end loop;
         Advance;                                   --  ')'
      end if;

      --  The result type may be written out, which a recursive function
      --  needs because its own result cannot be worked out.
      if Kind = Dash_Lex.Tk_Colon then
         Advance;
         if Kind /= Dash_Lex.Tk_Int then
            Fail ("only the type 'int' may be written for a result");
         end if;
         F.Ann_Typ := T_Int;
         Advance;
      end if;

      if Kind /= Dash_Lex.Tk_Is then
         Fail ("expected 'is' after the header of '"
               & To_String (F.Name) & "'");
      end if;
      Advance;
      loop
         Skip_Newlines;
         exit when Kind = Dash_Lex.Tk_Begin;

         if Kind = Dash_Lex.Tk_EOF then
            Fail ("unexpected end of file, 'begin' expected");
         end if;

         if Kind = Dash_Lex.Tk_Let then
            Append_To (F.Decls, Parse_Var_Decl);

         elsif Kind = Dash_Lex.Tk_Fs then
            --  A function written inside another function.
            Append_To (F.Nested, Parse_Function);

         else
            Fail ("only 'let' declarations and functions are allowed"
                  & " before 'begin'");
         end if;
      end loop;
      Advance;                                     --  'begin'

      Parse_Statements (Dash_Lex.Tk_End, F.Stmts);

      if Kind /= Dash_Lex.Tk_End then
         Fail ("expected 'end' to close '"
               & To_String (F.Name) & "'");
      end if;
      Advance;
      return F;
   end Parse_Function;

   ------------------------------------------------------------------
   --  Parse_Program
   ------------------------------------------------------------------

   function Parse_Program return Node_Access is
      Prog : constant Node_Access := New_Node (K_Program, 1);
   begin
      loop
         Skip_Newlines;
         exit when Kind = Dash_Lex.Tk_EOF;

         if Kind /= Dash_Lex.Tk_Fs then
            Fail ("expected 'fs' to start a function definition");
         end if;

         Append_Child (Prog, Parse_Function);
      end loop;
      return Prog;
   end Parse_Program;

   ------------------------------------------------------------------
   --  Parse
   ------------------------------------------------------------------

   function Parse (Tokens : Dash_Lex.Token_List) return Dash_Ast.Node_Access is
   begin
      Cur := Tokens.Head;
      if Cur = null then
         Nxt := null;
      else
         Nxt := Cur.Next;
      end if;

      return Parse_Program;
   end Parse;

end Dash_Parse;
