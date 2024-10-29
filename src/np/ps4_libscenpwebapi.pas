unit ps4_libSceNpWebApi;

{$mode ObjFPC}{$H+}
{$CALLING SysV_ABI_CDecl}

interface

uses
 subr_dynlib,
 ps4_libSceNpCommon,
 ps4_libSceNpManager;

implementation

function ps4_sceNpWebApiInitialize(libHttpCtxId:Integer;
                                   poolSize:size_t):Integer;
begin
 Writeln('sceNpWebApiInitialize:',libHttpCtxId,':',poolSize);
 Result:=4;
end;

function ps4_sceNpWebApiTerminate(libCtxId:Integer):Integer;
begin
 Result:=0;
end;

function ps4_sceNpWebApiCreateContext(libCtxId:Integer;pOnlineId:pSceNpOnlineId):Integer;
begin
 Writeln('sceNpWebApiCreateContext:',libCtxId,':',pOnlineId^.data);
 Result:=0;
end;


function ps4_sceNpWebApiCreateContextA(libCtxId,userId:Integer):Integer;
begin
 Writeln('sceNpWebApiCreateContextA:',libCtxId,':',userId);
 //Result:=Integer($80552907);
 Result:=0;
end;

function ps4_sceNpWebApiCreateHandle(libCtxId:Integer):Integer;
begin
 Result:=5;
end;

function ps4_sceNpWebApiDeleteHandle(libCtxId,handleId:Integer):Integer;
begin
 Result:=0;
end;

const
 //SceNpWebApiHttpMethod
 SCE_NP_WEBAPI_HTTP_METHOD_GET   =0;
 SCE_NP_WEBAPI_HTTP_METHOD_POST  =1;
 SCE_NP_WEBAPI_HTTP_METHOD_PUT   =2;
 SCE_NP_WEBAPI_HTTP_METHOD_DELETE=3;

type
 pSceNpWebApiContentParameter=^SceNpWebApiContentParameter;
 SceNpWebApiContentParameter=packed record
  contentLength:QWORD;
  pContentType:Pchar;
  reserved:array[0..15] of Byte;
 end;

function ps4_sceNpWebApiCreateRequest(
	  titleUserCtxId:Integer;
	  pApiGroup:Pchar;
	  pPath:Pchar;
	  method:Integer; //SceNpWebApiHttpMethod
	  pContentParameter:pSceNpWebApiContentParameter;
	  pRequestId:pInt64):Integer;
begin
 pRequestId^:=6;
 Result:=0;
end;

function ps4_sceNpWebApiDeleteRequest(requestId:Int64):Integer;
begin
 Result:=0;
end;

function ps4_sceNpWebApiSendRequest(requestId:Int64;
                                    pData:Pointer;
                                    dataSize:size_t):Integer;
begin
 Result:=0;
end;

type
 pSceNpWebApiResponseInformationOption=^SceNpWebApiResponseInformationOption;
 SceNpWebApiResponseInformationOption=packed record
  httpStatus:Integer;      //out
  _align:Integer;
  pErrorObject:Pchar;      //in
  errorObjectSize:size_t;  //in
  responseDataSize:size_t; //out
 end;

function ps4_sceNpWebApiSendRequest2(requestId:Int64;
                                     pData:Pointer;
                                     dataSize:size_t;
                                     pRespInfoOption:pSceNpWebApiResponseInformationOption
                                     ):Integer;
begin
 if (pRespInfoOption<>nil) then
 begin
  pRespInfoOption^.httpStatus:=404;
  pRespInfoOption^.responseDataSize:=0;
 end;
 Result:=0;
end;

function ps4_sceNpWebApiGetHttpStatusCode(requestId:Int64;
                                          pStatusCode:PInteger):Integer;
begin
 if (pStatusCode<>nil) then
 begin
  pStatusCode^:=404;
 end;
 Result:=0;
end;

function ps4_sceNpWebApiGetHttpResponseHeaderValueLength(
                                          requestId:Int64;
                                          pFieldName:PChar;
                                          pValueLength:PQWORD):Integer;
