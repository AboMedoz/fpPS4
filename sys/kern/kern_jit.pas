unit kern_jit;

{$mode ObjFPC}{$H+}
{$CALLING SysV_ABI_CDecl}


interface

uses
 kern_thr,
 vm_pmap,
 systm,
 trap,
 x86_fpdbgdisas,
 x86_jit,
 kern_stub;

type
 t_data16=array[0..15] of Byte;

const
 c_data16:t_data16=($90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90);

type
 tcopy_cb=procedure(vaddr:Pointer); //rdi

 t_memop_type=(moCopyout,moCopyin);

 p_jit_code=^t_jit_code;
 t_jit_code=record
  frame :t_jit_frame;
  prolog:p_stub_chunk;
  o_len :Byte;
  o_data:t_data16;
  code  :record end;
 end;

 t_jit_context=record
  rip_addr:QWORD;

  Code:t_data16;

  dis:TX86Disassembler;
  din:TInstruction;

  builder:t_jit_builder;

  jit_code:p_jit_code;
 end;

function  GetFrameOffsetInt(RegValue:TRegValue):Integer;
procedure print_disassemble(addr:Pointer;vsize:Integer);
function  classif_memop(var din:TInstruction):t_memop_type;
function  get_lea_id(memop:t_memop_type):Byte;
function  get_reg_id(memop:t_memop_type):Byte;
function  GetTargetOfs(var ctx:t_jit_context;id:Byte;var ofs:Int64):Boolean;

function  generate_jit(var ctx:t_jit_context):p_stub_chunk;

implementation

function GetFrameOffset(RegValue:TRegValue): Pointer; inline;
begin
  Result := nil;

  case RegValue.AType of
    regNone:
    begin
      Result := nil;
    end;
    regRip:
    begin
      Result := @p_kthread(nil)^.td_frame.tf_rip;
    end;
    regOne:
    begin
      Result := nil; //'1';
    end;
    regGeneral:
    begin
      case RegValue.ASize of
        os8,
        os16,
        os32,
        os64:
        begin
          case RegValue.AIndex of
            0:Result := @p_kthread(nil)^.td_frame.tf_rax;
            1:Result := @p_kthread(nil)^.td_frame.tf_rcx;
            2:Result := @p_kthread(nil)^.td_frame.tf_rdx;
            3:Result := @p_kthread(nil)^.td_frame.tf_rbx;
            4:Result := @p_kthread(nil)^.td_frame.tf_rsp;
            5:Result := @p_kthread(nil)^.td_frame.tf_rbp;
            6:Result := @p_kthread(nil)^.td_frame.tf_rsi;
            7:Result := @p_kthread(nil)^.td_frame.tf_rdi;
            8:Result := @p_kthread(nil)^.td_frame.tf_r8 ;
            9:Result := @p_kthread(nil)^.td_frame.tf_r9 ;
           10:Result := @p_kthread(nil)^.td_frame.tf_r10;
           11:Result := @p_kthread(nil)^.td_frame.tf_r11;
           12:Result := @p_kthread(nil)^.td_frame.tf_r12;
           13:Result := @p_kthread(nil)^.td_frame.tf_r13;
           14:Result := @p_kthread(nil)^.td_frame.tf_r14;
           15:Result := @p_kthread(nil)^.td_frame.tf_r15;
           else;
          end;
        end;
      else;
      end;
    end;
    regGeneralH:
    begin
      case RegValue.ASize of
        os8:
        begin
          case RegValue.AIndex of
            0:Result := (@p_kthread(nil)^.td_frame.tf_rax)+1;
            1:Result := (@p_kthread(nil)^.td_frame.tf_rcx)+1;
            2:Result := (@p_kthread(nil)^.td_frame.tf_rdx)+1;
            3:Result := (@p_kthread(nil)^.td_frame.tf_rbx)+1;
            else;
          end;
        end;
      else;
      end;
    end;
    regMm:
    begin
      Result := nil; //Format('mm%u', [AIndex]);
    end;
    regXmm:
    begin
      case RegValue.ASize of
        os32,
        os64,
        os128:
        begin
          Result := nil; //Format('xmm%u', [AIndex]);
        end;
        os256:
        begin
          Result := nil; //Format('ymm%u', [AIndex]);
        end;
      else;
      end;
    end;
    regSegment:
    begin
      case RegValue.AIndex of
        0:Result := @p_kthread(nil)^.td_frame.tf_es;
        1:Result := @p_kthread(nil)^.td_frame.tf_cs;
        2:Result := @p_kthread(nil)^.td_frame.tf_ss;
        3:Result := @p_kthread(nil)^.td_frame.tf_ds;
        4:Result := @p_kthread(nil)^.td_frame.tf_fs;
        5:Result := @p_kthread(nil)^.td_frame.tf_gs;
        else;
      end;
    end;
    regFlags:
    begin
      Result := @p_kthread(nil)^.td_frame.tf_rflags;
    end;
  else;
  end;
