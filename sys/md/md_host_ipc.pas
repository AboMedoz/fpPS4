unit md_host_ipc;

{$mode ObjFPC}{$H+}

interface

uses
 Classes,
 kern_thr,
 kern_thread,
 evbuffer,
 evpoll,
 host_ipc;

type
 t_push_cb=Function(Node:Pointer):Boolean of object;

 t_ipc_proto=object
  Fbev   :Pbufferevent;
  Finput :Pevbuffer;
  Foutput:Pevbuffer;

  FHeader:TNodeHeader;
  FState :Integer;

  FPush  :t_push_cb;

  procedure Send(mtype:t_mtype;mlen,mtid:DWORD;buf:Pointer);
  procedure Recv;
 end;

 THostIpcPipe=class(THostIpcConnect)
  evpoll:Tevpoll;
  proto:t_ipc_proto;
  procedure   set_pipe(fd:THandle);
  procedure   Recv; virtual;
  Function    Push(Node:Pointer):Boolean; virtual;
  procedure   thread_new;  virtual;
  procedure   thread_free; virtual;
  procedure   Send(mtype:t_mtype;mlen,mtid:DWORD;buf:Pointer); override;
  Constructor Create;
  Destructor  Destroy; override;
 end;

 THostIpcPipeMGUI=class(THostIpcPipe)
  Ftd:TThreadID;
  procedure   Recv;        override;
  procedure   thread_new;  override;
  procedure   thread_free; override;
 end;

 THostIpcPipeKERN=class(THostIpcPipe)
  Ftd:p_kthread;
  FHandler:THostIpcHandler;
  procedure   Recv;        override;
  procedure   thread_new;  override;
  procedure   thread_free; override;
 end;

implementation

procedure t_ipc_proto.Send(mtype:t_mtype;mlen,mtid:DWORD;buf:Pointer);
var
 node:PNodeHeader;
begin
 node:=AllocMem(SizeOf(TNodeHeader)+mlen);
 node^.mtype:=DWORD(mtype);
 node^.mlen :=mlen;
 node^.mtid :=mtid;
 Move(buf^,node^.buf,mlen);

 evbuffer_add_ref(Foutput,node,0,SizeOf(TNodeHeader)+mlen,Freemem_ptr);

 bufferevent_write(Fbev);
end;

procedure t_ipc_proto.Recv;
var
 node:PQNode;
begin

 repeat

  case FState of
   0:
     begin
      if (evbuffer_get_length(Finput)<SizeOf(TNodeHeader)) then Exit;

      evbuffer_remove(Finput,@FHeader,SizeOf(TNodeHeader));

      FState:=1;
     end;
   1:
     begin
      if (evbuffer_get_length(Finput)<FHeader.mlen) then Exit;

      node:=AllocMem(SizeOf(TQNode)+FHeader.mlen);

      node^.header:=FHeader;

      evbuffer_remove(Finput,@node^.buf,FHeader.mlen);

      FPush(node);

      FState:=0;
     end;

   else;
  end;

 until (evbuffer_get_length(Finput)=0);

end;

function pipe_gui_thread(parameter:pointer):ptrint;
begin
 Result:=0;
 evpoll_loop(parameter);
end;

procedure pipe_kern_thread(parameter:pointer); SysV_ABI_CDecl;
begin
 evpoll_loop(parameter);
end;

Procedure eventcb(bev:Pbufferevent;events:SizeUInt;ctx:pointer);
begin

 if ((events and (BEV_EVENT_ERROR or BEV_EVENT_EOF))<>0) then
 begin


  Exit;
 end;

 if (events and BEV_EVENT_READING)<>0 then
 begin
  THostIpcPipe(ctx).Recv;
  bufferevent_read(bev);
 end;

 if (events and BEV_EVENT_WRITING)<>0 then
 begin
  bufferevent_write(bev);
 end;

end;

procedure THostIpcPipe.set_pipe(fd:THandle);
begin
 proto.Fbev   :=bufferevent_pipe_new  (@evpoll,fd);
 proto.Finput :=bufferevent_get_input (proto.Fbev);
 proto.Foutput:=bufferevent_get_output(proto.Fbev);

 proto.FPush  :=@Self.Push;

 bufferevent_setcb(proto.Fbev,@eventcb,Pointer(Self));
 bufferevent_enable(proto.Fbev);
end;

procedure THostIpcPipe.Recv;
begin
 proto.Recv;
end;

Function THostIpcPipe.Push(Node:Pointer):Boolean;
begin
 Result:=FQueue.Push(node);
end;

procedure THostIpcPipe.thread_new;
begin
 //
end;

procedure THostIpcPipe.thread_free;
begin
 //
end;

procedure THostIpcPipe.Send(mtype:t_mtype;mlen,mtid:DWORD;buf:Pointer);
begin
 proto.Send(mtype,mlen,mtid,buf);
end;

Constructor THostIpcPipe.Create;
begin
 inherited;
 evpoll_init(@evpoll,nil);
 thread_new;
end;

Destructor THostIpcPipe.Destroy;
begin
 evpoll_break(@evpoll);
 thread_free;
 bufferevent_free(proto.Fbev);
 evpoll_free(@evpoll);
 inherited;
end;

//

procedure THostIpcPipeMGUI.Recv;
begin
 inherited;
 //
 if Assigned(Classes.WakeMainThread) then
 begin
  Classes.WakeMainThread(nil);
 end;
end;

procedure THostIpcPipeMGUI.thread_new;
begin
 Ftd:=BeginThread(@pipe_gui_thread,@evpoll);
end;

procedure THostIpcPipeMGUI.thread_free;
begin
 WaitForThreadTerminate(Ftd,0);
 CloseThread(Ftd);
end;

//

procedure THostIpcPipeKERN.Recv;
begin
 inherited;

 Update(FHandler);
end;

procedure THostIpcPipeKERN.thread_new;
begin
 Ftd:=nil;
 kthread_add(@pipe_kern_thread,@evpoll,@Ftd,'[ipc_pipe]');
end;

procedure THostIpcPipeKERN.thread_free;
begin
 thread_dec_ref(Ftd);
end;


end.


