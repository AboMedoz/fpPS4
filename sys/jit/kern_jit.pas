unit kern_jit;

{$mode ObjFPC}{$H+}
{$CALLING SysV_ABI_CDecl}

interface

uses
 mqueue,
 x86_fpdbgdisas,
 x86_jit,
 kern_jit_ctx;

var
 print_asm :Boolean=False;
 debug_info:Boolean=False;

procedure pick(var ctx:t_jit_context2;preload:Pointer);
procedure pick_locked(var ctx:t_jit_context2);

implementation

uses
 sysutils,
 vm_pmap_prot,
 vm_pmap,
 vm_map,
 sys_bootparam,
 kern_proc,
 kern_jit_ops,
 kern_jit_ops_sse,
 kern_jit_ops_avx,
 kern_jit_dynamic,
 kern_jit_test,
 kern_jit_asm,
 kern_thr,
 subr_backtrace;

procedure jit_assert(tf_rip:QWORD);
var
 td:p_kthread;
begin
 td:=curkthread;
 jit_save_to_sys_save(td);
 td^.td_frame.tf_rip:=tf_rip;
 print_error_td('Assert in guest code!');
 Assert(false);
end;

procedure _jit_assert; assembler; nostackframe;
asm
 call jit_save_ctx
 mov  %r14,%rdi
 jmp  jit_assert
end;

procedure jit_system_error;
begin
 Assert(False,'jit_system_error');
end;

procedure jit_unknow_int;
begin
 Assert(False,'jit_unknow_int');
end;

procedure jit_exit_proc(tf_rip:QWORD);
var
 td:p_kthread;
begin
 td:=curkthread;
 jit_save_to_sys_save(td);
 td^.td_frame.tf_rip:=tf_rip;
 print_error_td('TODO:jit_exit_proc');
 Assert(False);
end;

procedure _jit_exit_proc; assembler; nostackframe;
asm
 call jit_save_ctx
 mov  %r14,%rdi
 jmp  jit_exit_proc
end;

procedure _jit_cpuid(tf_rip,rax:qword);
var
 td:p_kthread;
begin
 td:=curkthread;
 jit_save_to_sys_save(td);
 td^.td_frame.tf_rip:=tf_rip;
 print_error_td('TODO:jit_cpuid:0x'+HexStr(rax,16));
 Assert(False);
end;

//cpuid(0x0)       :eax=0xd        ebx=0x68747541 ecx=0x444d4163 edx=0x69746e65
//cpuid(0x1)       :eax=0x710f31   ebx=0x7080800  ecx=0x3ed8220b edx=0x178bfbff
//0x4
//0x6
//cpuid(0x7)       :eax=0x0        ebx=0x0        ecx=0x0        edx=0x0
//0xb

//0x40000000
//0x40000010

//cpuid(0x80000000):eax=0x8000001e ebx=0x68747541 ecx=0x444d4163 edx=0x69746e65
//cpuid(0x80000001):eax=0x710f31   ebx=0x0        ecx=0x154837ff edx=0x2fd3fbff
//0x80000002
//0x80000004
//0x80000005
//0x80000006
//cpuid(0x80000008):eax=0x3028     ebx=0x0        ecx=0x3007     edx=0x0

//0xc0000000
//0xc0000001
procedure jit_cpuid; assembler; nostackframe;
label
 _cpuid_0,
 _cpuid_1,
 _cpuid_7,
 _cpuid_80000000,
 _cpuid_80000001,
 _cpuid_80000008;
asm
 pushf

 cmp $0,%eax
 je _cpuid_0

 cmp $1,%eax
 je _cpuid_1

 cmp $7,%eax
 je _cpuid_7

 cmp $0x80000000,%eax
 je _cpuid_80000000

 cmp $0x80000001,%eax
 je _cpuid_80000001

 cmp $0x80000008,%eax
 je _cpuid_80000008

 //unknow id
 popf
 mov  %rax,%r15
 call jit_save_ctx
 mov  %r14,%rdi
 mov  %r15,%rsi
 jmp  _jit_cpuid



 _cpuid_0:

 //cpu_high
 mov $0xD,%eax

 //cpu_vendor
 mov $0x68747541,%ebx
 mov $0x69746E65,%edx
 mov $0x444D4163,%ecx

 popf
 ret

 _cpuid_1:

 //get host
 cpuid

 //if ((cpu_id & 0xffffff80) == 0x740f00) then
 //if "machdep.bootparams.base_ps4_mode" then sceKernelHasNeoMode

 //if ((cpu_id & 0xffffff80) == 0x740f00) then sceKernelIsAuthenticNeo

 mov p_cpuid    ,%eax //cpu_id

 mov $0x178bfbff,%edx //cpu_feature
 mov $0x3ed8220b,%ecx //cpu_feature2

