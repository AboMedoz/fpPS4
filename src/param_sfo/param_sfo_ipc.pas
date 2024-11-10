unit param_sfo_ipc;

{$mode ObjFPC}{$H+}

interface

procedure init_param_sfo;
function  ParamSfoGetString(const name:RawByteString):RawByteString;
function  ParamSfoGetUInt  (const name:RawByteString):DWORD;

implementation

uses
 sysutils,
 atomic,
 sys_bootparam,
 host_ipc_interface,
 param_sfo_gui,
 kern_rwlock;

var
 param_sfo_lock     :Pointer=nil;
 param_sfo_lazy_init:Integer=0;
 param_sfo_file     :TParamSfoFile=nil;

type
 TParamSfoLoaderIpc=object
  function OnLoad(obj:TObject):Ptruint;
 end;

function TParamSfoLoaderIpc.OnLoad(obj:TObject):Ptruint;
begin
 Result:=0;

 Writeln('PARAM_SFO_LOAD');

 param_sfo_file:=TParamSfoFile(obj);
end;

procedure init_param_sfo;
var
 Loader:TParamSfoLoaderIpc;
 err:Integer;
begin
 if (param_sfo_lazy_init=2) then Exit;

 Writeln('PARAM_SFO_INIT');

 if CAS(param_sfo_lazy_init,0,1) then
 begin
  rw_wlock(param_sfo_lock);

  p_host_handler.AddCallback('PARAM_SFO_LOAD',@Loader.OnLoad,TParamSfoFile);

  err:=p_host_ipc.SendSync('PARAM_SFO_INIT');

  if (err<>0) then
  begin
   Assert(false,'PARAM_SFO_INIT error='+IntToStr(err));
  end;

  param_sfo_lazy_init:=2;
  rw_wunlock(param_sfo_lock);
 end else
 begin
  //sunc
  rw_wlock  (param_sfo_lock);
  rw_wunlock(param_sfo_lock);
 end;
end;

function ParamSfoGetString(const name:RawByteString):RawByteString;
begin
 init_param_sfo;
 rw_rlock(param_sfo_lock);
  Result:=param_sfo_file.GetString(name);
 rw_runlock(param_sfo_lock);
end;

function  ParamSfoGetUInt(const name:RawByteString):DWORD;
begin
 init_param_sfo;
 rw_rlock(param_sfo_lock);
  Result:=param_sfo_file.GetUInt(name);
 rw_runlock(param_sfo_lock);
end;


end.

