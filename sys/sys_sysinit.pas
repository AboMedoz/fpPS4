unit sys_sysinit;

{$mode ObjFPC}{$H+}
{$CALLING SysV_ABI_CDecl}

interface

procedure sys_init;

implementation

uses
 time,
 kern_time,
 subr_sleepqueue,
 kern_thr,
 kern_thread,
 kern_sig,
 kern_timeout,
 kern_synch,
 kern_umtx,
 kern_namedobj,
 vmount,
 vfiledesc,
 vm_map,
 kern_mtxpool,
 vsys_generic,
 vfs_subr,
 vfs_lookup,
 vfs_init,
 kern_event,
 devfs,
 devfs_devs,
 devfs_vfsops,
 fdesc_vfsops,
 null_vfsops,
 ufs,
 kern_descrip,
 vfs_mountroot;

var
 daemon_thr:p_kthread;

//Daemon for a separate thread
procedure sys_daemon(arg:Pointer);
begin
 repeat
  vnlru_proc;
  pause('sys_daemon',hz);
 until false;
 kthread_exit();
end;

procedure sys_daemon_init;
var
 n:Integer;
begin
 n:=kthread_add(@sys_daemon,nil,@daemon_thr,'sys_daemon');
 Assert(n=0,'sys_daemon');
end;

procedure module_init;
begin
 vfs_register(@devfs_vfsconf);
 vfs_register(@fdescfs_vfsconf);
 vfs_register(@nullfs_vfsconf);
 vfs_register(@ufs_vfsconf);
 vfs_mountroot.vfs_mountroot();
 fildesc_drvinit;
end;

//Manual order of lazy initialization
procedure sys_init;
begin
 timeinit;
 init_sleepqueues;
 PROC_INIT;
 threadinit;
 siginit;
 umtxq_sysinit;
 kern_timeout_init;
 named_table_init;
 vmountinit;
 fd_table_init;
 vminit;
 mtx_pool_setup_dynamic;
 selectinit;
 vntblinit;
 nameiinit;
 knote_init;
 vfs_event_init;
 devfs_mtx_init;
 devfs_devs_init;
 module_init;
 sys_daemon_init;
end;

end.