//                    0x07080800
//CPUID_BRAND_INDEX   0x000000ff
//CPUID_CLFUSH_SIZE   0x0000ff00
//CPUID_HTT_CORES     0x00ff0000  //sceKernelGetCurrentCpu 0..7
//CPUID_LOCAL_APIC_ID 0xff000000

 and $0xFF000000,%ebx //filter CPUID_LOCAL_APIC_ID

 or  $0x00080800,%ebx //cpu_procinfo

 popf
 ret

 _cpuid_7:

 mov $0x0,%eax
 mov $0x0,%ebx
 mov $0x0,%edx
 mov $0x0,%ecx

 popf
 ret

 _cpuid_80000000:

 //cpu_exthigh
 mov $0x8000001E,%eax

 //cpu_vendor
 mov $0x68747541,%ebx
 mov $0x69746e65,%edx
 mov $0x444d4163,%ecx

 popf
 ret

 _cpuid_80000001:

 mov $0x00710f31,%eax
 mov $0x00000000,%ebx
 mov $0x2fd3fbff,%edx //amd_feature
 mov $0x154837ff,%ecx //amd_feature2

 popf
 ret

 _cpuid_80000008:

 mov $0x00003028,%eax
 mov $0x00000000,%ebx
 mov $0x00000000,%edx
 mov $0x00003007,%ecx //cpu_procinfo2

 popf
 ret

end;

procedure op_jmp_dispatcher(var ctx:t_jit_context2);
begin
 with ctx.builder do
 begin
  leap(r15);
  call_far(@jit_plt_cache); //input:r14,r15
 end;
end;

procedure op_call_dispatcher(var ctx:t_jit_context2);
begin
 with ctx.builder do
 begin
  leap(r15);
  call_far(@jit_plt_cache); //input:r14,r15
 end;
end;

procedure trim_flow(var ctx:t_jit_context2);
begin
 ctx.trim:=True;
end;

procedure op_push_rip(var ctx:t_jit_context2);
var
 stack:TRegValue;
 imm:Int64;
begin
 //lea rsp,[rsp-8]
 //mov [rsp],r14

 with ctx.builder do
 begin
  stack:=r_tmp0;

  op_load_rsp(ctx,stack);
  leaq(stack,[stack-8]);

  op_uplift(ctx,os64); //in/out:r14

  imm:=Int64(ctx.ptr_next);

  if (classif_offset_se64(imm)=os64) then
  begin
   if (classif_offset_u64(imm)=os64) then
   begin
    //64bit imm
    movi64(r_tmp1,imm);
    movq([stack],r_tmp1);
   end else
   begin
    //32bit zero extend
    movi(new_reg_size(r_tmp1,os32),imm);
    movq([stack],r_tmp1);
   end;
  end else
  begin
   //32bit sign extend
   movi([stack,os64],imm);
  end;

  //For transactionality,
  //first we move the memory,
  //then we update the register
  //[op_uplift] op_load_rsp(ctx,stack);
  //[op_uplift] leaq(stack,[stack-8]);
  op_save_rsp(ctx,stack);

 end;
end;

procedure op_pop_rip(var ctx:t_jit_context2;imm:Word); //out:r14
var
 stack:TRegValue;
begin
 //mov r14,[rsp]
 //lea rsp,[rsp+8+imm]

 with ctx.builder do
 begin
  stack:=r_tmp0;

  op_load_rsp(ctx,stack);

  op_uplift(ctx,os64); //in/out:r14

  //load to tmp
  movq(r_tmp1,[stack]);

  //For transactionality,
  //first we move the memory,
  //then we update the register
  //[op_uplift] op_load_rsp(ctx,stack);
  leaq(stack,[stack+8+imm]);
  op_save_rsp(ctx,stack);

  //out:r14
  movq(r_tmp0,r_tmp1);
 end;
end;

procedure op_call(var ctx:t_jit_context2);
var
 id:t_jit_i_link;
 ofs:Int64;
 dst:Pointer;
 new1,new2:TRegValue;
 link:t_jit_i_link;
begin
 op_push_rip(ctx);

 if (ctx.din.Operand[1].RegValue[0].AType=regNone) then
 begin
  //imm offset

  ofs:=0;
  GetTargetOfs(ctx.din,ctx.code,1,ofs);

  dst:=ctx.ptr_next+ofs;

  if ctx.is_text_addr(QWORD(dst)) and
     (not exist_entry(dst)) then
  begin
   //near

   link:=ctx.get_link(dst);

   if (link<>nil_link) then
   begin
    ctx.builder.jmp(link);
    ctx.add_forward_point(fpCall,dst);
   end else
   begin
    id:=ctx.builder.jmp(nil_link);
    ctx.add_forward_point(fpCall,id,dst);
   end;
  end else
  begin
   op_set_r14_imm(ctx,Int64(dst));
   //
   op_call_dispatcher(ctx);
  end;

 end else
 if is_memory(ctx.din) then
 begin
  new1:=new_reg_size(r_tmp0,ctx.din.Operand[1]);
  //
  build_lea(ctx,1,new1,[inc8_rsp,code_ref]);
  //
  op_uplift(ctx,os64); //in/out:r14
  //
  ctx.builder.movq(new1,[new1]);
  //
  op_call_dispatcher(ctx);
 end else
 if is_preserved(ctx.din) then
 begin
  new1:=new_reg_size(r_tmp0,ctx.din.Operand[1]);
  //
  op_load(ctx,new1,1);
  //
  if is_rsp(ctx.din.Operand[1].RegValue[0]) then
  begin
   ctx.builder.leaq(new1,[new1+8]);
  end;
  //
  op_call_dispatcher(ctx);
 end else
 begin
  new1:=new_reg_size(r_tmp0,ctx.din.Operand[1]);
  new2:=new_reg(ctx.din.Operand[1]);
  //
  ctx.builder.movq(new1,new2);
  //
  op_call_dispatcher(ctx);
 end;

 //
 ctx.add_forward_point(fpCall,ctx.ptr_next);
end;

procedure op_ret(var ctx:t_jit_context2);
var
 imm:Int64;