end;

function GetFrameOffsetInt(RegValue:TRegValue):Integer;
begin
 Result:=Integer(ptruint(GetFrameOffset(RegValue)));
end;

procedure print_disassemble(addr:Pointer;vsize:Integer);
var
 proc:TDbgProcess;
 adec:TX86AsmDecoder;
 ptr,fin:Pointer;
 ACodeBytes,ACode:RawByteString;
begin
 ptr:=addr;
 fin:=addr+vsize;

 proc:=TDbgProcess.Create(dm64);
 adec:=TX86AsmDecoder.Create(proc);

 while (ptr<fin) do
 begin
  adec.Disassemble(ptr,ACodeBytes,ACode);
  Writeln(ACodeBytes:32,' ',ACode);
 end;

 adec.Free;
 proc.Free;
end;

procedure test_jit;
begin
 writeln('test_jit');
end;


//rdi,rsi,edx
procedure copyout_mov(vaddr:Pointer;cb:tcopy_cb;size:Integer);
var
 data:array[0..31] of Byte;
begin
 if pmap_test_cross(QWORD(vaddr),size-1) then
 begin
  cb(@data); //xmm->data
  copyout(@data,vaddr,size);
 end else
 begin
  vaddr:=uplift(vaddr);
  cb(vaddr); //xmm->vaddr
 end;
end;

//rdi,rsi,edx
procedure copyin_mov(vaddr:Pointer;cb:tcopy_cb;size:Integer);
var
 data:array[0..31] of Byte;
begin
 if pmap_test_cross(QWORD(vaddr),size-1) then
 begin
  copyin(vaddr,@data,size);
  cb(@data); //data->xmm
 end else
 begin
  vaddr:=uplift(vaddr);
  cb(vaddr); //vaddr->xmm
 end;
end;

function classif_memop(var din:TInstruction):t_memop_type;
begin
 if (ofMemory in din.Operand[1].Flags) then
 begin
  Result:=moCopyout;
 end else
 if (ofMemory in din.Operand[2].Flags) then
 begin
  Result:=moCopyin;
 end else
 begin
  Assert(false,'classif_memop');
 end;
end;

function get_lea_id(memop:t_memop_type):Byte;
begin
 case memop of
  moCopyout:Result:=1;
  moCopyin :Result:=2;
 end;
end;

function get_reg_id(memop:t_memop_type):Byte;
begin
 case memop of
  moCopyout:Result:=2;
  moCopyin :Result:=1;
 end;
end;

function GetTargetOfs(var ctx:t_jit_context;id:Byte;var ofs:Int64):Boolean;
var
 i:Integer;
begin
 Result:=True;
 i:=ctx.din.Operand[id].CodeIndex;
 case ctx.din.Operand[id].ByteCount of
   1: ofs:=PShortint(@ctx.Code[i])^;
   2: ofs:=PSmallint(@ctx.Code[i])^;
   4: ofs:=PInteger (@ctx.Code[i])^;
   8: ofs:=PInt64   (@ctx.Code[i])^;
   else
      Result:=False;
 end;
end;

procedure build_lea(var ctx:t_jit_context;id:Byte);
var
 RegValue:TRegValues;
 adr,tdr:t_jit_reg;
 i:Integer;
 ofs:Int64;
begin
 RegValue:=ctx.din.Operand[id].RegValue;

 adr:=t_jit_builder.rdi;
 adr.ARegValue[0].ASize:=RegValue[0].ASize;

 tdr:=t_jit_builder.rcx;

 with ctx.builder do
 begin
  movq(tdr,[GS+Integer(teb_thread)]);

  i:=GetFrameOffsetInt(RegValue[0]);
  Assert(i<>0,'build_lea');

  if (RegValue[0].ASize<>os64) then
  begin
   xorq(rdi,rdi);
  end;

  movq(adr,[tdr+i]);

  if (RegValue[0].AScale>1) then
  begin
   leaq(adr,[adr*RegValue[0].AScale])
  end;

  if (RegValue[1].AType<>regNone) then
  begin
   i:=GetFrameOffsetInt(RegValue[1]);
   Assert(i<>0,'build_lea');

   addq(adr,[tdr+i]);
  end;
 end;

 ofs:=0;
 if GetTargetOfs(ctx,id,ofs) then
 begin
  with ctx.builder do
  begin
   leaq(adr,[adr+ofs]);
  end;
 end;
