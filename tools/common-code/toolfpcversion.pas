{
  Copyright 2019-2021 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Detecting FPC and Lazarus version and some capabilities. }
unit ToolFpcVersion;

interface

type
  TToolVersion = class
  protected
    { Get Major,Minor,Release from S.
      Raise exception if it doesn't start with necessary numbers. }
    procedure ParseVersion(const S: String);
  public
    Major, Minor, Release: Integer;
    ReleaseRemark: String;
    function AtLeast(const AMajor, AMinor, ARelease: Integer): boolean;
    function ToString: String; override;
  end;

  TFpcVersion = class(TToolVersion)
  private
    CachedFpcPath: String;
  public
    IsCodeTyphon: Boolean;
    { Get FPC version by running "fpc -iV". }
    constructor Create;
  end;

  TLazarusVersion = class(TToolVersion)
  private
    CachedLazarusPath: String;
  public
    { Get Lazarus version by running "lazbuild --version". }
    constructor Create;
  end;

{ FPC version singleton, automatically created and destroyed in this unit.
  Using this raises exception EExecutableNotFound if FPC cannot be found,
  or any other Exception in case FPC cannot be executed
  or version cannot be parsed.
  Value of this may change when FpcCustomPath changes. }
function FpcVersion: TFpcVersion;

{ Lazarus version singleton, automatically created and destroyed in this unit.
  Using this raises exception EExecutableNotFound if lazbuild cannot be found,
  or any other Exception in case lazbuild cannot be executed
  or version cannot be parsed.
  Value of this may change when LazarusCustomPath changes. }
function LazarusVersion: TLazarusVersion;

implementation

uses SysUtils, Classes,
  CastleFilesUtils, CastleLog, CastleStringUtils,
  ToolCommonUtils, ToolCompilerInfo;

{ TToolVersion --------------------------------------------------------------- }

function TToolVersion.AtLeast(const AMajor, AMinor, ARelease: Integer): boolean;
begin
  Result :=
      (AMajor < Major) or
    ( (AMajor = Major) and (AMinor < Minor) ) or
    ( (AMajor = Major) and (AMinor = Minor) and (ARelease <= Release) );
end;

function TToolVersion.ToString: String;
begin
  Result := Format('%d.%d.%d', [Major, Minor, Release]) + ReleaseRemark;
end;

procedure TToolVersion.ParseVersion(const S: String);
var
  Token: String;
  SeekPos: Integer;
  I, ErrorCode, TempRelease: Integer;
begin
  SeekPos := 1;

  Token := NextToken(S, SeekPos, ['.', '-']);
  if Token = '' then
    raise Exception.CreateFmt('Failed to query version: no major number in "%s"', [S]);
  Major := StrToInt(Token);

  Token := NextToken(S, SeekPos, ['.', '-']);
  if Token = '' then
    raise Exception.CreateFmt('Failed to query version: no minor number in "%s"', [S]);
  Minor := StrToInt(Token);

  Token := NextToken(S, SeekPos, ['.', '-']);
  if Token = '' then
  begin
    WritelnWarning('Failed to query version: no release number in "%s", assuming 0', [S]);
    Release := 0;
  end else
  begin
    ReleaseRemark := '';
    Val(Token, Release, ErrorCode);
    if ErrorCode <> 0 then // this is a case of versions like 2.2.0RC1 which contain additional ReleaseRemark after the integer digit
    begin
      I := 0;
      repeat
        Inc(I);
        Val(Copy(Token, 1, I), TempRelease, ErrorCode);
        if ErrorCode = 0 then
          Release := TempRelease; // workaround the fact that if ErrorCode <> 0 the value of TempRelease is undefined, here we use the latest successful value only in case there were no conversion errors
      until ErrorCode <> 0; //or I >= Length(Token) - no need, as we guarantee by the condition above that ErrorCode <> 0 for full Token
      if I = 1 then // this means that the first character of Token is not a digit
        raise Exception.Create('Unable to parse "' + Token + '" as a Release version')
      else
        ReleaseRemark := Copy(Token, I, Length(Token));
    end;
  end;
end;

{ TFpcVersion ---------------------------------------------------------------- }

constructor TFpcVersion.Create;
var
  ToolOutput, ToolExe: string;
  ToolExitStatus: Integer;
begin
  inherited;

  ToolExe := FindExeFpcCompiler;
  MyRunCommandIndir(GetCurrentDir, ToolExe, ['-iV'], ToolOutput, ToolExitStatus,
    // use rcNoConsole to not blink with a console when CGE editor starts
    nil, nil, [rcNoConsole]);
  if ToolExitStatus <> 0 then
    raise Exception.Create('Failed to query FPC version');

  IsCodeTyphon := Pos('codetyphon', LowerCase(ToolExe)) > 0;

  { parse ToolOutput into Major,Minor,Release }
  ParseVersion(Trim(ToolOutput));

  WritelnVerbose('FPC version: ' + ToString);
end;

var
  FpcVersionCached: TFpcVersion;

function FpcVersion: TFpcVersion;
begin
  { Invalidate cache if FpcCustomPath changed.
    FpcCustomPath is used by FindExeFpcCompiler which is used by TFpcVersion.Create. }
  if (FpcVersionCached <> nil) and
     (FpcVersionCached.CachedFpcPath <> FpcCustomPath) then
    FreeAndNil(FpcVersionCached);
  if FpcVersionCached = nil then
  begin
    FpcVersionCached := TFpcVersion.Create;
    FpcVersionCached.CachedFpcPath := FpcCustomPath;
  end;
  Result := FpcVersionCached;
end;

{ TLazarusVersion ---------------------------------------------------------------- }

constructor TLazarusVersion.Create;
var
  ToolOutput, ToolExe: string;
  ToolExitStatus: Integer;
  ToolOutputList: TStringList;
begin
  inherited;

  ToolExe := FindExeLazbuild;
  MyRunCommandIndir(GetCurrentDir, ToolExe, ['--version'], ToolOutput, ToolExitStatus,
    // use rcNoConsole to not blink with a console when CGE editor starts
    nil, nil, [rcNoConsole]);
  if ToolExitStatus <> 0 then
    raise Exception.Create('Failed to query Lazarus (lazbuild) version');

  { parse ToolOutput into Major,Minor,Release }
  ToolOutputList := TStringList.Create;
  try
    ToolOutputList.Text := ToolOutput;

    if ToolOutputList.Count >= 2 then
    begin
      { Typical case. Lazbuild returns
          using config file ..../lazarus.cfg
          2.3.0
        with "using config file" possibly localized.
        So we first try 2nd line as a version number. }
      try
        ParseVersion(ToolOutputList[1]);
      except
        ParseVersion(ToolOutputList[0]);
      end;
    end else
    if ToolOutputList.Count = 1 then
    begin
      ParseVersion(ToolOutputList[0]);
    end else
      raise Exception.Create('Failed to query Lazarus (lazbuild) version, got empty output');
  finally FreeAndNil(ToolOutputList) end;

  WritelnVerbose('Lazarus version: ' + ToString);
end;

var
  LazarusVersionCached: TLazarusVersion;

function LazarusVersion: TLazarusVersion;
begin
  { Invalidate cache if LazarusCustomPath changed.
    LazarusCustomPath is used by FindExeLazbuild which is used by TLazarusVersion.Create. }
  if (LazarusVersionCached <> nil) and
     (LazarusVersionCached.CachedLazarusPath <> LazarusCustomPath) then
    FreeAndNil(LazarusVersionCached);
  if LazarusVersionCached = nil then
  begin
    LazarusVersionCached := TLazarusVersion.Create;
    LazarusVersionCached.CachedLazarusPath := LazarusCustomPath;
  end;
  Result := LazarusVersionCached;
end;

finalization
  FreeAndNil(FpcVersionCached);
  FreeAndNil(LazarusVersionCached);
end.