begin
 imm:=0;
 GetTargetOfs(ctx.din,ctx.code,1,imm);
 //
 op_pop_rip(ctx,imm); //out:r14
 //
 op_jmp_dispatcher(ctx);
 //
 trim_flow(ctx);
end;

procedure op_jmp(var ctx:t_jit_context2);
var
 id:t_jit_i_link;
 ofs:Int64;
 dst:Pointer;
 new1,new2:TRegValue;
 link:t_jit_i_link;
begin
 if (ctx.din.Operand[1].RegValue[0].AType=regNone) then
 begin
  //imm offset

  ofs:=0;
  GetTargetOfs(ctx.din,ctx.code,1,ofs);

  dst:=ctx.ptr_next+ofs;

  if ctx.is_text_addr(QWORD(dst)) and
     (not exist_entry(dst)) then
  begin
   //near

   link:=ctx.get_link(dst);

   if (link<>nil_link) then
   begin
    ctx.builder.jmp(link);
    ctx.add_forward_point(fpCall,dst);
   end else
   begin
    id:=ctx.builder.jmp(nil_link);
    ctx.add_forward_point(fpCall,id,dst);
   end;
  end else
  begin
   op_set_r14_imm(ctx,Int64(dst));
   //
   op_jmp_dispatcher(ctx);
  end;

 end else
 if is_memory(ctx.din) then
 begin
  new1:=new_reg_size(r_tmp0,ctx.din.Operand[1]);
  //
  build_lea(ctx,1,new1,[code_ref]);
  //
  op_uplift(ctx,os64); //in/out:r14
  //
  ctx.builder.movq(new1,[new1]);
  //
  op_jmp_dispatcher(ctx);
 end else
 if is_preserved(ctx.din) then
 begin
  new1:=new_reg_size(r_tmp0,ctx.din.Operand[1]);
  //
  op_load(ctx,new1,1);
  //
  op_jmp_dispatcher(ctx);
 end else
 begin
  new1:=new_reg_size(r_tmp0,ctx.din.Operand[1]);
  new2:=new_reg(ctx.din.Operand[1]);
  //
  ctx.builder.movq(new1,new2);
  //
  op_jmp_dispatcher(ctx);
 end;
 //
 trim_flow(ctx);
end;

procedure op_jcc(var ctx:t_jit_context2);
var
 id1,id2:t_jit_i_link;
 ofs:Int64;
 dst:Pointer;
 link:t_jit_i_link;
begin
 ofs:=0;
 GetTargetOfs(ctx.din,ctx.code,1,ofs);

 dst:=ctx.ptr_next+ofs;

 if ctx.is_text_addr(QWORD(dst)) and
    (not exist_entry(dst)) then
 begin
  //near

  link:=ctx.get_link(dst);

  id1:=ctx.builder.jcc(ctx.din.OpCode.Suffix,link);

  if (link<>nil_link) then
  begin
   ctx.add_forward_point(fpCall,dst);
  end else
  begin
   ctx.add_forward_point(fpCall,id1,dst);
  end;
 end else
 begin
  id1:=ctx.builder.jcc(ctx.din.OpCode.Suffix,nil_link,os8);

  id2:=ctx.builder.jmp(nil_link,os8);
   id1._label:=ctx.builder.get_curr_label.after;
   op_set_r14_imm(ctx,Int64(dst));
   op_jmp_dispatcher(ctx);
  id2._label:=ctx.builder.get_curr_label.after;
 end;
end;

procedure op_loop(var ctx:t_jit_context2);
var
 id1,id2,id3:t_jit_i_link;
 ofs:Int64;
 dst:Pointer;
 link:t_jit_i_link;
begin
 ofs:=0;
 GetTargetOfs(ctx.din,ctx.code,1,ofs);

 dst:=ctx.ptr_next+ofs;

 id1:=ctx.builder.loop(ctx.din.OpCode.Suffix,nil_link,ctx.dis.AddressSize);

 if ctx.is_text_addr(QWORD(dst)) and
    (not exist_entry(dst)) then
 begin
  //near

  link:=ctx.get_link(dst);

  id2:=ctx.builder.jmp(nil_link,os8);
   id1._label:=ctx.builder.get_curr_label.after;
   id3:=ctx.builder.jmp(nil_link);
  id2._label:=ctx.builder.get_curr_label.after;

  if (link<>nil_link) then
  begin
   ctx.add_forward_point(fpCall,dst);
  end else
  begin
   ctx.add_forward_point(fpCall,id3,dst);
  end;
 end else
 begin
  id2:=ctx.builder.jmp(nil_link,os8);
   id1._label:=ctx.builder.get_curr_label.after;
   op_set_r14_imm(ctx,Int64(dst));
   op_jmp_dispatcher(ctx);
  id2._label:=ctx.builder.get_curr_label.after;

 end;
end;

procedure op_jcxz(var ctx:t_jit_context2);
var
 id1,id2,id3:t_jit_i_link;
 ofs:Int64;
 dst:Pointer;
 link:t_jit_i_link;
