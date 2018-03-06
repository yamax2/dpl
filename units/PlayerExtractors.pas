unit PlayerExtractors;

{$mode objfpc}{$H+}

interface

uses
  PlayerThreads, Classes, SysUtils, Fgl, PlayerSubtitleExtractors;

type
  TPlayerFileInfo = packed record
    TrackFile: String;
    CreatedAt: TDateTime;
  end;

  TPlayerFileList = specialize TFPGMap<String, TPlayerFileInfo>;

  { TPlayerInfoExtractor }

  TPlayerInfoExtractor = class
  private
    FList: TPlayerFileList;
    FSessionID: String;
    FSubtileExtractorType: TSubtitleExtractorType;
    FTempDir: String;
    function GetCount: Integer;
    function GetFileInfo(const Index: Integer): TPlayerFileInfo;
    function GetFileInfoByName(const AFileName: String): TPlayerFileInfo;
    function GetFileName(const Index: Integer): String;
    procedure PrepareTempDir(const ATempDir: String);
  protected
    function GetSubtileExtractorType: TPlayerSubtitleExtractorClass; virtual;
  public
    constructor Create(AFileList: TStringList; const ATempDir: String);
    destructor Destroy; override;

    function LoadData: TThread;

    property Count: Integer read GetCount;
    property FileName[Index: Integer]: String read GetFileName; default;
    property FileInfo[Index: Integer]: TPlayerFileInfo read GetFileInfo;
    property FileInfoByName[AFileName: String]: TPlayerFileInfo read GetFileInfoByName;

    property SessionID: String read FSessionID;
    property SubtileExtractorType: TSubtitleExtractorType read FSubtileExtractorType write FSubtileExtractorType;
    property TempDir: String read FTempDir;
  end;

  { TPlayerExtractorManager }

  TPlayerExtractorManager = class(TPlayerThreadManager)
  private
    FExtractor: TPlayerInfoExtractor;
    FCount: Integer;
  protected
    function GetNextThread: TPlayerThread; override;
  public
    constructor Create(AExtractor: TPlayerInfoExtractor);

    property Extractor: TPlayerInfoExtractor read FExtractor;
  end;

  { TPlayerExtractorThread }

  TPlayerExtractorThread = class(TPlayerThread)
  private
    FIndex: Integer;
    function GetExtractor: TPlayerInfoExtractor;
    function GetManager: TPlayerExtractorManager;
  protected
    procedure Execute; override;
  public
    constructor Create(AManager: TPlayerExtractorManager; const AIndex: Integer);

    property Extractor: TPlayerInfoExtractor read GetExtractor;
    property Manager: TPlayerExtractorManager read GetManager;
  end;

implementation

{ TPlayerExtractorThread }

function TPlayerExtractorThread.GetManager: TPlayerExtractorManager;
begin
  Result:=inherited Manager as TPlayerExtractorManager;
end;

function TPlayerExtractorThread.GetExtractor: TPlayerInfoExtractor;
begin
  Result:=Manager.Extractor;
end;

procedure TPlayerExtractorThread.Execute;
var
  Service: TPlayerSubtitleExtractor;
begin
  Service:=Extractor.GetSubtileExtractorType.Create(
    Extractor[FIndex],
    Format('%ssubtitles_%d.data', [Extractor.TempDir, FIndex])
  );
  try
    Service.Extract;
  finally
    Service.Free;
  end;
end;

constructor TPlayerExtractorThread.Create(AManager: TPlayerExtractorManager;
  const AIndex: Integer);
begin
 inherited Create(AManager);
 FIndex:=AIndex;
end;

{ TPlayerExtractorManager }

function TPlayerExtractorManager.GetNextThread: TPlayerThread;
begin
  if not (FCount < Extractor.Count) then Result:=nil else
  begin
    Result:=TPlayerExtractorThread.Create(Self, FCount);
    Inc(FCount);
  end
end;

constructor TPlayerExtractorManager.Create(AExtractor: TPlayerInfoExtractor);
begin
  FExtractor:=AExtractor;
  FCount:=0;
  inherited Create;
end;

{ TPlayerInfoExtractor }

function TPlayerInfoExtractor.GetFileName(const Index: Integer): String;
begin
  Result:=FList.Keys[Index];
end;

procedure TPlayerInfoExtractor.PrepareTempDir(const ATempDir: String);
var
  Guid: TGUID;
begin
  if CreateGUID(Guid) <> 0 then raise Exception.Create('error');

  FSessionID:=LowerCase(GUIDToString(Guid));
  Delete(FSessionID, 1, 1);
  Delete(FSessionID, Length(FSessionID), 1);

  FTempDir:=IncludeTrailingPathDelimiter(ATempDir) + FSessionID;
  FTempDir:=IncludeTrailingPathDelimiter(FTempDir);
  ForceDirectories(FTempDir);
end;

function TPlayerInfoExtractor.GetSubtileExtractorType: TPlayerSubtitleExtractorClass;
begin
  case SubtileExtractorType of
    seFFmpeg: Result:=TPlayerSubtitleFfmpegExtractor;
    seMP4Box: Result:=TPlayerSubtitleMP4BoxExtractor;
  end;
end;

constructor TPlayerInfoExtractor.Create(AFileList: TStringList;
  const ATempDir: String);
var
  FileItemName: String;
  FileItemData: TPlayerFileInfo;
begin
  inherited Create;
  FSubtileExtractorType:=seFFmpeg;
  PrepareTempDir(ATempDir);

  FList:=TPlayerFileList.Create;
  for FileItemName in AFileList do
    if FileExists(FileItemName) then
    begin
      FileAge(FileItemName, FileItemData.CreatedAt);
      FileItemData.TrackFile:='';

      FList.Add(FileItemName, FileItemData);
    end;
end;

function TPlayerInfoExtractor.GetCount: Integer;
begin
  Result:=FList.Count;
end;

function TPlayerInfoExtractor.GetFileInfo(const Index: Integer): TPlayerFileInfo;
begin
  Result:=FList.Data[Index];
end;

function TPlayerInfoExtractor.GetFileInfoByName(const AFileName: String
  ): TPlayerFileInfo;
begin
  Result:=FList.KeyData[AFileName];
end;

destructor TPlayerInfoExtractor.Destroy;
begin
  FList.Free;
  inherited;
end;

function TPlayerInfoExtractor.LoadData: TThread;
begin
  Result:=TPlayerExtractorManager.Create(Self);
end;

end.