end;

//

procedure get_size_info(Size:TOperandSize;var byte_size:Integer;var reg:t_jit_reg);
begin
 case Size of
   os8:
   begin
    byte_size:=1;
    reg:=t_jit_builder.sil;
   end;
  os16:
   begin
    byte_size:=2;
    reg:=t_jit_builder.si;
   end;
  os32:
   begin
    byte_size:=4;
    reg:=t_jit_builder.esi;
   end;
  os64:
   begin
    byte_size:=8;
    reg:=t_jit_builder.rsi;
   end;
  else
   begin
    Writeln('get_size_info (',Size,')');
    Assert(false,'get_size_info (size)');
   end;
 end;
end;

procedure build_mov(var ctx:t_jit_context;id:Byte;memop:t_memop_type);
var
 i,copy_size,reg_size:Integer;
 imm:Int64;
 link:t_jit_i_link;
 mem,reg:t_jit_reg;
begin

 get_size_info(ctx.din.Operand[get_lea_id(memop)].Size,copy_size,mem);

 get_size_info(ctx.din.Operand[id].Size,reg_size,reg);

 case memop of
  moCopyout:
   begin
    with ctx.builder do
    begin
     //input:rdi

     if (copy_size=1) then
     begin
      call(@uplift); //input:rdi output:rax=rdi
     end else
     begin
      link:=leaj(rsi,[rip+$FFFF],-1);

      movi(edx,copy_size);

      call(@copyout_mov); //rdi,rsi,edx

      reta;

      //input:rdi

      link._label:=_label;
     end;

     imm:=0;
     if GetTargetOfs(ctx,id,imm) then
     begin
      //imm const

      if (copy_size>reg_size) or (imm=0) then
      begin
       xorq(rsi,rsi);
      end;

      if (imm<>0) then
      begin
       movi(reg,imm);
      end;

      movq([rdi],mem); //TODO movi([rdi],imm);
     end else
     begin
      movq(rcx,[GS+Integer(teb_thread)]);

      i:=GetFrameOffsetInt(ctx.din.Operand[id].RegValue[0]);
      Assert(i<>0,'build_mov');

      if (copy_size>reg_size) then
      begin
       xorq(rsi,rsi);
      end;

      movq(reg,[rcx+i]);
      movq([rdi],mem);
     end;

     reta;

    end;
   end;
  moCopyin:
   begin
    with ctx.builder do
    begin
     //input:rdi

     if (copy_size=1) then
     begin
      call(@uplift); //input:rdi output:rax=rdi
     end else
     begin
      link:=movj(rsi,[rip+$FFFF],-1);

      movi(edx,copy_size);

      call(@copyin_mov); //rdi,rsi,edx

      reta;

      //input:rdi

      link._label:=_label;
     end;

     movq(rcx,[GS+Integer(teb_thread)]);

     i:=GetFrameOffsetInt(ctx.din.Operand[id].RegValue[0]);
     Assert(i<>0,'build_mov');

     if (copy_size<reg_size) then
     begin
      xorq(rsi,rsi);
     end;

     movq(mem,[rdi]);
     movq([rcx+i],reg);

     reta;
    end;
   end;
 end; //case
end;

//

Const
 rflags_offset=Integer(ptruint(@p_kthread(nil)^.td_frame.tf_rflags));

procedure build_load_flags(var ctx:t_jit_context);
begin
 //input rcx:curkthread

 with ctx.builder do
 begin
  movq(ah,[rcx+rflags_offset]);
  sahf
 end;
end;

procedure build_save_flags(var ctx:t_jit_context);
begin
 //input rcx:curkthread

 with ctx.builder do
 begin
  lahf;
  movq([rcx+rflags_offset],ah);
 end;
end;

//

procedure build_cmp(var ctx:t_jit_context;id:Byte;memop:t_memop_type);
var
 i,copy_size,reg_size:Integer;
 imm:Int64;
 link:t_jit_i_link;
 mem,reg:t_jit_reg;