begin
 ofs:=0;
 GetTargetOfs(ctx.din,ctx.code,1,ofs);

 dst:=ctx.ptr_next+ofs;

 id1:=ctx.builder.jcxz(nil_link,ctx.dis.AddressSize);

 if ctx.is_text_addr(QWORD(dst)) and
    (not exist_entry(dst)) then
 begin
  link:=ctx.get_link(dst);

  id2:=ctx.builder.jmp(nil_link,os8);
   id1._label:=ctx.builder.get_curr_label.after;
   id3:=ctx.builder.jmp(nil_link);
  id2._label:=ctx.builder.get_curr_label.after;

  if (link<>nil_link) then
  begin
   ctx.add_forward_point(fpCall,dst);
  end else
  begin
   ctx.add_forward_point(fpCall,id3,dst);
  end;
 end else
 begin

  id2:=ctx.builder.jmp(nil_link,os8);
   id1._label:=ctx.builder.get_curr_label.after;
   op_set_r14_imm(ctx,Int64(dst));
   op_jmp_dispatcher(ctx);
  id2._label:=ctx.builder.get_curr_label.after;

 end;
end;

const
 movsx8_desc:t_op_type=(op:$0FBE);
 movsxd_desc:t_op_type=(op:$63);

procedure op_push(var ctx:t_jit_context2);
var
 imm:Int64;
 stack,new:TRegValue;
begin
 //lea rsp,[rsp-len]
 //mov [rsp],reg

 with ctx.builder do
 begin
  stack:=r_tmp0;

  if is_memory(ctx.din) then
  begin
   build_lea(ctx,1,r_tmp0);

   op_uplift(ctx,os64); //in/out:r14

   new:=new_reg_size(r_tmp1,ctx.din.Operand[1]);

   movq(new,[r_tmp0]);
  end else
  if (ctx.din.Operand[1].ByteCount<>0) then
  begin
   imm:=0;
   GetTargetOfs(ctx.din,ctx.code,1,imm);

   new:=new_reg_size(r_tmp1,ctx.din.Operand[1].Size);

   movi(new,imm);
  end else
  if is_preserved(ctx.din) then
  begin
   new:=new_reg_size(r_tmp1,ctx.din.Operand[1]);

   op_load(ctx,new,1);
  end else
  begin
   new:=new_reg(ctx.din.Operand[1]);
  end;

  //sign extend
  case new.ASize of
    os8:
     begin
      ctx.builder._RR(movsx8_desc,new,new,os64);
      new:=new_reg_size(new,os64);
     end;
   os32:
     begin
      ctx.builder._RR(movsxd_desc,new,new,os64);
      new:=new_reg_size(new,os64);
     end
   else;
  end;

  op_load_rsp(ctx,stack);
  leaq(stack,[stack-OPERAND_BYTES[new.ASize]]);

  op_uplift(ctx,new.ASize); //in/out:r14

  movq([stack],new);

  //For transactionality,
  //first we move the memory,
  //then we update the register
  //[op_uplift] op_load_rsp(ctx,stack);
  //[op_uplift] leaq(stack,[stack-OPERAND_BYTES[new.ASize]]);
  op_save_rsp(ctx,stack);

 end;
end;

procedure op_pushf(var ctx:t_jit_context2);
var
 mem_size:TOperandSize;
 stack,new:TRegValue;
begin
 //lea rsp,[rsp-len]
 //mov [rsp],rflags

 with ctx.builder do
 begin
  stack:=r_tmp0;

  new:=new_reg_size(r_tmp1,ctx.din.Operand[1]);

  mem_size:=ctx.din.Operand[1].Size;

  pushfq(mem_size);
  pop(new);

  op_load_rsp(ctx,stack);
  leaq(stack,[stack-OPERAND_BYTES[mem_size]]);

  op_uplift(ctx,mem_size); //in/out:r14

  movq([stack],new);

  //For transactionality,
  //first we move the memory,
  //then we update the register
  //[op_uplift] op_load_rsp(ctx,stack);
  //[op_uplift] leaq(stack,[stack-OPERAND_BYTES[mem_size]]);
  op_save_rsp(ctx,stack);

 end;
end;

procedure op_leave(var ctx:t_jit_context2);
var
 new,stack:TRegValue;
begin
 //mov rsp,rbp
 //mov rbp,[rsp]
 //lea rsp,[rsp+len]

 with ctx.builder do
 begin
  stack:=r_tmp0;
  new  :=r_tmp0;

  op_load_rbp(ctx,stack);

  op_uplift(ctx,os64); //in/out:r14

  movq(new,[stack]);

  //For transactionality,
  //first we move the memory,
  //then we update the register
  //[op_uplift] op_load_rbp(ctx,stack);
  //[op_uplift] op_save_rsp(ctx,stack);
  op_save_rbp(ctx,new);

  //[op_uplift] op_load_rsp(ctx,stack);
  leaq(stack,[stack+OPERAND_BYTES[ctx.dis.OperandSize]]);
  op_save_rsp(ctx,stack);
 end;

end;

procedure op_popf(var ctx:t_jit_context2);
var
 mem_size:TOperandSize;
 new,stack:TRegValue;
begin
 //mov rflags,[rsp]
 //lea rsp,[rsp+len]

 with ctx.builder do
 begin
  stack:=r_tmp0;

  new:=new_reg_size(r_tmp0,ctx.din.Operand[1]);

  mem_size:=ctx.din.Operand[1].Size;

  op_load_rsp(ctx,stack);

  op_uplift(ctx,mem_size); //in/out:r14

  movq(new,[stack]);
  push(new);
  popfq(mem_size);

  //For transactionality,
  //first we move the memory,
  //then we update the register
  //[op_uplift] op_load_rsp(ctx,stack);
  leaq(stack,[stack+OPERAND_BYTES[new.ASize]]);
  op_save_rsp(ctx,stack);
 end;
