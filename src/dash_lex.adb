------------------------------------------------------------------------------
--  Dash_Lex -- body
------------------------------------------------------------------------------

with Ada.Characters.Latin_1;

package body Dash_Lex is

   --  Control characters, spelled out so that the analyser does not
   --  depend on the visibility of a standard package.
   HT : constant Character := Character'Val (9);
   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   ------------------------------------------------------------------
   --  Character classification
   ------------------------------------------------------------------

   function Is_Ident_Start (C : Character) return Boolean is
     (C in 'a' .. 'z' | 'A' .. 'Z' | '_');

   function Is_Digit_C (C : Character) return Boolean is
     (C in '0' .. '9');

   function Is_Hex_Digit (C : Character) return Boolean is
     (C in '0' .. '9' | 'a' .. 'f' | 'A' .. 'F');

   function Is_Blank_C (C : Character) return Boolean is
     (C = ' ' or else C = HT or else C = CR);

   function Hex_Value (C : Character) return Integer is
   begin
      case C is
         when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' => return Character'Pos (C) - Character'Pos ('a') + 10;
         when 'A' .. 'F' => return Character'Pos (C) - Character'Pos ('A') + 10;
         when others     => return 0;
      end case;
   end Hex_Value;

   ------------------------------------------------------------------
   --  Kind_Image
   ------------------------------------------------------------------

   function Kind_Image (K : Token_Kind) return String is
   begin
      case K is
         when Tk_EOF      => return "end of file";
         when Tk_Newline  => return "end of line";
         when Tk_Fs       => return "'fs'";
         when Tk_Is       => return "'is'";
         when Tk_Begin    => return "'begin'";
         when Tk_End      => return "'end'";
         when Tk_Let      => return "'let'";
         when Tk_Int      => return "'int'";
         when Tk_St       => return "'st'";
         when Tk_Ut       => return "'ut'";
         when Tk_Ident    => return "identifier";
         when Tk_Int_Lit  => return "integer literal";
         when Tk_Str_Lit  => return "string literal";
         when Tk_LParen   => return "'('";
         when Tk_RParen   => return "')'";
         when Tk_Lt       => return "'<'";
         when Tk_Gt       => return "'>'";
         when Tk_Colon    => return "':'";
         when Tk_Assign   => return "'='";
         when Tk_Plus     => return "'+'";
         when Tk_Minus    => return "'-'";
         when Tk_Star     => return "'*'";
         when Tk_Slash    => return "'/'";
         when Tk_Percent  => return "'%'";
         when Tk_Comma    => return "','";
      end case;
   end Kind_Image;

   ------------------------------------------------------------------
   --  Lex
   ------------------------------------------------------------------

   procedure Lex (Source : String; Tokens : out Token_List) is

      Pos   : Natural := Source'First;
      Last  : Natural := Source'Last;
      Line  : Natural := 1;
      Col   : Natural := 1;
      Depth : Natural := 0;
      Prev  : Character := ' ';

      procedure Emit
        (K    : Token_Kind;
         Text : String := "";
         Val  : Long_Long_Integer := 0;
         L    : Natural := Line;
         C    : Natural := Col)
      is
         N : constant Token_Node_Access := new Token_Node;
      begin
         N.Tok.Kind      := K;
         N.Tok.Text      := To_Unbounded_String (Text);
         N.Tok.Int_Value := Val;
         N.Tok.Line      := L;
         N.Tok.Column    := C;

         if Tokens.Tail = null then
            Tokens.Head := N;
         else
            Tokens.Tail.Next := N;
         end if;
         Tokens.Tail := N;
      end Emit;

      procedure At_Error (Msg : String; L : Natural := Line; C : Natural := Col) is
      begin
         raise Lex_Error with "line" & Natural'Image (L) & ", column"
           & Natural'Image (C) & ": " & Msg;
      end At_Error;

      Start : Natural;
      Word  : Unbounded_String;
      Acc   : Long_Long_Integer;
      Buf   : Unbounded_String;
      C1    : Character;
      C2    : Character;

   begin
      Tokens.Head := null;
      Tokens.Tail := null;

      if Source'Length = 0 then
         Emit (Tk_EOF);
         return;
      end if;

      --  A byte order mark at the start of the file is skipped.
      if Source'Length >= 3
        and then Source (Source'First) = Character'Val (16#EF#)
        and then Source (Source'First + 1) = Character'Val (16#BB#)
        and then Source (Source'First + 2) = Character'Val (16#BF#)
      then
         Pos  := Source'First + 3;
         Col  := Col + 3;
      end if;

      loop
         --  Skip horizontal white space.
         while Pos <= Last and then Is_Blank_C (Source (Pos)) loop
            Pos := Pos + 1;
            Col := Col + 1;
         end loop;

         exit when Pos > Last;

         C1 := Source (Pos);

         if C1 = LF then

            --  End of line: a statement terminator, unless we are inside
            --  parentheses where line breaks carry no meaning.
            if Depth = 0 then
               Emit (Tk_Newline);
            end if;

            --  Collapse a run of blank lines into a single terminator.
            while Pos <= Last
              and then (Source (Pos) = LF or else Source (Pos) = CR)
            loop
               if Source (Pos) = LF then
                  Line := Line + 1;
                  Col  := 1;
               else
                  Col := Col + 1;
               end if;
               Pos := Pos + 1;
            end loop;

            Prev := LF;

         elsif C1 = '-' and then Pos + 1 <= Last and then Source (Pos + 1) = '-'
           and then (Prev = ' ' or else Prev = HT or else Prev = LF)
         then
            --  Ada style comment, up to the end of the line.
            while Pos <= Last and then Source (Pos) /= LF loop
               Pos := Pos + 1;
               Col := Col + 1;
            end loop;

         elsif C1 = '"' then

            --  String literal.  A quote inside the text is doubled.
            Start := Pos;
            Pos  := Pos + 1;
            Col  := Col + 1;
            Buf  := Null_Unbounded_String;

            loop
               if Pos > Last then
                  At_Error ("unterminated string literal", Line, Col);
               end if;

               if Source (Pos) = '"' then
                  if Pos + 1 <= Last and then Source (Pos + 1) = '"' then
                     Append (Buf, '"');
                     Pos := Pos + 2;
                     Col := Col + 2;
                  else
                     Pos := Pos + 1;
                     Col := Col + 1;
                     exit;
                  end if;
               elsif Source (Pos) = LF then
                  At_Error ("unterminated string literal", Line, Col);
               else
                  Append (Buf, Source (Pos));
                  Pos := Pos + 1;
                  Col := Col + 1;
               end if;
            end loop;

            Emit (Tk_Str_Lit, To_String (Buf), 0, Line, Start - Source'First + 1);
            Prev  := '"';

         elsif Is_Ident_Start (C1) then

            Start := Pos;
            while Pos <= Last
              and then (Is_Ident_Start (Source (Pos)) or else Is_Digit_C (Source (Pos)))
            loop
               Pos := Pos + 1;
               Col := Col + 1;
            end loop;

            Word := To_Unbounded_String (Source (Start .. Pos - 1));

            if Word = "fs" then
               Emit (Tk_Fs, To_String (Word));
            elsif Word = "is" then
               Emit (Tk_Is, To_String (Word));
            elsif Word = "begin" then
               Emit (Tk_Begin, To_String (Word));
            elsif Word = "end" then
               Emit (Tk_End, To_String (Word));
            elsif Word = "let" then
               Emit (Tk_Let, To_String (Word));
            elsif Word = "int" then
               Emit (Tk_Int, To_String (Word));
            elsif Word = "st" then
               Emit (Tk_St, To_String (Word));
            elsif Word = "ut" then
               Emit (Tk_Ut, To_String (Word));
            else
               Emit (Tk_Ident, To_String (Word));
            end if;

            Prev := 'x';

         elsif Is_Digit_C (C1) then

            Start := Pos;
            Acc   := 0;

            if C1 = '0' and then Pos + 1 <= Last
              and then (Source (Pos + 1) = 'x' or else Source (Pos + 1) = 'X')
            then
               --  Hexadecimal literal.
               Pos := Pos + 2;
               Col := Col + 2;
               while Pos <= Last and then Is_Hex_Digit (Source (Pos)) loop
                  Acc := Acc * 16 + Long_Long_Integer (Hex_Value (Source (Pos)));
                  Pos := Pos + 1;
                  Col := Col + 1;
               end loop;
               Emit (Tk_Int_Lit, Source (Start .. Pos - 1), Acc);

            elsif C1 = '0' and then Pos + 1 <= Last
              and then (Source (Pos + 1) = 'b' or else Source (Pos + 1) = 'B')
            then
               --  Binary literal.
               Pos := Pos + 2;
               Col := Col + 2;
               while Pos <= Last
                 and then (Source (Pos) = '0' or else Source (Pos) = '1')
               loop
                  Acc := Acc * 2
                    + (if Source (Pos) = '1' then 1 else 0);
                  Pos := Pos + 1;
                  Col := Col + 1;
               end loop;
               Emit (Tk_Int_Lit, Source (Start .. Pos - 1), Acc);

            else
               --  Decimal literal.
               while Pos <= Last and then Is_Digit_C (Source (Pos)) loop
                  Pos := Pos + 1;
                  Col := Col + 1;
               end loop;

               begin
                  Acc := Long_Long_Integer'Value (Source (Start .. Pos - 1));
               exception
                  when others =>
                     At_Error ("integer literal out of range", Line, Start - Source'First + 1);
               end;

               Emit (Tk_Int_Lit, Source (Start .. Pos - 1), Acc);
            end if;

            Prev := '0';

         else

            --  Punctuation and operators.
            case C1 is
               when '(' =>
                  Emit (Tk_LParen, "(");
                  Pos   := Pos + 1;
                  Col   := Col + 1;
                  Depth := Depth + 1;

               when ')' =>
                  Emit (Tk_RParen, ")");
                  Pos := Pos + 1;
                  Col := Col + 1;
                  if Depth > 0 then
                     Depth := Depth - 1;
                  end if;

               when '<' =>
                  Emit (Tk_Lt, "<");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when '>' =>
                  Emit (Tk_Gt, ">");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when ':' =>
                  Emit (Tk_Colon, ":");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when '=' =>
                  Emit (Tk_Assign, "=");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when '+' =>
                  Emit (Tk_Plus, "+");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when '-' =>
                  Emit (Tk_Minus, "-");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when '*' =>
                  Emit (Tk_Star, "*");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when '/' =>
                  Emit (Tk_Slash, "/");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when '%' =>
                  Emit (Tk_Percent, "%");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when ',' =>
                  Emit (Tk_Comma, ",");
                  Pos := Pos + 1;
                  Col := Col + 1;

               when others =>
                  At_Error ("unexpected character '" & C1 & "'");
            end case;

            Prev := C1;
         end if;
      end loop;

      Emit (Tk_EOF);
   end Lex;

end Dash_Lex;
