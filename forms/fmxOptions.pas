unit fmxOptions;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, ActnList, Buttons, Menus,
  PlayerExtractors, PlayerExporters;

type

  { TfmOptions }

  TfmOptions = class(TForm)
    acAdd: TAction;
    acAddDir: TAction;
    acOpen: TAction;
    acExit: TAction;
    acRemove: TAction;
    acClear: TAction;
    ActionList: TActionList;
    btAddDir: TBitBtn;
    btRemoveFiles: TBitBtn;
    btOpen: TBitBtn;
    btExit: TBitBtn;
    btAddFiles: TBitBtn;
    btRemoveFiles1: TBitBtn;
    ImageList: TImageList;
    lbGithub: TLabel;
    lbFiles: TLabel;
    ListBox: TListBox;
    miSeparator: TMenuItem;
    miClear: TMenuItem;
    miRemove: TMenuItem;
    OpenDialog: TOpenDialog;
    PageControl: TPageControl;
    pActions: TPanel;
    pButtons: TPanel;
    DirectoryDialog: TSelectDirectoryDialog;
    pmMenu: TPopupMenu;
    tbOptions: TTabSheet;
    tbFiles: TTabSheet;
    procedure acAddDirExecute(Sender: TObject);
    procedure acAddExecute(Sender: TObject);
    procedure acClearExecute(Sender: TObject);
    procedure acClearUpdate(Sender: TObject);
    procedure acExitExecute(Sender: TObject);
    procedure acOpenExecute(Sender: TObject);
    procedure acOpenUpdate(Sender: TObject);
    procedure acRemoveExecute(Sender: TObject);
    procedure acRemoveUpdate(Sender: TObject);
    procedure lbGithubClick(Sender: TObject);
  private
    FSessionID: String;
    FExtractor: TPlayerInfoExtractor;
    FExporter: TPlayerExporter;
    procedure AddFileToList(const FileName: String);
    procedure OnException(Sender: TObject; E: Exception);

    function ExtractData: Boolean;
    function ExportData: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  fmOptions: TfmOptions;

implementation
uses
  lclintf, fmxProgress, fmxMain, PlayerLogger;

{$R *.lfm}

{ TfmOptions }

procedure TfmOptions.acExitExecute(Sender: TObject);
begin
  Close;
end;

procedure TfmOptions.acOpenExecute(Sender: TObject);
var
  SessionID: String;
begin
  if not ExtractData or not ExportData then
  begin
    if FExtractor.Failed then ShowMessage('error on data extraction');
    Exit;
  end;

  Hide;
  Application.CreateForm(TfmMain, fmMain);
  fmMain.SessionID:=SessionID;
  fmMain.Show;
end;

procedure TfmOptions.acAddExecute(Sender: TObject);
var
  FileName: String;
begin
  if not OpenDialog.Execute then Exit;

  for FileName in OpenDialog.Files do
    AddFileToList(FileName);
end;

procedure TfmOptions.acClearExecute(Sender: TObject);
begin
 ListBox.Clear;
end;

procedure TfmOptions.acClearUpdate(Sender: TObject);
begin
  acClear.Enabled:=ListBox.Count > 0;
end;

procedure TfmOptions.acAddDirExecute(Sender: TObject);
var
  Dir, FileName: String;
  Files: TStringList;
begin
  if not DirectoryDialog.Execute then Exit;

  Files:=TStringList.Create;
  try
    for Dir in DirectoryDialog.Files do
    begin
      Files.Clear;
      FindAllFiles(Files, Dir, '*.mp4;*.mov;*.MP4;*.MOV', True);

      for FileName in Files do
        AddFileToList(FileName);
    end;
  finally
    Files.Free;
  end;
end;

procedure TfmOptions.acOpenUpdate(Sender: TObject);
begin
  acOpen.Enabled:=ListBox.Items.Count > 0;
end;

procedure TfmOptions.acRemoveExecute(Sender: TObject);
begin
  ListBox.DeleteSelected;
end;

procedure TfmOptions.acRemoveUpdate(Sender: TObject);
begin
  acRemove.Enabled:=ListBox.SelCount > 0;
end;

procedure TfmOptions.lbGithubClick(Sender: TObject);
begin
  OpenURL(lbGithub.Caption);
end;

procedure TfmOptions.AddFileToList(const FileName: String);
begin
  if (ListBox.Items.IndexOf(FileName) < 0) and FileExists(FileName) then
    ListBox.Items.Add(FileName);
end;

procedure TfmOptions.OnException(Sender: TObject; E: Exception);
begin
  logger.Log('Exception: %s', [E.Message]);
end;

function TfmOptions.ExtractData: Boolean;
begin
  Result:=False;

  FExtractor:=TPlayerInfoExtractor.Create(ListBox.Items);
  try
    Result:=FExtractor.Loaded;
    FSessionID:=FExtractor.SessionID;
    if Result then Exit;

    with TfmProgress.Create(Self) do
    try
      ProgressBar.Position:=0;
      TrackCount:=FExtractor.Count;
      FExtractor.OnFinish:=@ProcessFinished;
      FExtractor.OnProcess:=@Processed;

      Manager:=FExtractor.LoadData;
      try
        ShowModal;
        Manager.WaitFor;
      finally
        Manager.Free;
      end;
    finally
      Free;
    end;

    Result:=FExtractor.Loaded;
  finally
    FExtractor.Free;
  end;
end;

function TfmOptions.ExportData: Boolean;
begin
  Result:=False;

  FExporter:=TPlayerExporter.Create(FSessionID);
  try
    with TfmProgress.Create(Self) do
    try
      ProgressBar.Position:=0;
      TrackCount:=FExporter.Count;
      FExporter.OnFinish:=@ProcessFinished;
      FExporter.OnProcess:=@Processed;

      Manager:=FExporter.ExportData;
      if Manager <> nil then
        try
          ShowModal;
          Manager.WaitFor;
        finally
          Manager.Free;
        end;
    finally
      Free;
    end;

    Result:=FExporter.Exported;
  finally
    FExporter.Free;
  end;
end;

constructor TfmOptions.Create(AOwner: TComponent);
begin
  inherited;
  FSessionID:='';
  Application.OnException:=@OnException;
  lbGithub.Font.Color:=clBlue;
  Caption:=Application.Title;
  PageControl.PageIndex:=0;
  ListBox.Items.Clear;
end;

end.