end;

procedure op_pop(var ctx:t_jit_context2);
var
 new,stack:TRegValue;
begin
 //mov reg,[rsp]
 //lea rsp,[rsp+len]

 with ctx.builder do
 begin
  stack:=r_tmp0;

  op_load_rsp(ctx,stack);

  op_uplift(ctx,os64); //in/out:r14

  if is_memory(ctx.din) then
  begin
   new:=new_reg_size(r_tmp1,ctx.din.Operand[1]);

   movq(new,[stack]);

   build_lea(ctx,1,r_tmp0);

   op_uplift(ctx,os64); //in/out:r14

   movq([r_tmp0],new);
  end else
  if is_preserved(ctx.din) then
  begin
   new:=new_reg_size(r_tmp0,ctx.din.Operand[1]);

   movq(new,[stack]);

   op_save(ctx,1,fix_size(new));
  end else
  begin
   new:=new_reg(ctx.din.Operand[1]);

   movq(new,[stack]);
  end;

  //For transactionality,
  //first we move the memory,
  //then we update the register
  op_load_rsp(ctx,stack);
  leaq(stack,[stack+OPERAND_BYTES[new.ASize]]);
  op_save_rsp(ctx,stack);
 end;
end;

procedure op_syscall(var ctx:t_jit_context2);
begin
 ctx.add_forward_point(fpCall,ctx.ptr_curr);
 ctx.add_forward_point(fpCall,ctx.ptr_next);
 //
 op_set_rip_imm(ctx,Int64(ctx.ptr_next));
 //
 ctx.builder.call_far(@jit_syscall); //syscall dispatcher
end;

procedure op_int(var ctx:t_jit_context2);
var
 i:Integer;
 id:Byte;
begin
 i:=ctx.din.Operand[1].ByteCount;
 Assert(i=1);
 id:=PByte(ctx.code)[i];

 case id of
  1,3:
   begin
    add_orig(ctx);
   end;

  $41: //assert?
   begin
    //
    op_set_r14_imm(ctx,Int64(ctx.ptr_curr));
    ctx.builder.call_far(@_jit_assert); //TODO error dispatcher
   end;

  $44: //system error?
   begin
    //
    op_set_r14_imm(ctx,Int64(ctx.ptr_curr));
    ctx.builder.call_far(@jit_system_error); //TODO error dispatcher
    trim_flow(ctx);
   end;

  else
   begin
    ctx.builder.call_far(@jit_unknow_int);
    trim_flow(ctx);
   end;
 end;
end;

procedure op_ud2(var ctx:t_jit_context2);
begin
 //exit proc?
 ctx.builder.int3;
 op_set_r14_imm(ctx,Int64(ctx.ptr_curr));
 ctx.builder.call_far(@_jit_exit_proc); //TODO exit dispatcher
 trim_flow(ctx);
end;

procedure op_iretq(var ctx:t_jit_context2);
begin
 //exit proc?
 ctx.builder.int3;
 op_set_r14_imm(ctx,Int64(ctx.ptr_curr));
 ctx.builder.call_far(@_jit_exit_proc); //TODO exit dispatcher
 trim_flow(ctx);
end;

procedure op_hlt(var ctx:t_jit_context2);
begin
 //stop thread?
 ctx.builder.int3;
 op_set_r14_imm(ctx,Int64(ctx.ptr_curr));
 ctx.builder.call_far(@_jit_exit_proc); //TODO exit dispatcher
end;

procedure op_cpuid(var ctx:t_jit_context2);
begin
 op_set_r14_imm(ctx,Int64(ctx.ptr_curr));
 ctx.builder.call_far(@jit_cpuid);
end;

procedure op_rdtsc(var ctx:t_jit_context2);
begin
 add_orig(ctx);
end;

procedure op_nop(var ctx:t_jit_context2);
begin
 //align?
end;

procedure op_invalid(var ctx:t_jit_context2);
begin
 ctx.builder.int3;
 ctx.builder.ud2;
end;

{
 //load flags to al,ah
 seto(al);
 lahf;

 //store flags from al,ah
 addi(al,127);
 sahf;
}

//
procedure op_debug_info(var ctx:t_jit_context2);
var
 link_jmp:t_jit_i_link;
begin
 //debug
 if debug_info then
 begin
  link_jmp:=ctx.builder.jmp(nil_link,os8);
  //
  ctx.builder.cli;
  //op_set_r14_imm(ctx,$FACEADD7);
  op_set_r14_imm(ctx,Int64(ctx.ptr_curr));
  add_orig(ctx);
  op_set_r14_imm(ctx,Int64(ctx.ptr_next));
  //op_set_r14_imm(ctx,$FACEADDE);
  ctx.builder.sti;
  //
  link_jmp._label:=ctx.builder.get_curr_label.after;
 end;
 //debug
end;

