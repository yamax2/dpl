unit PlayerThreads;

{$mode objfpc}{$H+}

interface

uses
{$ifdef unix}
  cthreads,
  cmem,
{$endif}
  Classes, SysUtils;

type
  TPlayerThread = class;

  { TPlayerThreadManager }

  TPlayerThreadManager = class(TThread)
  private
    FEvent: pRTLEvent;
    FList: TThreadList;
    FForceTerminated: Boolean;
    class var FManagers: TThreadList;
  protected
    procedure Execute; override;
    function GetNextThread: TPlayerThread; virtual;
    function GetMaxThreadCount: Integer; virtual;
    procedure Process(AFinishedThread: TPlayerThread = nil);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Interrupt(const Force: Boolean = False);

    class constructor ClassCreate;
    class destructor ClassDestroy;
    class procedure WaitForThreadList(AList: TThreadList; const AForceTerminate: Boolean = False);

    property MaxThreadCount: Integer read GetMaxThreadCount;
  end;

  { TPlayerThread }

  TPlayerThread = class(TThread)
  private
    FManager: TPlayerThreadManager;
  public
    constructor Create(AManager: TPlayerThreadManager);
    destructor Destroy; override;

    property Manager: TPlayerThreadManager read FManager;
  end;


implementation

{ TPlayerThread }

constructor TPlayerThread.Create(AManager: TPlayerThreadManager);
begin
  FManager:=AManager;
  inherited Create(True);
  FreeOnTerminate:=True;
end;

destructor TPlayerThread.Destroy;
begin
  FManager.Process(Self);
  inherited;
end;

{ TPlayerThreadManager }

procedure TPlayerThreadManager.Execute;
begin
 Process;
 RtlEventWaitFor(FEvent);
 Terminate;
 WaitForThreadList(FList, FForceTerminated);
end;

function TPlayerThreadManager.GetNextThread: TPlayerThread;
begin
  Result:=nil;
end;

function TPlayerThreadManager.GetMaxThreadCount: Integer;
begin
 Result:=8;
end;

procedure TPlayerThreadManager.Process(AFinishedThread: TPlayerThread);
var
  List: TList;
  NextThread: TPlayerThread;
begin
 List:=FList.LockList;
 try
   if AFinishedThread <> nil then List.Remove(AFinishedThread);
   if not (List.Count < GetMaxThreadCount) or Terminated then Exit;

   repeat
     NextThread:=GetNextThread;
     if NextThread <> nil then
     begin
       List.Add(NextThread);
       NextThread.Start;
     end;
   until (NextThread = nil) or Terminated or not (List.Count < GetMaxThreadCount);

   if NextThread = nil then Interrupt;
 finally
   FList.UnlockList;
 end;
end;

constructor TPlayerThreadManager.Create;
var
  List: TList;
begin
  FList:=TThreadList.Create;
  FEvent:=RTLEventCreate;

  List:=FManagers.LockList;
  try
    List.Add(Self);
  finally
    FManagers.UnlockList;
  end;

  FForceTerminated:=False;
  inherited Create(False);
  FreeOnTerminate:=True;
end;

destructor TPlayerThreadManager.Destroy;
var
  List: TList;
begin
  FList.Free;
  RTLeventdestroy(FEvent);

  List:=FManagers.LockList;
  try
    List.Remove(Self);
  finally
    FManagers.UnlockList;
  end;

  inherited;
end;

procedure TPlayerThreadManager.Interrupt(const Force: Boolean);
begin
  FForceTerminated:=Force;
  Terminate;
  RtlEventSetEvent(FEvent);
end;

class constructor TPlayerThreadManager.ClassCreate;
begin
  FManagers:=TThreadList.Create;
end;

class destructor TPlayerThreadManager.ClassDestroy;
begin
  WaitForThreadList(FManagers);
  FManagers.Free;
end;

class procedure TPlayerThreadManager.WaitForThreadList(AList: TThreadList;
  const AForceTerminate: Boolean);
var
  List: TList;
  Handles: array of TThreadID;
  Index: Integer;
begin
 List:=AList.LockList;
 try
   SetLength(Handles, List.Count);
   for Index:=0 to List.Count - 1 do
   begin
     Handles[Index]:=TThread(List[Index]).Handle;
     if AForceTerminate then
       TThread(List[Index]).Terminate;
   end;
 finally
   AList.UnlockList;
 end;

 for Index:=0 to Length(Handles) - 1 do
   WaitForThreadTerminate(Handles[Index], 0);
end;

end.

