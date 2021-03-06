unit PlayerExporters;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  SqlDB,
  fpjson,
  PlayerThreads;

type

  { TPlayerExporter }

  TPlayerProcessEvent = procedure(Sender: TObject;
    const AProcessedCount: Integer) of object;

  TPlayerExporter = class
  private
    FCount: Integer;
    FExported, FFailed: Boolean;
    FOnFinish: TNotifyEvent;
    FOnProcess: TPlayerProcessEvent;
    FSessionID, FDir: String;
    FProcessedCount: Integer;
    procedure CalcTripsForSession;
  protected
    function CreateQuery(const SQLResource: String = ''): TSQLQuery;
    procedure DoFinish; virtual;
    procedure DoProcess; virtual;
  public
    constructor Create(ASessionID: String);
    destructor Destroy; override;
    function ExportData: TPlayerThreadManager;

    property Count: Integer read FCount;
    property Exported: Boolean read FExported;
    property SessionID: String read FSessionID;

    property OnFinish: TNotifyEvent read FOnFinish write FOnFinish;
    property OnProcess: TPlayerProcessEvent read FOnProcess write FOnProcess;
  end;

  { TPlayerExporterManager }

  TPlayerExporterManager = class(TPlayerThreadManager)
  private
    FExporter: TPlayerExporter;
    FQuery: TSQLQuery;
    FData: TJSONArray;
    procedure AddTrip;
    procedure GenerateHtml;
  protected
    function GetNextThread: TPlayerThread; override;
    procedure Execute; override;
  public
    constructor Create(AExporter: TPlayerExporter);
    destructor Destroy; override;
    procedure Interrupt(const Force: Boolean = False); override;
    procedure SaveJson(const FileName: String; AJson: TJSONData);

    property Exporter: TPlayerExporter read FExporter;
  end;

  { TPlayerExporterThread }

  TPlayerExporterThread = class(TPlayerThread)
  private
    FTripID: Integer;
    FQuery: TSQLQuery;
    FTracks, FPoints: TJSONArray;
    function GetManager: TPlayerExporterManager;
    procedure ExportPoints;
    procedure ExportTracks;
  protected
    procedure Execute; override;
  public
    constructor Create(AManager: TPlayerThreadManager;
      const ATripID: Integer);
    destructor Destroy; override;

    property Manager: TPlayerExporterManager read GetManager;
    property TripID: Integer read FTripID;
  end;

implementation

uses
  Math, DB, dmxPlayer, PlayerLogger, PlayerOptions, FileUtil, PlayerSessionStorage;

{ TPlayerExporterThread }

function TPlayerExporterThread.GetManager: TPlayerExporterManager;
begin
  Result:=inherited Manager as TPlayerExporterManager;
end;

procedure TPlayerExporterThread.ExportPoints;
var
  Field: TField;
  Point: TJSONObject;
begin
  LoadTextFromResource(FQuery.SQL, 'GET_POINTS');
  FQuery.Open;

  while not FQuery.EOF do
  begin
    if Terminated then Break;

    Point:=TJSONObject.Create;
    for Field in FQuery.Fields do
      Point.Strings[Field.FieldName]:=Field.AsString;

    FPoints.Add(Point);
    FQuery.Next;
  end;

  FQuery.Close;
end;

procedure TPlayerExporterThread.ExportTracks;
var
  Track: TJSONObject;
begin
  FQuery.Open;

  while not FQuery.EOF do
  begin
    if Terminated then Break;

    Track:=TJSONObject.Create;
    Track.Strings['filename']:=FQuery.FieldByName('filename').AsString;
    Track.Integers['rn']:=FQuery.FieldByName('trip_rn').AsInteger;
    Track.Integers['start_id']:=FQuery.FieldByName('start_id').AsInteger;
    Track.Integers['end_id']:=FQuery.FieldByName('end_id').AsInteger;

    FTracks.Add(Track);
    FQuery.Next;
  end;

  FQuery.Close;
end;

procedure TPlayerExporterThread.Execute;
begin
  try
    ExportTracks;
    ExportPoints;

    if not Terminated then
    begin
      Manager.SaveJson(Format('%stracks_%d.json', [Manager.Exporter.FDir, FTripID]), FTracks);
      Manager.SaveJson(Format('%spoints_%d.json', [Manager.Exporter.FDir, FTripID]), FPoints);

      Synchronize(@Manager.Exporter.DoProcess);
    end;
  except
    on E: Exception do
    begin
      logger.Log('error on exporter trip %d, session %s, text: %s',
        [FTripID, Manager.Exporter.FSessionID, E.Message]);

      Manager.Exporter.FFailed:=True;
      Manager.Interrupt(True);
    end;
  end;
end;

constructor TPlayerExporterThread.Create(AManager: TPlayerThreadManager;
  const ATripID: Integer);
begin
  inherited Create(AManager);
  FTripID:=ATripID;

  FTracks:=TJSONArray.Create;
  FPoints:=TJSONArray.Create;

  FQuery:=Manager.Exporter.CreateQuery('GET_TRIPS_TRACKS');
  FQuery.ParamByName('trip_id').AsInteger:=FTripID;
end;

destructor TPlayerExporterThread.Destroy;
begin
  FQuery.Free;
  FTracks.Free;
  FPoints.Free;
  inherited;
end;

{ TPlayerExporterManager }

procedure TPlayerExporterManager.AddTrip;
var
  obj: TJSONObject;
  Duration: Integer;