procedure init_cbs;
begin

 //

 jit_rep_cbs[repOPins ]:=@op_invalid;
 jit_rep_cbs[repOPouts]:=@op_invalid;
 jit_rep_cbs[repOPret ]:=@op_ret;

 //

 jit_cbs[OPPnone,OPcall,OPSnone]:=@op_call;
 jit_cbs[OPPnone,OPjmp ,OPSnone]:=@op_jmp;
 jit_cbs[OPPnone,OPret ,OPSnone]:=@op_ret;
 jit_cbs[OPPnone,OPretf,OPSnone]:=@op_ret;

 jit_cbs[OPPnone,OPj__,OPSc_o  ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_no ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_b  ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_nb ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_z  ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_nz ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_be ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_nbe]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_s  ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_ns ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_p  ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_np ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_l  ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_nl ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_le ]:=@op_jcc;
 jit_cbs[OPPnone,OPj__,OPSc_nle]:=@op_jcc;

 jit_cbs[OPPnone,OPloop,OPSnone]:=@op_loop;
 jit_cbs[OPPnone,OPloop,OPSc_ne]:=@op_loop;
 jit_cbs[OPPnone,OPloop,OPSc_e ]:=@op_loop;

 jit_cbs[OPPnone,OPjcxz ,OPSnone]:=@op_jcxz;
 jit_cbs[OPPnone,OPjecxz,OPSnone]:=@op_jcxz;
 jit_cbs[OPPnone,OPjrcxz,OPSnone]:=@op_jcxz;

 jit_cbs[OPPnone,OPpush,OPSnone]:=@op_push;
 jit_cbs[OPPnone,OPpop ,OPSnone]:=@op_pop;

 jit_cbs[OPPnone,OPpushf ,OPSnone]:=@op_pushf;
 jit_cbs[OPPnone,OPpushf ,OPSx_q ]:=@op_pushf;

 jit_cbs[OPPnone,OPenter ,OPSnone]:=@op_invalid; //TODO
 jit_cbs[OPPnone,OPleave ,OPSnone]:=@op_leave;

 jit_cbs[OPPnone,OPpopf  ,OPSnone]:=@op_popf;
 jit_cbs[OPPnone,OPpopf  ,OPSx_q ]:=@op_popf;

 jit_cbs[OPPnone,OPsyscall,OPSnone]:=@op_syscall;
 jit_cbs[OPPnone,OPint    ,OPSnone]:=@op_int;
 jit_cbs[OPPnone,OPint1   ,OPSnone]:=@add_orig;
 jit_cbs[OPPnone,OPint3   ,OPSnone]:=@add_orig;
 jit_cbs[OPPnone,OPud1    ,OPSnone]:=@add_orig;
 jit_cbs[OPPnone,OPud2    ,OPSnone]:=@op_ud2;

 jit_cbs[OPPnone,OPiret,OPSnone]:=@op_iretq;
 jit_cbs[OPPnone,OPiret,OPSx_d ]:=@op_iretq;
 jit_cbs[OPPnone,OPiret,OPSx_q ]:=@op_iretq;

 jit_cbs[OPPnone,OPhlt ,OPSnone]:=@op_hlt;

 jit_cbs[OPPnone,OPcpuid,OPSnone]:=@op_cpuid;
 jit_cbs[OPPnone,OPrdtsc,OPSnone]:=@op_rdtsc;

 jit_cbs[OPPnone,OPnop,OPSnone]:=@op_nop;

 jit_cbs[OPPnone,OPin  ,OPSnone]:=@op_invalid;
 jit_cbs[OPPnone,OPins ,OPSx_b ]:=@op_invalid;
 jit_cbs[OPPnone,OPins ,OPSx_w ]:=@op_invalid;
 jit_cbs[OPPnone,OPins ,OPSx_d ]:=@op_invalid;

 jit_cbs[OPPnone,OPout ,OPSnone]:=@op_invalid;
 jit_cbs[OPPnone,OPouts,OPSx_b ]:=@op_invalid;
 jit_cbs[OPPnone,OPouts,OPSx_w ]:=@op_invalid;
 jit_cbs[OPPnone,OPouts,OPSx_d ]:=@op_invalid;

 jit_cbs[OPPnone,OPrdmsr,OPSnone]:=@op_invalid;
 jit_cbs[OPPnone,OPwrmsr,OPSnone]:=@op_invalid;
end;

function test_disassemble(addr:Pointer;vsize:Integer):Boolean;
var
 proc:TDbgProcess;
 adec:TX86AsmDecoder;
 ptr,fin:Pointer;
 ACodeBytes,ACode:RawByteString;
begin
 Result:=True;

 ptr:=addr;
 fin:=addr+vsize;

 proc:=TDbgProcess.Create(dm64);
 adec:=TX86AsmDecoder.Create(proc);

 while (ptr<fin) do
 begin
  adec.Disassemble(ptr,ACodeBytes,ACode);

  case adec.Instr.OpCode.Opcode of
   OPX_Invalid..OPX_GroupP:
    begin
     Result:=False;
     Break;
    end;
   else;
  end;

  if (adec.Instr.Flags * [ifOnly32, ifOnly64, ifOnlyVex] <> []) or
     is_invalid(adec.Instr) then
  begin
   Result:=False;
   Break;
  end;

 end;

 adec.Free;
 proc.Free;
end;

procedure pick(var ctx:t_jit_context2;preload:Pointer); [public, alias:'kern_jit_pick'];
var
 map:vm_map_t;
 node:p_jit_entry_point;
begin
 map:=p_proc.p_vmspace;

 vm_map_lock(map);

  if (preload<>nil) then
  begin
   node:=preload_entry(preload);
   if (node<>nil) then
   begin
    node^.dec_ref;
    vm_map_unlock(map);
    Exit;
   end;
  end;

  pick_locked(ctx);

 vm_map_unlock(map);
end;

var
 _print_stat:Integer=0;

procedure pick_locked(var ctx:t_jit_context2);
const
 SCODES:array[TSimdOpcode] of Byte=(0,0,1,3,2);
 MCODES:array[0..3] of RawByteString=('','0F','0F38','0F3A');
