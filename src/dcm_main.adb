------------------------------------------------------------------------------
--  Dcm_Main -- the Dash Compiler Machine.
--
--  Usage:
--
--     dcm build <file.dh> [-o <name.exe>] [--keep-ada]
--         Translate the program into Ada and build a native executable.
--
--     dcm run <file.dh>
--         Run the program on the Dash virtual machine.
--
--     dcm check <file.dh>
--         Analyse the program and report the errors, without building.
--
--     dcm ast <file.dh>
--         Print the syntax tree.
--
--     dcm version
--
--  The DCM itself is written in Ada.  No C is used anywhere.
------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNAT.OS_Lib;
with Dash_Ast;
with Dash_Codegen;
with Dash_Lex;
with Dash_Parse;
with Dash_Sema;
with Dash_Vm;

procedure Dcm_Main is

   use Ada.Strings.Unbounded;
   use Dash_Ast;

   use type GNAT.OS_Lib.String_Access;

   Version : constant String := "DCM 0.1.0 -- the Dash Compiler Machine";

   ------------------------------------------------------------------
   --  Reading the source
   ------------------------------------------------------------------

   function Read_Source (Name : String) return String is
      F   : Ada.Text_IO.File_Type;
      Buf : Unbounded_String := Null_Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Name);
      while not Ada.Text_IO.End_Of_File (F) loop
         Append (Buf, Ada.Text_IO.Get_Line (F));
         Append (Buf, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (F);
      return To_String (Buf);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         raise;
   end Read_Source;

   ------------------------------------------------------------------
   --  The front end
   ------------------------------------------------------------------

   procedure Front_End (Source_Name : String; Program : out Node_Access) is
      Tokens : Dash_Lex.Token_List;
      Text   : constant String := Read_Source (Source_Name);
   begin
      Dash_Lex.Lex (Text, Tokens);
      Program := Dash_Parse.Parse (Tokens);
      Dash_Sema.Check (Program);
   end Front_End;

   ------------------------------------------------------------------
   --  Printing the syntax tree
   ------------------------------------------------------------------

   procedure Print_Node (N : Node_Access; Depth : Natural) is
      C : Child_List_Access;
   begin
      if N = null then
         return;
      end if;

      Ada.Text_IO.Put_Line (String'(1 .. Depth * 2 => ' ')
                           & Dash_Ast.Image (N));

      C := N.Children;
      while C /= null loop
         Print_Node (C.Item, Depth + 1);
         C := C.Next;
      end loop;

      C := N.Stmts;
      while C /= null loop
         Print_Node (C.Item, Depth + 1);
         C := C.Next;
      end loop;
   end Print_Node;

   ------------------------------------------------------------------
   --  Finding the Ada compiler
   ------------------------------------------------------------------

   function Find_Ada_Compiler return String is
      Env : constant GNAT.OS_Lib.String_Access :=
        GNAT.OS_Lib.Getenv ("DASH_GNAT");
   begin
      if Env /= null and then Env (Env'First .. Env'Last) /= "" then
         return Env (Env'First .. Env'Last);
      end if;

      if Ada.Directories.Exists ("gnatmake.exe") then
         return "gnatmake.exe";
      elsif Ada.Directories.Exists ("gnatmake") then
         return "gnatmake";
      elsif Ada.Directories.Exists ("C:\msys64\ucrt64\bin\gnatmake.exe") then
         return "C:\msys64\ucrt64\bin\gnatmake.exe";
      elsif Ada.Directories.Exists ("C:\msys64\mingw64\bin\gnatmake.exe") then
         return "C:\msys64\mingw64\bin\gnatmake.exe";
      elsif Ada.Directories.Exists ("C:\GNAT\bin\gnatmake.exe") then
         return "C:\GNAT\bin\gnatmake.exe";
      end if;

      return "";
   end Find_Ada_Compiler;

   ------------------------------------------------------------------
   --  Building a native executable
   ------------------------------------------------------------------

   procedure Build (Source_Name : String; Output_Name : String;
                    Keep_Ada : Boolean)
   is
      Program    : Node_Access;
      Ada_Source : Unbounded_String;
      Build_Dir  : constant String :=
        Ada.Strings.Fixed.Trim (Output_Name, Ada.Strings.Both) & ".dcm";
      Gen_File   : constant String := "dash_main.adb";
      Compiler   : constant String := Find_Ada_Compiler;
      Args       : GNAT.OS_Lib.Argument_List (1 .. 6);
      Status     : Integer;
      Abs_Out    : constant String := Ada.Directories.Full_Name (Output_Name);
   begin
      if Compiler = "" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "dcm: no Ada compiler was found.");
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "     Install GNAT, or point DASH_GNAT at gnatmake.");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Front_End (Source_Name, Program);

      Ada_Source := Dash_Codegen.Generate (Program);

      --  The build happens in a directory of its own, so that nothing is
      --  left behind in the folder of the user.
      if Ada.Directories.Exists (Build_Dir) then
         Ada.Directories.Delete_Tree (Build_Dir);
      end if;
      Ada.Directories.Create_Path (Build_Dir);

      declare
         F : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File,
                             Ada.Directories.Full_Name (Build_Dir)
                             & "\" & Gen_File);
         Ada.Text_IO.Put_Line (F, To_String (Ada_Source));
         Ada.Text_IO.Close (F);
      end;

      --  Run the Ada compiler inside the build directory.
      Args (1) := new String'("-q");
      Args (2) := new String'("-gnat2022");
      Args (3) := new String'("-O2");
      Args (4) := new String'("-o");
      Args (5) := new String'(Abs_Out);
      Args (6) := new String'(Gen_File);

      declare
         Saved_Dir : constant String := Ada.Directories.Current_Directory;
      begin
         Ada.Directories.Set_Directory (Build_Dir);
         Status := GNAT.OS_Lib.Spawn
           (Program_Name => Compiler,
            Args         => Args (1 .. 6));
         Ada.Directories.Set_Directory (Saved_Dir);
      exception
         when others =>
            Ada.Directories.Set_Directory (Saved_Dir);
            raise;
      end;

      if Status /= 0 then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "dcm: the Ada compiler failed, the exit status was "
            & Integer'Image (Status));
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "     the generated Ada source is kept in " & Build_Dir);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      if Keep_Ada then
         Ada.Text_IO.Put_Line
           ("dcm: the generated Ada source is kept in " & Build_Dir);
      else
         Ada.Directories.Delete_Tree (Build_Dir);
      end if;

      Ada.Text_IO.Put_Line ("dcm: built " & Output_Name);
   end Build;

   ------------------------------------------------------------------
   --  The commands
   ------------------------------------------------------------------

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line ("usage:");
      Ada.Text_IO.Put_Line ("  dcm build <file.dh> [-o <name.exe>] [--keep-ada]");
      Ada.Text_IO.Put_Line ("  dcm run   <file.dh>");
      Ada.Text_IO.Put_Line ("  dcm check <file.dh>");
      Ada.Text_IO.Put_Line ("  dcm ast   <file.dh>");
      Ada.Text_IO.Put_Line ("  dcm version");
   end Usage;

   Command     : Unbounded_String := Null_Unbounded_String;
   Source_File : Unbounded_String := Null_Unbounded_String;
   Output_File : Unbounded_String := Null_Unbounded_String;
   Keep_Ada    : Boolean := False;
   Program     : Node_Access;
   Skip        : Boolean := False;

