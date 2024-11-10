unit ps4_libSceNpWebApi2;

{$mode ObjFPC}{$H+}
{$CALLING SysV_ABI_CDecl}

interface

uses
 subr_dynlib,
 ps4_libSceNpCommon,
 ps4_libSceNpManager;

implementation

const
 SCE_NP_WEBAPI_EXTD_PUSH_EVENT_EXTD_DATA_KEY_LEN_MAX=32;

type
 pSceNpWebApi2ContentParameter=^SceNpWebApi2ContentParameter;
 SceNpWebApi2ContentParameter=packed record
  contentLength:QWORD;
  pContentType :Pchar;
  reserved     :array[0..15] of Byte;
 end;

 pSceNpWebApi2ResponseInformationOption=^SceNpWebApi2ResponseInformationOption;
 SceNpWebApi2ResponseInformationOption=packed record
  httpStatus      :Integer;
  _align          :Integer;
  pErrorObject    :Pchar;
  errorObjectSize :QWORD;
  responseDataSize:QWORD;
 end;

 pSceNpWebApi2ExtdPushEventExtdDataKey=^SceNpWebApi2ExtdPushEventExtdDataKey;
 SceNpWebApi2ExtdPushEventExtdDataKey=packed record
  val:array[0..SCE_NP_WEBAPI_EXTD_PUSH_EVENT_EXTD_DATA_KEY_LEN_MAX] of AnsiChar;
 end;

 pSceNpWebApi2PushEventFilterParameter=^SceNpWebApi2PushEventFilterParameter;
 SceNpWebApi2PushEventFilterParameter=packed record
  dataType      :SceNpWebApi2ExtdPushEventExtdDataKey;
  pExtdDataKey  :Pointer;
  extdDataKeyNum:QWORD;
 end;

const
 SCE_NP_WEBAPI2_PUSH_EVENT_UUID_LENGTH=36;

type
 pSceNpWebApi2PushEventPushContextId=^SceNpWebApi2PushEventPushContextId;
 SceNpWebApi2PushEventPushContextId=packed record
  uuid:array[0..SCE_NP_WEBAPI2_PUSH_EVENT_UUID_LENGTH] of Char;
 end;

function ps4_sceNpWebApi2Initialize(libHttp2CtxId:Integer;
                                    poolSize:size_t):Integer;
begin
 Writeln('sceNpWebApi2Initialize:',libHttp2CtxId,':',poolSize);
 Result:=4;
end;

function ps4_sceNpWebApi2CreateRequest(titleUserCtxId:Integer;
	                               pApiGroup:Pchar;
	                               pPath:Pchar;
	                               method:PChar; //SceNpWebApi2HttpMethod
	                               pContentParameter:pSceNpWebApi2ContentParameter;
	                               pRequestId:pInt64):Integer;
begin
 Result:=0;
end;

function ps4_sceNpWebApi2SendRequest(requestId:Int64;
                                     pData:Pointer;
                                     dataSize:QWORD;
                                     pRespInfoOption:pSceNpWebApi2ResponseInformationOption):Integer;
begin
 Result:=0;
end;

function ps4_sceNpWebApi2CreateUserContext(libCtxId,m_userId:Integer):Integer;
begin
 Writeln('sceNpWebApi2CreateUserContext:',libCtxId,':',m_userId);
 Result:=5;
end;

function ps4_sceNpWebApi2PushEventDeletePushContext(userCtxId:Integer;
                                                    pPushCtxId:pSceNpWebApi2PushEventPushContextId):Integer;
begin
 Result:=0;
end;

function ps4_sceNpWebApi2AddHttpRequestHeader(requestId:Integer;
                                              const pFieldName:PChar;
                                              const pValue:PChar):Integer;
begin
 Result:=0;
end;

function ps4_sceNpWebApi2PushEventCreateHandle(libCtxId:Integer):Integer;
begin
 Result:=0;
end;

function ps4_sceNpWebApi2PushEventCreateFilter(libCtxId:Integer;
                                               handleId:Integer;
                                               pNpServiceName:PChar;
                                               npServiceLabel:DWORD;
                                               pFilterParam:pSceNpWebApi2PushEventFilterParameter;
                                               filterParamNum:QWORD):Integer;
begin
 Result:=0;
end;

function ps4_sceNpWebApi2PushEventRegisterCallback(libCtxId:Integer;
                                                   cbFunc:Pointer;
                                                   pUserArg:Pointer):Integer;
begin
 Result:=0;
end;

function Load_libSceNpWebApi2(name:pchar):p_lib_info;
var
 lib:TLIBRARY;
begin
 Result:=obj_new_int('libSceNpWebApi2');

 lib:=Result^.add_lib('libSceNpWebApi2');
 lib.set_proc($FA8F7CD7A61086A4,@ps4_sceNpWebApi2Initialize);
 lib.set_proc($DC423F39227AE577,@ps4_sceNpWebApi2CreateRequest);
 lib.set_proc($95038217CE25BF3C,@ps4_sceNpWebApi2SendRequest);
 lib.set_proc($B24E786E2E85B583,@ps4_sceNpWebApi2CreateUserContext);
 lib.set_proc($41A7F179933758AE,@ps4_sceNpWebApi2PushEventDeletePushContext);
 lib.set_proc($7A038EBEB9C5EA62,@ps4_sceNpWebApi2AddHttpRequestHeader);
 lib.set_proc($595D46C0CDF63606,@ps4_sceNpWebApi2PushEventCreateHandle);
 lib.set_proc($32C685851FA53C4E,@ps4_sceNpWebApi2PushEventCreateFilter);
 lib.set_proc($7D8DD0A9E36417C9,@ps4_sceNpWebApi2PushEventRegisterCallback);
end;

var
 stub:t_int_file;

initialization
 RegisteredInternalFile(stub,'libSceNpWebApi2.prx',@Load_libSceNpWebApi2);

end.