begin
  obj:=TJSONObject.Create;

  Duration:=FQuery.FieldByName('duration').AsInteger;
  obj.Integers['id']:=FQuery.FieldByName('id').AsInteger;
  obj.Strings['started_at']:=FQuery.FieldByName('started_at').AsString;
  obj.Strings['duration']:=Format('%d:%d', [Duration div 3600, (Duration mod 3600) div 60]);
  obj.Strings['distance']:=FloatToStr(RoundTo(FQuery.FieldByName('distance').AsFloat / 1000, -2));
  obj.Strings['avg_speed']:=FloatToStr(RoundTo(FQuery.FieldByName('avg_speed').AsFloat, -2));
  obj.Strings['size']:=FloatToStr(RoundTo(FQuery.FieldByName('size_mb').AsFloat / 1024, -2));

  FData.Add(obj);
  (FQuery.FieldByName('gpx') as TBlobField).SaveToFile(
    Format('%s%d.gpx', [Exporter.FDir, FQuery.FieldByName('id').AsInteger])
  );
end;

procedure TPlayerExporterManager.GenerateHtml;
var
  Html: TStringList;
begin
  Html:=TStringList.Create;
  try
    Html.LoadFromFile('html/dist/index.html');

    Html.Text:=Html.Text.Replace('bundle.js', '../../../html/dist/bundle.js')
                        .Replace('{{trips}}', FData.AsJson)
                        .Replace('{{tracks}}', '');

    Html.SaveToFile(FExporter.FDir + 'index.html');
  finally
    Html.Free;
  end;
end;

function TPlayerExporterManager.GetNextThread: TPlayerThread;
var
  id: Integer;
begin
  if FQuery.EOF then Result:=nil else
  begin
    id:=FQuery.FieldByName('id').AsInteger;
    AddTrip;

    logger.Log('starting new exporter thread: trip %d for session %s',
      [id, Exporter.FSessionID]);
    Result:=TPlayerExporterThread.Create(Self, id);

    SaveJson(Format('%strips.json', [Exporter.FDir]), FData);
    FQuery.Next;
  end
end;

procedure TPlayerExporterManager.Execute;
begin
  try
    try
      inherited;

      if FQuery.EOF then
      begin
        Exporter.FExported:=True;
        GenerateHtml;
      end;
    except
      on E: Exception do
      begin
        logger.Log('error on exporting session %s, text: %s',
          [Exporter.FSessionID, E.Message]);

        FExporter.FFailed:=True;
        Interrupt(True);
      end;
    end;
  finally
    Synchronize(@FExporter.DoFinish);
  end;
end;

constructor TPlayerExporterManager.Create(AExporter: TPlayerExporter);
begin
  FExporter:=AExporter;

  FQuery:=Exporter.CreateQuery('GET_TRIPS_LIST');
  FQuery.ParamByName('session_id').AsString:=Exporter.SessionID;
  FQuery.Open;

  FData:=TJSONArray.Create;

  inherited Create;
end;

destructor TPlayerExporterManager.Destroy;
begin
  FQuery.Close;
  FQuery.Free;
  FData.Free;

  inherited;
end;

procedure TPlayerExporterManager.Interrupt(const Force: Boolean);
var
  List: TList;
  Index: Integer;

  CurThread: TPlayerExporterThread;
begin
  inherited;

  if not Force then Exit;
  List:=ThreadList.LockList;
  try
    for Index:=0 to List.Count - 1 do
    begin
      CurThread:=TPlayerExporterThread(List[Index]);
      CurThread.Terminate;
    end;
  finally
    ThreadList.UnlockList;
  end;
end;

procedure TPlayerExporterManager.SaveJson(const FileName: String;
  AJson: TJSONData);
var
  List: TStringList;
begin
  List:=TStringList.Create;
  try
    List.Text:=AJson.AsJSON;
    List.SaveToFile(FileName);
  finally
    List.Free;
  end;
end;

{ TPlayerExporter }

procedure TPlayerExporter.CalcTripsForSession;
var
  Query: TSQLQuery;
begin
  Query:=CreateQuery('GET_TRIPS_COUNT');
  Query.ParamByName('session_id').AsString:=FSessionID;

  Query.Open;
  try
    FCount:=0;
    if not Query.IsEmpty then FCount:=Query.FieldByName('cc').AsInteger;
  finally
    Query.Close;
  end;
end;

function TPlayerExporter.CreateQuery(const SQLResource: String): TSQLQuery;
begin
  Result:=TSQLQuery.Create(dmPlayer);
  Result.DataBase:=dmPlayer.Connection;
  Result.Transaction:=dmPlayer.Transaction;

  if SQLResource <> '' then
    LoadTextFromResource(Result.SQL, SQLResource);
end;

procedure TPlayerExporter.DoFinish;
begin
  if @FOnFinish <> nil then
    FOnFinish(Self);
end;

procedure TPlayerExporter.DoProcess;
begin
  Inc(FProcessedCount);
  if @FOnProcess <> nil then
    FOnProcess(Self, FProcessedCount);
end;

constructor TPlayerExporter.Create(ASessionID: String);
begin
  inherited Create;
  FExported:=False;
  FSessionID:=ASessionID;

  FDir:=IncludeTrailingPathDelimiter(opts.TempDir);
  FDir:=IncludeTrailingPathDelimiter(FDir + 'html');
  FDir:=IncludeTrailingPathDelimiter(FDir + ASessionID);

  DeleteDirectory(FDir, False);
  logger.log('recreating dir: %s', [FDir]);
  ForceDirectories(FDir);

  CalcTripsForSession;
end;

destructor TPlayerExporter.Destroy;
begin
  logger.Log('export finished: %s', [FSessionID]);

  inherited;
end;

function TPlayerExporter.ExportData: TPlayerThreadManager;
begin
  logger.Log('exporting session: %s', [FSessionID]);

  FProcessedCount:=0;
  FFailed:=False;
  if FCount = 0 then Exit;

  Result:=TPlayerExporterManager.Create(Self);
  Result.Start;
end;

end.