begin
 Writeln('sceNpWebApiGetHttpResponseHeaderValueLength:',pFieldName);
 if (pValueLength<>nil) then
 begin
  pValueLength^:=0;
 end;
 Result:=0;
end;

function ps4_sceNpWebApiReadData(requestId:Int64;
                                 pData:Pointer;
                                 size:size_t):Integer;
begin
 Result:=0;
end;

const
 SCE_NP_WEBAPI_PUSH_EVENT_DATA_TYPE_LEN_MAX=64;
 SCE_NP_WEBAPI_EXTD_PUSH_EVENT_EXTD_DATA_KEY_LEN_MAX=32;

type
 pSceNpWebApiPushEventDataType=^SceNpWebApiPushEventDataType;
 SceNpWebApiPushEventDataType=packed record
  val:array[0..SCE_NP_WEBAPI_PUSH_EVENT_DATA_TYPE_LEN_MAX] of AnsiChar;
 end;

 pSceNpWebApiExtdPushEventExtdDataKey=^SceNpWebApiExtdPushEventExtdDataKey;
 SceNpWebApiExtdPushEventExtdDataKey=packed record
  val:array[0..SCE_NP_WEBAPI_EXTD_PUSH_EVENT_EXTD_DATA_KEY_LEN_MAX] of AnsiChar;
 end;

 pSceNpWebApiExtdPushEventFilterParameter=^SceNpWebApiExtdPushEventFilterParameter;
 SceNpWebApiExtdPushEventFilterParameter=packed record
  dataType:pSceNpWebApiExtdPushEventExtdDataKey;
  pExtdDataKey:Pointer;
  extdDataKeyNum:size_t;
 end;

 pSceNpWebApiExtdPushEventExtdData=^SceNpWebApiExtdPushEventExtdData;
 SceNpWebApiExtdPushEventExtdData=packed record
  extdDataKey:SceNpWebApiExtdPushEventExtdDataKey;
  pData      :PChar;
  dataLen    :QWORD;
 end;

 SceNpWebApiExtdPushEventCallbackA=procedure(
  userCtxId     :Integer;
  callbackId    :Integer;
  pNpServiceName:PChar;
  npServiceLabel:SceNpServiceLabel;
  pTo           :pSceNpPeerAddressA;
  pToOnlineId   :pSceNpOnlineId;
  pFrom         :pSceNpPeerAddressA;
  pFromOnlineId :SceNpOnlineId;
  pDataType     :pSceNpWebApiPushEventDataType;
  pData         :PChar;
  dataLen       :QWORD;
  pExtdData     :pSceNpWebApiExtdPushEventExtdData;
  extdDataNum   :QWORD;
  pUserArg      :Pointer
 );

function ps4_sceNpWebApiCreatePushEventFilter(libCtxId:Integer;
                                              pDataType:pSceNpWebApiPushEventDataType;
                                              dataTypeNum:size_t):Integer;
begin
 Result:=7;
end;

function ps4_sceNpWebApiCreateServicePushEventFilter(libCtxId:Integer;
                                                     handleId:Integer;
                                                     pNpServiceName:PChar;
                                                     npServiceLabel:DWORD; //SceNpServiceLabel
                                                     pDataType:pSceNpWebApiPushEventDataType;
                                                     dataTypeNum:size_t):Integer;
begin
 Result:=8;
end;

function ps4_sceNpWebApiCreateExtdPushEventFilter(libCtxId,handleId:Integer;
                                                  pNpServiceName:PChar;
                                                  npServiceLabel:DWORD;
                                                  pFilterParam:pSceNpWebApiExtdPushEventFilterParameter;
                                                  filterParamNum:size_t):Integer;
begin
 Result:=9;
end;


function ps4_sceNpWebApiRegisterPushEventCallback(userCtxId:Integer;
                                                  filterId:Integer;
                                                  cbFunc:Pointer; //SceNpWebApiPushEventCallback
                                                  pUserArg:Pointer):Integer;
