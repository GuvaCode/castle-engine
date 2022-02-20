{
  Copyright 2014-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.
  Parts of this file are based on FPC packages/fpmkunit/src/fpmkunit.pp unit,
  which conveniently uses *exactly* the same license as Castle Game Engine.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Generating resources (res) files. }
unit ToolResources;

interface

uses CastleUtils, CastleStringUtils,
  ToolProject, ToolArchitectures, Classes;

{ Maybe make castle-auto-generated-resources.res (depends on platform).
  Returns if resource file was created. }
function MakeAutoGeneratedResources(const Project: TCastleProject;
  const FinalOutputResourcePath: string;
  const OS: TOS; const CPU: TCpu; const Plugin: Boolean): Boolean;

implementation

uses SysUtils,
  Resource, ResWriter, VersionResource, VersionConsts, VersionTypes,
  GroupIconResource,
  CastleURIUtils, CastleLog, CastleFilesUtils, CastleDownload,
  ToolCommonUtils, ToolUtils, ToolCompilerInfo, ToolManifest;

function MakeAutoGeneratedResources(const Project: TCastleProject;
  const FinalOutputResourcePath: string;
  const OS: TOS; const CPU: TCpu; const Plugin: Boolean): Boolean;

  function MakeVersion(const V: TProjectVersion): TFileProductVersion;
  var
    I: Integer;
  begin
    for I := 0 to 3 do
      Result[I] := V.Items[I];
  end;

const
  ManifestTemplate = {$I ../embedded_templates/windows/castle-automatic-windows.manifest.inc};
  // Used as default in RC parser in fcl-res, with comment "MS RC starts up as en-US"
  DefaultRcLanguage = $0409;
var
  IcoPath, OutputManifest: string;
  FullIcoPath, ResFilename: string;
  Res: TResources;
  VerRes: TVersionResource;
  VerStringTable: TVersionStringTable;
  VerTranslationInfo: TVerTranslationInfo;
  ResManifest: TGenericResource;
  ResIconGroup: TGroupIconResource;
  ManifestStream, IconStream: TStream;
begin
  // For now, the .res files are only used on Windows
  Result := OS in AllWindowsOSes;
  if not Result then Exit;

  OutputManifest := Project.ReplaceMacros(ManifestTemplate);

  { nil local variables, to easily finalize them later in one finally..end clause }
  ManifestStream := nil;
  IconStream := nil;

  Res := TResources.Create;
  try
    { Originally written as RC file, with resource contents
      (version info, icon, manifest)
      crafted looking at docs, what others are doing, and what Lazarus produces:

      http://www.osronline.com/article.cfm?article=588
      http://msdn.microsoft.com/en-us/library/windows/desktop/aa381058%28v=vs.85%29.aspx
      http://stackoverflow.com/questions/12821369/vc-2012-how-to-include-version-info-from-version-inc-maintained-separately
      http://forum.lazarus.freepascal.org/index.php?topic=8979.0

      This was then reworked RC -> into Pascal code using FPC TResources.
      This way we can construct this in a cross-platform way,
      without any additional intermediate RC files,
      and generate RES without any external tools (like windres).
      To understand how RC -> map into fcl-res classes

      - read fcl-res source code, esp. rcparser.y.

      - https://www.freepascal.org/docs-html/current/fclres/basic%20usage.html
        is very helpful to understand fcl-res classes.
    }

    VerRes := TVersionResource.Create;
    VerRes.LangID := DefaultRcLanguage;
    VerRes.FixedInfo.FileVersion := MakeVersion(Project.Version);
    VerRes.FixedInfo.ProductVersion := MakeVersion(Project.Version);
    VerRes.FixedInfo.FileOS := VOS_NT_WINDOWS32;
    VerRes.FixedInfo.FileType := VFT_APP;
    Res.Add(VerRes);

    VerStringTable := TVersionStringTable.Create('040904b0');
    if Project.Author <> '' then
    begin
      VerStringTable.Add('CompanyName', Project.Author);
      VerStringTable.Add('LegalCopyright', 'Copyright ' + Project.Author);
    end;
    VerStringTable.Add('FileDescription', Project.Name);
    VerStringTable.Add('FileVersion', Project.Version.DisplayValue);
    VerStringTable.Add('InternalName', Project.Name);
    VerStringTable.Add('OriginalFilename', Project.ExecutableName + '.exe');
    VerStringTable.Add('ProductName', Project.Name);
    VerStringTable.Add('ProductVersion', Project.Version.DisplayValue);
    VerRes.StringFileInfo.Add(VerStringTable);

    VerTranslationInfo.Language := $0409; // US English
    VerTranslationInfo.Codepage := 1200; // Unicode
    VerRes.VarFileInfo.Add(VerTranslationInfo);

    ResManifest := TGenericResource.Create(
      TResourceDesc.Create(RT_MANIFEST),
      TResourceDesc.Create(1)
    );
    ManifestStream := TStringStream.Create(OutputManifest);
    ResManifest.SetCustomRawDataStream(ManifestStream);
    Res.Add(ResManifest);

    IcoPath := Project.Icons.FindExtension(['.ico']);
    FullIcoPath := CombinePaths(Project.Path, IcoPath);
    if IcoPath <> '' then
    begin
      ResIconGroup := TGroupIconResource.Create(nil, TResourceDesc.Create('MAINICON'));
      IconStream := Download(FilenameToURISafe(FullIcoPath));
      ResIconGroup.SetCustomItemDataStream(IconStream);
      Res.Add(ResIconGroup);
    end else
      WritelnWarning('Windows Resources', 'Icon in format suitable for Windows (.ico) not found. Exe file will not have icon.');

    ResFilename := FinalOutputResourcePath + 'castle-auto-generated-resources.res';
    Res.WriteToFile(ResFilename);
  finally
    FreeAndNil(Res);
    { Free streams.
      We need to do this, passing them to SetCustomItemDataStream / SetCustomItemDataStream
      doesn't make them owned by Res.
      This is confirmed with testing with HeapTrc, and reading docs
      https://www.freepascal.org/docs-html/current/fclres/basic%20usage.html. }
    FreeAndNil(ManifestStream);
    FreeAndNil(IconStream);
  end;

  WritelnVerbose('Generated ' + ExtractFileName(ResFilename) + ', make sure you include it in your dpr/lpr source file like this:');
  WritelnVerbose('  {$ifdef CASTLE_AUTO_GENERATED_RESOURCES} {$R ' + ExtractFileName(ResFilename) + '} {$endif}');
end;

end.