begin

 get_size_info(ctx.din.Operand[get_lea_id(memop)].Size,copy_size,mem);

 get_size_info(ctx.din.Operand[id].Size,reg_size,reg);

 with ctx.builder do
 begin

  case memop of
   moCopyout:
    begin
     with ctx.builder do
     begin
      //input:rdi

      if (copy_size=1) then
      begin
       call(@uplift); //input:rdi output:rax=rdi
      end else
      begin
       link:=leaj(rsi,[rip+$FFFF],-1);

       movi(edx,copy_size);

       call(@copyout_mov); //rdi,rsi,edx

       reta;

       //input:rdi

       link._label:=_label;
      end;

      movq(rcx,[GS+Integer(teb_thread)]);

      imm:=0;
      if GetTargetOfs(ctx,id,imm) then
      begin
       //imm const

       build_load_flags(ctx);
       if (reg_size=1) and (copy_size<>1) then
       begin
        cmpi8(mem.ARegValue[0].ASize,[rdi],imm);
       end else
       begin
        cmpi(mem.ARegValue[0].ASize,[rdi],imm);
       end;
       build_save_flags(ctx);

      end else
      begin
       i:=GetFrameOffsetInt(ctx.din.Operand[id].RegValue[0]);
       Assert(i<>0,'build_cmp');

       if (copy_size>reg_size) then
       begin
        xorq(rsi,rsi);
       end;

       movq(reg,[rcx+i]);

       build_load_flags(ctx);
       cmpq([rdi],mem);
       build_save_flags(ctx);
      end;


      reta;
     end;
    end;
   moCopyin:
    begin
     with ctx.builder do
     begin

      //input:rdi

      if (copy_size=1) then
      begin
       call(@uplift); //input:rdi output:rax=rdi
      end else
      begin
       link:=leaj(rsi,[rip+$FFFF],-1);

       movi(edx,copy_size);

       call(@copyout_mov); //rdi,rsi,edx

       reta;

       //input:rdi

       link._label:=_label;
      end;

      movq(rcx,[GS+Integer(teb_thread)]);

      i:=GetFrameOffsetInt(ctx.din.Operand[id].RegValue[0]);
      Assert(i<>0,'build_cmp');

      if (copy_size<reg_size) then
      begin
       xorq(rsi,rsi);
      end;

      movq(reg,[rcx+i]);

      build_load_flags(ctx);
      cmpq(mem,[rdi]);
      build_save_flags(ctx);

      reta;

     end;
    end;
  end; //case

 end;

end;


//

procedure build_vmovdqu(var ctx:t_jit_context;id:Byte;memop:t_memop_type);
var
 link:t_jit_i_link;
 dst:t_jit_reg;
begin
 case memop of
  moCopyout:
   begin
    with ctx.builder do
    begin
     //input:rdi

     link:=leaj(rsi,[rip+$FFFF],-1);

     case ctx.din.Operand[id].RegValue[0].ASize of
      os128:movi(edx,16);
      os256:movi(edx,32);
      else
       Assert(false);
     end;

     call(@copyout_mov); //rdi,rsi,edx

     reta;

     //input:rdi

     link._label:=_label;

     dst:=Default(t_jit_reg);
     dst.ARegValue:=ctx.din.Operand[id].RegValue;

     vmovdqu([rdi],dst);

     reta;
    end;
   end;
  moCopyin:
   begin
    with ctx.builder do
    begin
     //input:rdi

     link:=movj(rsi,[rip+$FFFF],-1);

     case ctx.din.Operand[id].RegValue[0].ASize of
      os128:movi(edx,16);
      os256:movi(edx,32);
      else
       Assert(false);
     end;

     call(@copyin_mov); //rdi,rsi,edx

     reta;

     //input:rdi

     link._label:=_label;

     dst:=Default(t_jit_reg);
     dst.ARegValue:=ctx.din.Operand[id].RegValue;

     vmovdqu(dst,[rdi]);

     reta;
    end;
   end;
 end; //case
end;

procedure build_vmovups(var ctx:t_jit_context;id:Byte;memop:t_memop_type);
var
 link:t_jit_i_link;
 dst:t_jit_reg;
begin
 case memop of
  moCopyout:
   begin
    with ctx.builder do
    begin
     //input:rdi

     link:=leaj(rsi,[rip+$FFFF],-1);

     case ctx.din.Operand[id].RegValue[0].ASize of
      os128:movi(edx,16);
      os256:movi(edx,32);
      else
       Assert(false);
     end;

     call(@copyout_mov); //rdi,rsi,edx

     reta;

     //input:rdi

     link._label:=_label;

     dst:=Default(t_jit_reg);
     dst.ARegValue:=ctx.din.Operand[id].RegValue;

     vmovups([rdi],dst);

     reta;
    end;
   end;
  moCopyin:
   begin
    with ctx.builder do
    begin
     //input:rdi

     link:=movj(rsi,[rip+$FFFF],-1);

     case ctx.din.Operand[id].RegValue[0].ASize of
      os128:movi(edx,16);
      os256:movi(edx,32);
      else
       Assert(false);
     end;

     call(@copyin_mov); //rdi,rsi,edx

     reta;

     //input:rdi

     link._label:=_label;

     dst:=Default(t_jit_reg);
     dst.ARegValue:=ctx.din.Operand[id].RegValue;

     vmovups(dst,[rdi]);

     reta;
    end;
   end;
 end; //case
