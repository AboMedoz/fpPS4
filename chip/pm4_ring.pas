unit pm4_ring;

{$mode ObjFPC}{$H+}
{$CALLING SysV_ABI_CDecl}

interface

uses
 errno,
 md_map,
 systm,
 bittype;

type
 //IT_INDIRECT_BUFFER_CNST = $00000033;  ccb  0xc0023300
 //IT_INDIRECT_BUFFER      = $0000003f;  dcb  0xc0023f00

 PPM4CMDINDIRECTBUFFER=^PM4CMDINDIRECTBUFFER;
 PM4CMDINDIRECTBUFFER=bitpacked record
  header   :DWORD; // PM4_TYPE_3_HEADER
  ibBase   :QWORD; // Indirect buffer base address, must be 4 byte aligned
  //
  ibSize   :bit20; // Indirect buffer size
  reserved0:bit4;
  vmid     :bit4;  // Virtual memory domain ID for command buffer
  reserved1:bit4;
 end;

 PPM4CMDSWITCHBUFFER=^PM4CMDSWITCHBUFFER;
 PM4CMDSWITCHBUFFER=bitpacked record
  header:DWORD;
  data  :DWORD;
 end;

const
 GC_RING_SIZE=$80000;
 GC_RING_PADD=64*1024;

type
 p_pm4_ring=^t_pm4_ring;
 t_pm4_ring=packed record
  buff:Pointer;
  size:DWORD;
  rptr:DWORD;
  wptr:DWORD;
  aptr:DWORD;
 end;

function  gc_ring_create(ring:p_pm4_ring;size:ptruint):Integer;
function  gc_ring_free  (ring:p_pm4_ring):Integer;

function  gc_ring_pm4_alloc  (ring:p_pm4_ring;size:DWORD;buff:PPointer):Boolean;
procedure gc_ring_pm4_submit (ring:p_pm4_ring);
procedure gc_ring_pm4_release(ring:p_pm4_ring);

function  gc_ring_pm4_peek (ring:p_pm4_ring;size:PDWORD;buff:PPointer):Boolean;
function  gc_ring_pm4_drain(ring:p_pm4_ring;size:DWORD):Boolean;

function  gc_submit_internal       (ring:p_pm4_ring;count:DWORD;cmds:Pointer):Integer;
function  gc_switch_buffer_internal(ring:p_pm4_ring):Integer;

implementation

function gc_ring_create(ring:p_pm4_ring;size:ptruint):Integer;
var
 hMem:THandle;
begin
 Result:=0;
 if (ring=nil) then Exit(-1);

 size:=1 shl BsfQWORD(size);
 if (size<GC_RING_PADD) then size:=GC_RING_PADD;

 ring^.buff:=nil;
 ring^.size:=size;
 ring^.rptr:=0;
 ring^.wptr:=0;
 ring^.aptr:=0;

 Result:=md_reserve_ex(ring^.buff,size+GC_RING_PADD);
 if (Result<>0) then Exit;

 Result:=md_split(ring^.buff,size);
 if (Result<>0) then Exit;

 hMem:=0;
 Result:=md_memfd_create(hMem,size);
 if (Result<>0) then Exit;

 Result:=md_file_mmap_ex(hMem,ring^.buff,0,size,MD_PROT_RW);
 if (Result<>0) then
 begin
  md_memfd_close(hMem);
  Exit;
 end;

 Result:=md_file_mmap_ex(hMem,ring^.buff+size,size,GC_RING_PADD,MD_PROT_RW);

 md_memfd_close(hMem);
end;

function gc_ring_free(ring:p_pm4_ring):Integer;
begin
 Result:=0;
 if (ring=nil) then Exit;
 if (ring^.buff=nil) then Exit;
 if (ring^.size=0) then Exit;

 Result:=md_unmap_ex(ring^.buff,ring^.size+GC_RING_PADD);
end;

//need lock
function gc_ring_pm4_alloc(ring:p_pm4_ring;size:DWORD;buff:PPointer):Boolean;
var
 next:DWORD;