label
 _next,
 _build,
 _invalid;
var
 addr:Pointer;
 ptr:Pointer;

 links:t_jit_context2.t_forward_links;
 entry_link:Pointer;

 dis:TX86Disassembler;
 din:TInstruction;

 cb:t_jit_cb;

 link_new :t_jit_i_link;
 link_curr:t_jit_i_link;
 link_next:t_jit_i_link;

 node,node_curr,node_next:p_jit_instruction;
begin
 if (ctx.max=QWORD(-1)) then
 begin
  //dont scan rip relative
  ctx.max:=0;
 end else
 begin
  ctx.max:=QWORD(ctx.max_forward_point);
 end;

 if (p_print_jit_preload<>0) then
 begin
  Writeln(' ctx.text_start:0x',HexStr(ctx.text_start,16));
  Writeln(' ctx.max       :0x',HexStr(ctx.max,16));
  Writeln(' ctx.text___end:0x',HexStr(ctx.text___end,16));
  Writeln(' ctx.map____end:0x',HexStr(ctx.map____end,16));
 end;

 if System.InterlockedExchange(_print_stat,1)=0 then
 begin
  print_test_jit_cbs(False,True);
 end;

 links:=Default(t_jit_context2.t_forward_links);
 addr:=nil;

 if not ctx.fetch_forward_point(links,addr) then
 begin
  ctx.Free;
  Exit;
 end;

 ctx.trim:=False;

 entry_link:=addr;

 ctx.new_chunk(links.ptype,entry_link);

 ptr:=addr;

 dis:=Default(TX86Disassembler);
 din:=Default(TInstruction);

 while True do
 begin

  if not ctx.is_text_addr(QWORD(ptr)) then
  begin
   if (p_print_jit_preload<>0) then
   begin
    writeln('not excec:0x',HexStr(ptr));
   end;
   goto _invalid;
  end;

  if ((pmap_get_prot(QWORD(ptr)) and PAGE_PROT_EXECUTE)=0) then
  begin
   if (p_print_jit_preload<>0) then
   begin
    writeln('not excec:0x',HexStr(ptr));
   end;
   goto _invalid;
  end;

  ctx.ptr_curr:=ptr;

  //guest->host ptr
  ctx.code:=uplift(ptr);
  ptr:=ctx.code;

  dis.Disassemble(dm64,ptr,din);

  ctx.ptr_next:=ctx.ptr_curr+(ptr-ctx.code);

  case din.OpCode.Opcode of
   OPX_Invalid..OPX_GroupP:
    begin
     //invalid
     if (p_print_jit_preload<>0) then
     begin
      writeln('invalid1:0x',HexStr(ctx.ptr_curr));
     end;

     _invalid:

     if (p_print_jit_preload<>0) then
     begin
      print_frame(stdout,ctx.ptr_curr);
      Writeln('original------------------------':32,' ','0x',HexStr(ctx.ptr_curr));
      print_disassemble(ctx.code,dis.CodeIdx);
      Writeln('original------------------------':32,' ','0x',HexStr(ctx.ptr_next));
     end;

     ctx.mark_chunk(fpInvalid);

     ctx.builder.int3;
     ctx.builder.int3;
     ctx.builder.ud2;

     link_curr:=ctx.builder.get_curr_label.before;
     link_next:=ctx.builder.get_curr_label.after;

     cb:=@op_invalid;
     ctx.trim:=True;
     goto _next; //trim
    end;
   else;
  end;

  if (din.Flags * [ifOnly32, ifOnly64, ifOnlyVex] <> []) or
     (din.ParseFlags * [preF3,preF2] <> []) or
     is_invalid(din) then
  begin
   if (p_print_jit_preload<>0) then
   begin
    writeln('invalid2:0x',HexStr(ctx.ptr_curr));
   end;
   goto _invalid;
  end;

  {
  if (qword(ctx.ptr_curr) and $FFFFF) = $427F5 then
  begin
   print_asm:=true;
   ctx.builder.int3;
  end;
  }

  if print_asm then
  begin
   Writeln('original------------------------':32,' ','0x',HexStr(ctx.ptr_curr));
   print_disassemble(ctx.code,dis.CodeIdx);
   Writeln('original------------------------':32,' ','0x',HexStr(ctx.ptr_next));
  end;

  ctx.dis:=dis;
  ctx.din:=din;

  if is_rep_prefix(ctx.din) then
  begin
   cb:=@op_invalid;
   if (ctx.din.OpCode.Prefix=OPPnone) then
   begin
    case ctx.din.OpCode.Opcode of
     OPins :cb:=jit_rep_cbs[repOPins ];
     OPouts:cb:=jit_rep_cbs[repOPouts];
     OPmovs:cb:=jit_rep_cbs[repOPmovs];
     OPlods:cb:=jit_rep_cbs[repOPlods];
     OPstos:cb:=jit_rep_cbs[repOPstos];
     OPcmps:cb:=jit_rep_cbs[repOPcmps];
     OPscas:cb:=jit_rep_cbs[repOPscas];
     OPret :cb:=jit_rep_cbs[repOPret ];
     else;
    end;
   end;
  end else
  begin
   cb:=jit_cbs[ctx.din.OpCode.Prefix,ctx.din.OpCode.Opcode,ctx.din.OpCode.Suffix];
  end;

  if (cb=@op_invalid) then
  begin
   case ctx.get_chunk_ptype of
    fpData,
    fpInvalid:
     begin
      writeln('skip:0x',HexStr(ctx.ptr_curr));
      goto _invalid;
     end
    else;
   end;
  end;

  if (cb=nil) then
  begin
   print_error_td('Unhandled jit opcode!');

   Writeln('original------------------------':32,' ','0x',HexStr(ctx.ptr_curr));
   print_disassemble(ctx.code,dis.CodeIdx);
   Writeln('original------------------------':32,' ','0x',HexStr(ctx.ptr_next));

   Writeln('Unhandled jit:',
           ctx.din.OpCode.Prefix,',',
           ctx.din.OpCode.Opcode,',',
           ctx.din.OpCode.Suffix,' ',
           ctx.din.Operand[1].Size,' ',
           ctx.din.Operand[2].Size);
   Writeln('opcode=$',HexStr(ctx.dis.opcode,8),' ',
           'MIndex=',ctx.dis.ModRM.Index,' ',
           'SimdOp=',ctx.dis.SimdOpcode,':',SCODES[ctx.dis.SimdOpcode],' ',
           'mm=',ctx.dis.mm,':',MCODES[ctx.dis.mm and 3]);

   Assert(false);
  end;

  link_curr:=ctx.builder.get_curr_label.after;
  node_curr:=link_curr._node;

  cb(ctx);

  link_next:=ctx.builder.get_curr_label.after;
  node_next:=link_next._node;

  {
  if (node_curr<>node_next) and
     (node_curr<>nil) then
  begin
   node:=TAILQ_NEXT(node_curr,@node_curr^.link);

   while (node<>nil) do
   begin

    if not test_disassemble(@node^.AData,node^.ASize) then
    begin
     print_asm:=True;
     Break;
    end;


    node:=TAILQ_NEXT(node,@node^.link);
   end;
  end;
  }

  //debug print
  if print_asm then
  if (node_curr<>node_next) and
     (node_curr<>nil) then
  begin
   node:=TAILQ_NEXT(node_curr,@node_curr^.link);

   Writeln('recompiled----------------------':32,' ','');
   while (node<>nil) do
   begin

    print_disassemble(@node^.AData,node^.ASize);


    node:=TAILQ_NEXT(node,@node^.link);
   end;
   Writeln('recompiled----------------------':32,' ','');
  end;

  {
  if (qword(ptr) and $FFFFF) = $1a710 then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;

  if (qword(ptr) and $FFFFF) = $1a6bd then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;
  }

  {
  if (qword(ptr) and $FFFFF) = $29e53 then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;

  if (qword(ptr) and $FFFFF) = $29e42 then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;

  if (qword(ptr) and $FFFFF) = $29e45 then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;

  if (qword(ptr) and $FFFFF) = $2b8a0 then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;
  }

  {
  if (qword(ctx.ptr_curr) and $FFFFF) = $2849d then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;
  }

  {
  if (qword(ctx.ptr_curr) and $FFFFF) = $2f59f then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;
  }

  {
  if (qword(ctx.ptr_curr) and $FFFFF) = $2f1f6 then
  begin
   //print_asm:=true;
   ctx.builder.int3;
  end;
  }

  _next:

  //debug
  if (cb<>@op_invalid) then
  begin
   op_debug_info(ctx);
  end;
  //debug

  //resolve forward links
  if (links.root<>nil) then
  begin
   links.Resolve(link_curr);
   links.root:=nil;
  end;

  //add new entry point
  if (entry_link<>nil) then
  begin
   ctx.add_entry_point(entry_link,link_curr);
   entry_link:=nil;
  end;

  //label exist in current blob
  if not ctx.trim then
  begin
   link_new:=ctx.get_link(ctx.ptr_next);

   if (link_new<>nil_link) then
   begin
    ctx.builder.jmp(link_new);
    //Writeln('jmp next:0x',HexStr(ptr));
    ctx.trim:=True;
   end;
  end;

  //entry exist in another blob
  if not ctx.trim then
  if exist_entry(ctx.ptr_next) then
  begin
   op_set_r14_imm(ctx,Int64(ctx.ptr_next));
   //
   op_jmp_dispatcher(ctx);
   //
   ctx.trim:=True;
  end;

  //add new label [link_curr..link_next]
  begin
   //update link_next
   link_next:=ctx.builder.get_curr_label.after;

   ctx.add_label(ctx.ptr_curr,
                 ctx.ptr_next,
                 link_curr,
                 link_next);
  end;

  if ctx.trim then
  begin
   ctx.trim:=False;

   //close chunk
   ctx.end_chunk(ctx.ptr_next);

   repeat

    if not ctx.fetch_forward_point(links,addr) then
    begin
     goto _build;
    end;

    link_new:=ctx.get_link(addr);
    if (link_new=nil_link) then
    begin
     //Writeln('not found:0x',HexStr(addr));
     Break;
    end else
    begin
     links.Resolve(link_new);
     links.root:=nil;
     //
     ctx.add_entry_point(addr,link_new);
    end;

   until false;

   entry_link:=addr;

   ctx.new_chunk(links.ptype,entry_link);

   ptr:=addr;
  end;

 end;

 _build:
 //build blob

 ctx.builder.int3;
 ctx.builder.int3;
 ctx.builder.int3;
 ctx.builder.ud2;

 build(ctx);
 ctx.Free;

end;

initialization
 init_cbs;


end.