begin
 Result:=1;
end;

function ps4_sceNpWebApiRegisterServicePushEventCallback(userCtxId:Integer;
                                                         filterId:Integer;
                                                         cbFunc:Pointer; //SceNpWebApiServicePushEventCallback
                                                         pUserArg:Pointer):Integer;
begin
 Result:=2;
end;

function ps4_sceNpWebApiRegisterExtdPushEventCallback(userCtxId,filterId:Integer;
                                                         cbFunc:Pointer; //SceNpWebApiServicePushEventCallback
                                                         pUserArg:Pointer):Integer;
begin
 Result:=3;
end;

function ps4_sceNpWebApiRegisterExtdPushEventCallbackA(userCtxId,filterId:Integer;
                                                       cbFunc:SceNpWebApiExtdPushEventCallbackA;
                                                       pUserArg:Pointer):Integer;
begin
 Result:=3;
end;

procedure ps4_sceNpWebApiCheckTimeout();
begin
 //
end;

function ps4_sceNpWebApiDeleteContext(userCtxId:Integer):Integer;
begin
 Result:=0;
end;

function Load_libSceNpWebApi(name:pchar):p_lib_info;
var
 lib:TLIBRARY;
begin
 Result:=obj_new_int('libSceNpWebApi');

 lib:=Result^.add_lib('libSceNpWebApi');
 lib.set_proc($1B70272CD7510631,@ps4_sceNpWebApiInitialize);
 lib.set_proc($6ACCF74ED22A185F,@ps4_sceNpWebApiTerminate);
 lib.set_proc($C7563BCA261293B7,@ps4_sceNpWebApiCreateContext);
 lib.set_proc($CE4E9CEB9C68C8ED,@ps4_sceNpWebApiCreateContextA);
 lib.set_proc($EFD33F26ABEF1A8D,@ps4_sceNpWebApiCreateHandle);
 lib.set_proc($E4C9FB4D8C29977D,@ps4_sceNpWebApiDeleteHandle);
 lib.set_proc($ADD82CE59D4CC85C,@ps4_sceNpWebApiCreateRequest);
 lib.set_proc($9E842095EBBE28B1,@ps4_sceNpWebApiDeleteRequest);
 lib.set_proc($9156CBE212F72BBC,@ps4_sceNpWebApiSendRequest);
 lib.set_proc($2A335E67FDBDCAC4,@ps4_sceNpWebApiSendRequest2);
 lib.set_proc($936D74A0A80FF346,@ps4_sceNpWebApiGetHttpStatusCode);
 lib.set_proc($EF8DD9CC4073955F,@ps4_sceNpWebApiGetHttpResponseHeaderValueLength);
 lib.set_proc($090B4F45217A0ECF,@ps4_sceNpWebApiReadData);
 lib.set_proc($CB94DAE490B34076,@ps4_sceNpWebApiCreatePushEventFilter);
 lib.set_proc($B08171EF7E3EC72B,@ps4_sceNpWebApiCreateServicePushEventFilter);
 lib.set_proc($3DF4930C280D3207,@ps4_sceNpWebApiRegisterPushEventCallback);
 lib.set_proc($909409134B8A9B9C,@ps4_sceNpWebApiRegisterServicePushEventCallback);
 lib.set_proc($33605407E0CD1061,@ps4_sceNpWebApiCreateExtdPushEventFilter);
 lib.set_proc($BEB334D80E46CB53,@ps4_sceNpWebApiRegisterExtdPushEventCallback);
 lib.set_proc($8E15CA1902787A02,@ps4_sceNpWebApiRegisterExtdPushEventCallbackA);
 lib.set_proc($81534DCB17FFD528,@ps4_sceNpWebApiCheckTimeout);
 lib.set_proc($5D48DDB124D36775,@ps4_sceNpWebApiDeleteContext);
end;

var
 stub:t_int_file;

initialization
 reg_int_file(stub,'libSceNpWebApi.prx',@Load_libSceNpWebApi);

end.