begin
 Result:=False;
 if (size>ring^.size) then Exit;

 next:=ring^.aptr+size;

 if (next>=ring^.size) then
 begin
  next:=next and (ring^.size-1);
  if (next>ring^.rptr) then Exit;
 end;

 buff^:=ring^.buff+ring^.aptr;
 ring^.aptr:=next;
 Result:=True;
end;

procedure gc_ring_pm4_submit(ring:p_pm4_ring);
begin
 System.InterlockedExchange(ring^.wptr,ring^.aptr);
end;

procedure gc_ring_pm4_release(ring:p_pm4_ring);
begin
 ring^.aptr:=ring^.wptr;
end;

//single consumer
function gc_ring_pm4_peek(ring:p_pm4_ring;size:PDWORD;buff:PPointer):Boolean;
var
 rptr:DWORD;
 wptr:DWORD;
 s   :DWORD;
begin
 Result:=False;

 rptr:=ring^.rptr;
 wptr:=ring^.wptr;

 if (rptr>wptr) then
 begin
  if (wptr>GC_RING_PADD) then wptr:=GC_RING_PADD;
  s:=(ring^.size-rptr)+wptr;
 end else
 begin
  s:=wptr-rptr;
 end;

 if (s<>0) then
 begin
  size^:=s;
  buff^:=ring^.buff+rptr;
  Result:=True;
 end;
end;

//single consumer
function gc_ring_pm4_drain(ring:p_pm4_ring;size:DWORD):Boolean;
var
 rptr:DWORD;
 wptr:DWORD;
 s   :DWORD;
begin
 Result:=False;

 rptr:=ring^.rptr;
 wptr:=ring^.wptr;

 if (rptr>wptr) then
 begin
  s:=(ring^.size-rptr)+wptr;
 end else
 begin
  s:=wptr-rptr;
 end;

 if (size>s) then Exit;

 rptr:=rptr+size;
 rptr:=rptr and (ring^.size-1);

 System.InterlockedExchange(ring^.rptr,rptr);

 Result:=True;
end;

function gc_submit_internal(ring:p_pm4_ring;count:DWORD;cmds:Pointer):Integer;
var
 size:QWORD;
 buf:PPM4CMDINDIRECTBUFFER;
 op:DWORD;
begin
 Result:=0;
 if (count=0) then Exit;

 if (count>=$1000) then Exit(-2142502897);

 size:=(count*16);

 buf:=nil;
 if not gc_ring_pm4_alloc(ring,size,@buf) then
 begin
  Writeln(stderr,'### gc_submit_common : Cannot allocate a space in ring buffer.');
  Exit(EBUSY);
 end;

 Result:=copyin(cmds,buf,size);

 if (Result<>0) then
 begin
  gc_ring_pm4_release(ring);
  Exit(-2142502898);
 end;

 while (count<>0) do
 begin
  op:=buf^.header;

  if ((op<>$c0023300) and (op<>$c0023f00)) then
  begin
   Writeln(stderr,'## gc_insert_indirect_buffer: invalid opcode = 0x',HexStr(op,8));
   gc_ring_pm4_release(ring);
   Exit(-2142502896);
  end;

  if (buf^.ibSize=0) then
  begin
   Writeln(stderr,'## gc_insert_indirect_buffer: invalid ib_size = 0x',HexStr(buf^.ibSize,5));
   gc_ring_pm4_release(ring);
   Exit(-2142502895);
  end;

  Inc(buf);
  Dec(count);
 end;

 gc_ring_pm4_submit(ring);
end;

function gc_switch_buffer_internal(ring:p_pm4_ring):Integer;
var
 buf:PPM4CMDSWITCHBUFFER;
begin
 Result:=0;

 buf:=nil;
 if not gc_ring_pm4_alloc(ring,sizeof(PM4CMDSWITCHBUFFER),@buf) then
 begin
  Writeln(stderr,'### gc_switch_buffer_internal : Cannot allocate a space in ring buffer.');
  Exit(EBUSY);
 end;

 //IT_SWITCH_BUFFER = $0000008b;

 buf^.header:=$c0008b00;
 buf^.data  :=0;

 gc_ring_pm4_submit(ring);
end;

end.
