unit ps4_libSceIpmi;

{$mode ObjFPC}{$H+}
{$CALLING SysV_ABI_CDecl}
{$WARN 4110 off}

interface

uses
 subr_dynlib;

implementation

function Load_libSceIpmi(name:pchar):p_lib_info;
var
 lib:TLIBRARY;
begin
 Result:=obj_new_int('libSceIpmi');

 lib:=Result^.add_lib('libSceIpmi');
end;

var
 stub:t_int_file;

initialization
 RegisteredInternalFile(stub,'libSceIpmi.prx',@Load_libSceIpmi);

end.

