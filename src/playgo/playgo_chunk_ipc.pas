unit playgo_chunk_ipc;

{$mode ObjFPC}{$H+}

interface

uses
 playgo_chunk_gui;

var
 playgo_lock     :Pointer=nil;
 playgo_lazy_init:Integer=0;
 playgo_file     :TPlaygoFile=nil;

function  is_init_playgo:Boolean;
procedure init_playgo;
procedure free_playgo;

implementation

uses
 sysutils,
 atomic,
 sys_bootparam,
 host_ipc_interface,
 kern_rwlock;

type
 TPlaygoLoaderIpc=object
  function OnLoad(obj:TObject):Ptruint;
 end;

function TPlaygoLoaderIpc.OnLoad(obj:TObject):Ptruint;
begin
 Result:=0;

 Writeln('PLAYGO_LOAD');

 playgo_file:=TPlaygoFile(obj);
end;

function is_init_playgo:Boolean;
begin
 Result:=(playgo_lazy_init=2);
end;

procedure init_playgo;
var
 Loader:TPlaygoLoaderIpc;
 err:Integer;
begin
 if (playgo_lazy_init=2) then Exit;

 Writeln('PLAYGO_INIT');

 if CAS(playgo_lazy_init,0,1) then
 begin
  rw_wlock(playgo_lock);

  p_host_handler.AddCallback('PLAYGO_LOAD',@Loader.OnLoad,TPlaygoFile);

  err:=p_host_ipc.SendSync('PLAYGO_INIT');

  if (err<>0) then
  begin
   Assert(false,'PLAYGO_LOAD error='+IntToStr(err));
  end;

  playgo_lazy_init:=2;
  rw_wunlock(playgo_lock);
 end else
 begin
  //sunc
  rw_wlock  (playgo_lock);
  rw_wunlock(playgo_lock);
 end;
end;

procedure free_playgo;
begin
 rw_wlock  (playgo_lock);

 FreeAndNil(playgo_file);

 rw_wunlock(playgo_lock);
end;

end.