end;

procedure build_vmovdqa(var ctx:t_jit_context;id:Byte;memop:t_memop_type);
var
 dst:t_jit_reg;
begin
 case memop of
  moCopyout:
   begin
    with ctx.builder do
    begin
     //input:rdi

     call(@uplift); //input:rdi output:rax

     dst:=Default(t_jit_reg);
     dst.ARegValue:=ctx.din.Operand[id].RegValue;

     vmovdqa([rax],dst);

     reta;
    end;
   end;
  moCopyin:
   begin
    with ctx.builder do
    begin
     //input:rdi

     call(@uplift); //input:rdi output:rax

     dst:=Default(t_jit_reg);
     dst.ARegValue:=ctx.din.Operand[id].RegValue;

     vmovdqa(dst,[rax]);

     reta;
    end;
   end;
 end; //case
end;

function generate_jit(var ctx:t_jit_context):p_stub_chunk;
label
 _err;
var
 memop:t_memop_type;
 jit_size,size,i:Integer;
begin

 //ctx.builder.call(@test_jit); //test

 case ctx.din.OpCode.Opcode of
  OPmov:
   begin
    case ctx.din.OpCode.Suffix of

     OPSnone:
      begin
       memop:=classif_memop(ctx.din);

       build_lea(ctx,get_lea_id(memop));
       build_mov(ctx,get_reg_id(memop),memop);
      end;

     OPSx_dqu:
      begin
       memop:=classif_memop(ctx.din);

       build_lea(ctx,get_lea_id(memop));
       build_vmovdqu(ctx,get_reg_id(memop),memop);
      end;

     OPSx_dqa:
      begin
       memop:=classif_memop(ctx.din);

       build_lea(ctx,get_lea_id(memop));
       build_vmovdqa(ctx,get_reg_id(memop),memop);
      end

     else
      goto _err;
    end; //case
   end; //OPmov

  OPcmp:
   begin
    case ctx.din.OpCode.Suffix of

     OPSnone:
      begin
       memop:=classif_memop(ctx.din);

       build_lea(ctx,get_lea_id(memop));
       build_cmp(ctx,get_reg_id(memop),memop);
      end;

     else
      goto _err;
    end; //case
   end; //OPcmp

  OPmovu:
   begin
    case ctx.din.OpCode.Suffix of

     OPSx_ps:
       begin
        memop:=classif_memop(ctx.din);

        build_lea(ctx,get_lea_id(memop));
        build_vmovups(ctx,get_reg_id(memop),memop);
       end;

     else
      goto _err;
    end; //case
   end; //OPmovu

  else
   begin
    _err:
    Writeln('Unhandled jit:',
            ctx.din.OpCode.Opcode,' ',
            ctx.din.OpCode.Suffix,' ',
            ctx.din.Operand[1].Size,' ',
            ctx.din.Operand[2].Size);
    Assert(false);
   end;
 end;

 jit_size:=ctx.builder.GetMemSize;
 size:=SizeOf(t_jit_code)+jit_size;

 Result:=p_alloc(nil,size);

 ctx.jit_code:=@Result^.body;
 ctx.jit_code^:=Default(t_jit_code);

 ctx.jit_code^.frame.call:=@ctx.jit_code^.code;
 ctx.jit_code^.frame.addr:=Pointer(ctx.rip_addr);
 ctx.jit_code^.frame.reta:=Pointer(ctx.rip_addr+ctx.dis.CodeIdx);

 ctx.jit_code^.o_len :=ctx.dis.CodeIdx;
 ctx.jit_code^.o_data:=c_data16;

 Move(ctx.Code,ctx.jit_code^.o_data,ctx.dis.CodeIdx);

 ctx.builder.SaveTo(@ctx.jit_code^.code,jit_size);

 Writeln('--------------------------------':32,' ','print patch');
 print_disassemble(@ctx.jit_code^.code,ctx.builder.GetInstructionsSize);

 if (Length(ctx.builder.AData))<>0 then
 begin
  Writeln('--------------------------------':32,' ','print data');
  For i:=0 to High(ctx.builder.AData) do
  begin
   Writeln('[0x'+HexStr(ctx.builder.AData[i])+']':32,' data:',i);
  end;
  Writeln('--------------------------------':32,' ','print data');
 end;

 Writeln;

 ///
end;


end.