begin
   --  Command line.
   if Ada.Command_Line.Argument_Count < 1 then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Command := To_Unbounded_String (Ada.Command_Line.Argument (1));

   for I in 2 .. Ada.Command_Line.Argument_Count loop
      declare
         A : constant String := Ada.Command_Line.Argument (I);
      begin
         if A = "-o" and then I < Ada.Command_Line.Argument_Count then
            Output_File := To_Unbounded_String (Ada.Command_Line.Argument (I + 1));
            Skip := True;
         elsif A = "--keep-ada" then
            Keep_Ada := True;
         elsif not Skip then
            if Source_File = Null_Unbounded_String then
               Source_File := To_Unbounded_String (A);
            end if;
         end if;
      end;
      Skip := False;
   end loop;

   begin
      if Command = "version" then
         Ada.Text_IO.Put_Line (Version);
         return;

      elsif Command = "help" then
         Usage;
         return;

      elsif Source_File = Null_Unbounded_String then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                               "dcm: no source file was given");
         Usage;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      if Command = "build" then
         if Output_File = Null_Unbounded_String then
            Output_File := To_Unbounded_String
              (Ada.Directories.Base_Name (To_String (Source_File)) & ".exe");
         end if;
         Build (To_String (Source_File), To_String (Output_File), Keep_Ada);

      elsif Command = "run" then
         Front_End (To_String (Source_File), Program);
         Dash_Vm.Run (Program);

      elsif Command = "check" then
         Front_End (To_String (Source_File), Program);
         Ada.Text_IO.Put_Line ("dcm: " & To_String (Source_File)
                              & " is correct.");

      elsif Command = "ast" then
         declare
            Tokens : Dash_Lex.Token_List;
         begin
            Dash_Lex.Lex (Read_Source (To_String (Source_File)), Tokens);
            Program := Dash_Parse.Parse (Tokens);
         end;
         Print_Node (Program, 0);

      else
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                               "dcm: unknown command '" & To_String (Command)
                               & "'");
         Usage;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;

   exception
      when E : Dash_Lex.Lex_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                               To_String (Source_File) & ": "
                               & Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);

      when E : Dash_Parse.Parse_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                               To_String (Source_File) & ": "
                               & Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);

      when E : Dash_Sema.Sema_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                               To_String (Source_File) & ": "
                               & Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);

      when E : Dash_Codegen.Codegen_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                               To_String (Source_File) & ": "
                               & Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);

      when E : Dash_Vm.Runtime_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                               To_String (Source_File) & ": "
                               & Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);

      when E : others =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
                               "dcm: " & Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end;

end Dcm_Main;
