program dpl;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  cmem,
  {$ENDIF}
  Interfaces,
  Forms,

  // player
  CpuCount,
  PlayerThreads,
  PlayerExtractors,
  PlayerSubtitleExtractors,
  dmxPlayer,
  PlayerOptions,
  PlayerLogger,
  PlayerSessionStorage,

  // forms
  fmxOptions,
  fmxMain,
  fmxProgress;

{$R *.res}

begin
  opts.TempDir:='./tmp';
  opts.LogOptions:=[ploExtractor, ploDB];

  Application.Title:='Dashcam Player Light';
  RequireDerivedFormResource:=True;
  Application.Initialize;
  Application.CreateForm(TfmOptions, fmOptions);
  Application.Run;
end.

