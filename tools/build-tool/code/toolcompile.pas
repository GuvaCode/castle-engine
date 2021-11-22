{
  Copyright 2014-2021 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Compiling with FPC. }
unit ToolCompile;

{$I castleconf.inc}

interface

uses Classes,
  CastleStringUtils,
  ToolManifest, ToolArchitectures;

type
  TCompilationMode = (cmRelease, cmValgrind, cmDebug);

{ Compile with Pascal compiler.
  SearchPaths, ExtraOptions may be @nil (same as empty). }
procedure Compile(Compiler: TCompiler;
  const OS: TOS; const CPU: TCPU; const Plugin: boolean;
  const Mode: TCompilationMode; const WorkingDirectory, CompileFile: string;
  const SearchPaths, LibraryPaths: TStrings;
  const ExtraOptions: TStrings);

{ Compile with FPC and proper command-line option given file.
  SearchPaths, ExtraOptions may be @nil (same as empty). }
procedure CompileFpc(const OS: TOS; const CPU: TCPU; const Plugin: boolean;
  const Mode: TCompilationMode; const WorkingDirectory, CompileFile: string;
  const SearchPaths, LibraryPaths: TStrings;
  const ExtraOptions: TStrings);

{ Compile with Delphi and proper command-line option given file.
  SearchPaths, ExtraOptions may be @nil (same as empty). }
procedure CompileDelphi(const OS: TOS; const CPU: TCPU;
  const Mode: TCompilationMode; const WorkingDirectory, CompileFile: string;
  const SearchPaths: TStrings;
  const ExtraOptions: TStrings);

{ Compile with lazbuild. }
procedure CompileLazbuild(const OS: TOS; const CPU: TCPU;
  const Mode: TCompilationMode;
  const WorkingDirectory, LazarusProjectFile: string);

{ Run lazbuild with specified command-line options.
  Warning: This @italic(may) modify LazbuildOptions contents,
  consider them undefined after this call. }
procedure RunLazbuild(const WorkingDirectory: String; const LazbuildOptions: TCastleStringList);
procedure RunLazbuild(const WorkingDirectory: String; const LazbuildOptions: array of String);

{ Output path, where temporary things like units (and iOS stuff)
  are placed. }
function CompilationOutputPath(const Compiler: TCompiler;
  const OS: TOS; const CPU: TCPU;
  const WorkingDirectory: string): string;

function ModeToString(const M: TCompilationMode): string;
function StringToMode(const S: string): TCompilationMode;

var
  { Should we use the -Vxxx parameter, that is necessary if you got FPC
    from the fpc-3.0.3.intel-macosx.cross.ios.dmg
    (official "FPC for iOS" installation). }
  FpcVersionForIPhoneSimulator: string = 'auto';

const
  { Paths with units and include files that are for all OSes and all compilers.

    Note:

    - We don't bother trying to have separate include dirs (.inc) and units (.pas).
      We just pass the same paths for both includes and units, this is simpler.

    - We pass all paths, even system-specific, regardless of the target
      OS/architecture.

      We tried smarter approach in the past (such that you could have e.g.
      "windows/castle_system_specific.inc" and "unix/castle_system_specific.inc",
      and compiler recognized what to do on [$I castle_system_specific.inc]
      based on include paths)...
      but it was not really friendly for Lazarus lpk.

      So it is simpler to just name all includes and units differently,
      even across system-specific dirs. }

  EnginePaths: array [0..44] of String = (
    'base',
    'common_includes',
    'base/android',
    'base/windows',
    'base/unix',
    'base/opengl',
    'fonts',
    'fonts/opengl',
    'window',
    'window/gtk',
    'window/windows',
    'window/unix',
    'window/deprecated_units',
    'images',
    'images/opengl',
    'images/opengl/glsl/generated-pascal',
    '3d',
    '3d/opengl',
    'x3d',
    'x3d/opengl',
    'x3d/opengl/glsl/generated-pascal',
    'audio',
    'audio/fmod',
    'audio/openal',
    'audio/ogg_vorbis',
    'files',
    'files/indy',
    'castlescript',
    'ui',
    'ui/windows',
    'ui/opengl',
    'game',
    'services',
    'services/opengl',
    'physics',
    'physics/kraft',
    'pasgltf',
    'deprecated_units',
    { Vampyre Imaging Library }
    'vampyre_imaginglib/src/Source',
    'vampyre_imaginglib/src/Source/JpegLib',
    'vampyre_imaginglib/src/Source/ZLib',
    'vampyre_imaginglib/src/Extras/Extensions',
    'vampyre_imaginglib/src/Extensions/J2KObjects',
    'vampyre_imaginglib/src/Extensions/LibTiff',
    'vampyre_imaginglib/src/Extensions'
  );

  { Additional include/units paths, only for Delphi. }
  EnginePathsDelphi: array [0..1] of String = (
    'compatibility/delphi-only',
    'compatibility/delphi-only/fcl-json'
  );

  { Paths for library (object) files.
    For FPC these are passed using -Fl. }
  EngineLibraryPaths: array [0..1] of String = (
    'vampyre_imaginglib/src/Extensions/J2KObjects',
    'vampyre_imaginglib/src/Extensions/LibTiff/Compiled'
  );

implementation

uses SysUtils, Process,
  CastleUtils, CastleLog, CastleFilesUtils, CastleFindFiles,
  ToolCommonUtils, ToolUtils, ToolFpcVersion, ToolCompilerInfo;

type
  TFpcVersionForIPhoneSimulatorChecked = class
  strict private
    class var
      IsCached: boolean;
      CachedValue: string;
    class function AutoDetect(const FpcVer: TFpcVersion): string; static;
  public
    { Return FpcVersionForIPhoneSimulator, but the 1st time this is run,
      we check and optionally change the returned value to something better. }
    class function Value(const FpcVer: TFpcVersion): string; static;
  end;

class function TFpcVersionForIPhoneSimulatorChecked.AutoDetect(
  const FpcVer: TFpcVersion): string; static;
begin
  if (not Odd(FpcVer.Minor)) and
     (not Odd(FpcVer.Release)) then
  begin
    { If we have a stable FPC version (like 3.0.0, 3.0.2, 3.0.4...)
      then for iPhone Simulator pass -V with release bumped +1
      (making it 3.0.1, 3.0.3, 3.0.5...). }
    Result := Format('%d.%d.%d', [
      FpcVer.Major,
      FpcVer.Minor,
      FpcVer.Release + 1]);
    Writeln('Auto-detected FPC version for iPhone Simulator as ' + Result);
  end else
    { In other cases, do not pass any -Vxxx for iPhone Simulator.
      This is OK for FPC 3.1.1 from FPC SVN. }
    Result := '';
end;

class function TFpcVersionForIPhoneSimulatorChecked.Value(
  const FpcVer: TFpcVersion): string; static;
var
  FpcOutput, FpcExe: string;
  FpcExitStatus: Integer;
begin
  if not IsCached then
  begin
    CachedValue := FpcVersionForIPhoneSimulator;
    IsCached := true;

    if CachedValue = 'auto' then
      CachedValue := AutoDetect(FpcVer);

    if CachedValue <> '' then
    begin
      FpcExe := FindExeFpcCompiler;
      MyRunCommandIndir(GetCurrentDir, FpcExe, ['-V' + CachedValue, '-iV'], FpcOutput, FpcExitStatus);
      if FpcExitStatus <> 0 then
      begin
        WritelnWarning('Failed to execute FPC with "-V' + CachedValue + '" option, indicating that using this option for iPhone Simulator is invalid.' + NL +
          '  We will continue assuming that --fpc-version-iphone-simulator is empty (using normal FPC version to compile for iPhone Simulator).' + NL +
          '  Call with the correct --fpc-version-iphone-simulator on the command-line to get rid of this warning.');
        CachedValue := '';
      end;
    end;
  end;

  Result := CachedValue;
end;

type
  TCleanDirectoryHelper = class
    DeletedFiles: Cardinal; //< only for DeleteFoundFile
    procedure DeleteFoundFile(const FileInfo: TFileInfo; var StopSearch: boolean);
  end;

procedure TCleanDirectoryHelper.DeleteFoundFile(const FileInfo: TFileInfo; var StopSearch: boolean);
begin
  if Verbose then
    Writeln('Deleting ' + FileInfo.AbsoluteName);
  CheckDeleteFile(FileInfo.AbsoluteName);
  Inc(DeletedFiles);
end;

{ Clean compilation trash in Directory, recursively. }
procedure CleanDirectory(const Directory: string);
var
  Helper: TCleanDirectoryHelper;

  procedure DeleteFilesRecursive(const Mask: string);
  begin
    FindFiles(Directory, Mask, false,
      {$ifdef CASTLE_OBJFPC}@{$endif} Helper.DeleteFoundFile, [ffRecursive]);
  end;

begin
  Helper := TCleanDirectoryHelper.Create;
  try
    // clean FPC compilation stuff
    DeleteFilesRecursive('*.ppu');
    DeleteFilesRecursive('*.o');
    DeleteFilesRecursive('*.or');
    DeleteFilesRecursive('*.rst');
    DeleteFilesRecursive('*.rsj');
    Writeln('Deleted ', Helper.DeletedFiles, ' files');
  finally FreeAndNil(Helper) end;
end;

{ Writeln a message that FPC/Lazarus crashed and we will retry,
  and clean compilation leftover files. }
procedure FpcLazarusCrashRetry(const WorkingDirectory, ToolName, ProjectName: String);
begin
  Writeln('-------------------------------------------------------------');
  Writeln('It seems ' + ToolName + ' crashed. If you can reproduce this problem, please report it to http://bugs.freepascal.org/ ! We want to help ' + ProjectName + ' developers to fix this problem, and the only way to do it is to report it. If you need help creating a good bugreport, speak up on the ' + ProjectName + ' mailing list or Castle Game Engine forum.');
  Writeln;
  Writeln('As a workaround, right now we''ll clean your project, and (if we have permissions) the Castle Game Engine units, and try compiling again.');
  Writeln('-------------------------------------------------------------');
  { when we're called to compile a project, WorkingDirectory is the project path }
  CleanDirectory(WorkingDirectory);
  CleanDirectory(TempOutputPath(WorkingDirectory, false));
  if CastleEnginePath <> '' then
  begin
    { Compiling project using build tool (through FPC or lazbuild)
      should *not* leave any file in src/ .
      But, just to be safe, try to clear it if possible. }
    CleanDirectory(CastleEnginePath + 'src' + PathDelim);
    CleanDirectory(CastleEnginePath + 'packages' + PathDelim + 'lib' + PathDelim);
  end;
end;

function FilterFpcOutput(var Line: String; const Data: Pointer): Boolean;
var
  LineLower: String;
begin
  { Lowercase once and later use IsPrefix many times with IgnoreCase=false (faster). }
  LineLower := LowerCase(Line);
  Result := not (
    IsPrefix('generics.collections.pas(', LineLower, false) or
    IsPrefix('generics.dictionaries.inc(', LineLower, false)
  );
  // Uncomment this just to debug that our line splitting in TCaptureOutputFilter works
  // Line := '<begin>' + Line + '<end>';
end;

procedure CompileFpc(const OS: TOS; const CPU: TCPU; const Plugin: boolean;
  const Mode: TCompilationMode; const WorkingDirectory, CompileFile: string;
  const SearchPaths, LibraryPaths, ExtraOptions: TStrings);
var
  CastleEngineSrc: string;
  FpcVer: TFpcVersion;
  FpcOptions: TCastleStringList;

  procedure AddEnginePath(Path: string);
  begin
    Path := CastleEngineSrc + Path;
    if not DirectoryExists(Path) then
      WritelnWarning('Path', 'Path "%s" does not exist. Make sure that $CASTLE_ENGINE_PATH points to the directory containing Castle Game Engine sources.', [Path]);
    FpcOptions.Add('-Fu' + Path);
    FpcOptions.Add('-Fi' + Path);
  end;

  procedure AddEngineSearchPaths;
  var
    S: String;
  begin
    if CastleEngineSrc <> '' then
    begin
      for S in EnginePaths do
        AddEnginePath(S);

      if (not FpcVer.AtLeast(3, 1, 1)) or FpcVer.IsCodeTyphon then
        AddEnginePath('compatibility/generics.collections/src');

      { Do not add castle-fpc.cfg.
        Instead, rely on code below duplicating castle-fpc.cfg logic
        (reasons: engine sources, with castle-fpc.cfg, may not be available
        where build-tool is called).

      FpcOptions.Add('-dCASTLE_ENGINE_PATHS_ALREADY_DEFINED');
      FpcOptions.Add('@' + InclPathDelim(CastleEnginePath) + 'castle_game_engine(or castle-engine)/castle-fpc.cfg');
      }
    end;
  end;

  procedure AddSearchPaths;
  var
    S: String;
  begin
    if SearchPaths <> nil then
      for S in SearchPaths do
      begin
        FpcOptions.Add('-Fu' + S);
        FpcOptions.Add('-Fi' + S);
      end;
  end;

  procedure AddEngineLibraryPaths;
  var
    S: String;
  begin
    if CastleEngineSrc <> '' then
      for S in EngineLibraryPaths do
        FpcOptions.Add('-Fl' + CastleEngineSrc + S);
  end;

  procedure AddLibraryPaths;
  var
    S: String;
  begin
    if LibraryPaths <> nil then
      for S in LibraryPaths do
        FpcOptions.Add('-Fl' + S);
  end;

  function IsIOS: boolean;
  begin
    Result :=
      (OS = iphonesim) or
      ((OS = iOS) and (CPU = arm)) or
      ((OS = iOS) and (CPU = aarch64));
  end;

  procedure AddIOSOptions;
  {$ifdef DARWIN}
  const
    SimulatorSdk = '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk';
    DeviceSdk = '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk';
  {$endif}
  var
    LikeIOS: boolean; // physical iOS or iPhoneSimulator
    VersionForSimulator: string;
  begin
    LikeIOS := false;

    if OS = iphonesim then
    begin
      LikeIOS := true;
      VersionForSimulator := TFpcVersionForIPhoneSimulatorChecked.Value(FpcVer);
      if VersionForSimulator <> '' then
        FpcOptions.Add('-V' + VersionForSimulator);
      {$ifdef DARWIN}
      FpcOptions.Add('-XR' + SimulatorSdk);
      {$endif}
    end;

    if (OS = iOS) and (CPU = arm) then
    begin
      LikeIOS := true;
      FpcOptions.Add('-Cparmv7');
      FpcOptions.Add('-Cfvfpv3');
      {$ifdef DARWIN}
      FpcOptions.Add('-XR' + DeviceSdk);
      {$endif}
    end;

    if (OS = iOS) and (CPU = aarch64) then
    begin
      LikeIOS := true;
      {$ifdef DARWIN}
      FpcOptions.Add('-XR' + DeviceSdk);
      {$endif}
    end;

    Assert(LikeIOS = IsIOS);

    // options for all iOS-like platforms
    if LikeIOS then
    begin
      FpcOptions.Add('-Cn');
      FpcOptions.Add('-dCASTLE_IOS');

      { This corresponds to the iOS version used when compiling FPC 3.0.3 RTL
        from the latest official FPC release for iOS.
        With -WP5.1, I got a lot of warnings that FPC RTL was for iOS 7.0.
        Also, I got an error:
        clang: error: -fembed-bitcode is not supported on versions of iOS prior to 6.0
      }
      FpcOptions.Add('-WP7.0');

      { This option is actually ununsed, since we pass -Cn
        and later create the library manually.

        Add -w to ignore linker warnings

        This seems the only way to get rid of Xcode (>= 8.3) linker errors when
        compiling iOS project. The error is

          Warning:pointer not aligned at address...

        and it is caused when compiling x86 code for iPhone Simulator.
        The error is inside FPC RTL, FPC developers consider this warning
        unnecessary, aligning the relevant structured would be wasteful:
        https://bugs.freepascal.org/view.php?id=31696

        See more:
        https://forum.lazarus.freepascal.org/index.php?topic=36978.0
        https://stackoverflow.com/questions/41229076/project-settings-recommends-compiler-warning-suspicious-moves
      }
      //FpcOptions.Add('-k-w');

      { This option is actually ununsed, since we pass -Cn
        and later create the library manually. }
      FpcOptions.Add('-o' +
        CompilationOutputPath(coFpc, OS, CPU, WorkingDirectory) +
        'libcge_ios_project_unused.a');
    end;
  end;

var
  FpcOutput, FpcExe: string;
  FpcExitStatus: Integer;
begin
  FpcVer := FpcVersion;

  FpcOptions := TCastleStringList.Create;
  try
    if CastleEnginePath <> '' then
      CastleEngineSrc := CastleEnginePath + 'src' + PathDelim
    else
      CastleEngineSrc := '';

    AddEngineSearchPaths;
    AddSearchPaths;
    AddEngineLibraryPaths;
    AddLibraryPaths;

    { Specify the compilation options explicitly,
      duplicating logic from ../castle-fpc.cfg .
      (Engine sources may be possibly not available,
      so we also cannot depend on castle-fpc.cfg being available.) }
    FpcOptions.Add('-l');
    FpcOptions.Add('-vwn');
    FpcOptions.Add('-Ci');
    if GetEnvironmentVariable('CASTLE_ENGINE_TEST_DELPHI_MODE') = 'true' then
    begin
      FpcOptions.Add('-Mdelphi');
      FpcOptions.Add('-Sm-');
      FpcOptions.Add('-Sc-');
      // Also define it, to allow eventually doing
      // {$ifdef CASTLE_ENGINE_TEST_DELPHI_MODE}... in code.
      FpcOptions.Add('-dCASTLE_ENGINE_TEST_DELPHI_MODE');
    end else
    begin
      FpcOptions.Add('-Mobjfpc');
      FpcOptions.Add('-Sm');
      FpcOptions.Add('-Sc');
    end;
    FpcOptions.Add('-Sg');
    FpcOptions.Add('-Si');
    FpcOptions.Add('-Sh');
    FpcOptions.Add('-vm2045'); // do not show Warning: (2045) APPTYPE is not supported by the target OS
    FpcOptions.Add('-vm5024'); // do not show Hint: (5024) Parameter "..." not used

    // do not show
    // Warning: Constructing a class "TCustomDictionaryEnumerator$4$crc6100464F" with abstract method "GetCurrent"
    // Warning: Constructing a class "TCustomDictionaryEnumerator$4$crcBD4794B2" with abstract method "DoMoveNext"
    // Update: No need to hide it anymore: our FilterFpcOutput handles it, and thus we don't need to hide this useful warning for user code
    // FpcOptions.Add('-vm04046');

    if FpcVer.AtLeast(3, 1, 1) then
    begin
      // do not show Warning: Symbol "TArrayHelper$1" is experimental
      // (only for FPC 3.1.1, for 3.0.x we fix this in our custom Generics.Collections unit)
      // Update: No need to hide it anymore: our FilterFpcOutput handles it, and thus we don't need to hide this useful warning for user code
      // FpcOptions.Add('-vm05063');

      // do not show
      // Note: Private type "TCustomPointersEnumerator$2<CASTLEVECTORSINTERNALSINGLE.TGenericVector2,CASTLEVECTORS.TCustomList$1$crc1D7BB6F0.PT>.T" never used
      // Update: No need to hide it anymore: our FilterFpcOutput handles it, and thus we don't need to hide this useful warning for user code
      // FpcOptions.Add('-vm5071');
    end;

    if FpcVer.AtLeast(3, 2, 0) then
    begin
      // do not show
      // Warning: function result variable of a managed type does not seem to be initialized
      // (a lot of false warnings since FPC 3.3.1)
      FpcOptions.Add('-vm5093');

      // do not show
      // Note: Call to subroutine "$1" marked as inline is not inlined
      // (In FPC 3.3.1, not in FPC 3.1.1 rev 38027)
      // (flood of notes after using Generics.Collections, but also from other units)
      FpcOptions.Add('-vm6058');
    end;

    if FpcVer.AtLeast(3, 3, 1) then
    begin
      // do not show
      // Warning: Local variable "$1" of a managed type does not seem to be initialized
      // (a lot of false warnings since FPC 3.3.1)
      FpcOptions.Add('-vm5089');

      // do not show
      // Warning: Variable "OutputFace" of a managed type does not seem to be initialized
      // (3 false warnings since FPC 3.3.1 in Kraft)
      FpcOptions.Add('-vm5090');
    end;

    if (OS = iOS) and not FpcVer.AtLeast(3, 2, 2) then
      // Before FPC 3.2.2, the OS=iOS was designated as OS=darwin for FPC
      FpcOptions.Add('-Tdarwin')
    else
      FpcOptions.Add('-T' + OSToString(OS));

    FpcOptions.Add('-P' + CPUToString(CPU));

    { Release build and valgrind build are quite similar, they share many options. }
    if Mode in [cmRelease, cmValgrind] then
    begin
      { Aarch64 optimizations exhibit bugs, on all OSes,
        with older FPC < 3.3.1 (rev 48104).
        Testcases:

        - iOS:

          With FPC 3.0.3 on iOS/aarch64 (physical iOS, 64-bit)
          it seems all programs compiled with -O1 or -O2 crash at start.

        - Android:

          Reading some PNG fails (testcase: Silhouette), at least with -O2, fails.

          It is unsure with which FPC version this was reproducible.
          Probably some FPC 3.0.x.
          Michalis can no longer reproduce it with FPC 3.3.1 revision 42921
          (latest revision as of 2019/09/05).

        - Android and Nintendo Switch and iOS:

          TDrawableImage.Draw3x3 calculations are wildly wrong,
          and in effect TDrawableImage.Draw3x3 usually doesn't seem to draw anything.
          It seems like DrawWidth parameter is not received correctly,
          but workarounding it only uncovers more problems, it looks like
          the values in local Single variables there randomly change.

          This is still reproducible with FPC 3.3.1 revision 42921
          (latest revision as of 2019/09/05),
          however it is locally workarounded by "$optimizations off" around
          Draw3x3 implementation now.

        So we disable optimizations on Aarch64.
        Unless $CASTLE_ENGINE_ENABLE_AARCH64_OPTIMIZER is set to true.
        Or unless we have FPC version where it was fixed:
        see https://trello.com/c/5ydB4MuA/113-enable-again-aarch64-optimizations }

      if (CPU = Aarch64) and
         (not FpcVer.AtLeast(3, 3, 1)) and
         (GetEnvironmentVariable('CASTLE_ENGINE_ENABLE_AARCH64_OPTIMIZER') <> 'true') then
      begin
        FpcOptions.Add('-O-');
        WritelnWarning('Disabling optimizations, because they are buggy on Aarch64 with FPC < 3.3.1 (rev 48104).');
      end else
        FpcOptions.Add('-O2');
      FpcOptions.Add('-dRELEASE');
    end;

    case Mode of
      cmRelease:
        begin
          FpcOptions.Add('-Xs');
        end;
      cmValgrind:
        begin
          { See https://github.com/castle-engine/castle-engine/wiki/Profiling-Using-Valgrind
            for reasons of Valgrind options. }
          FpcOptions.Add('-gv');
          FpcOptions.Add('-gl');
        end;
      cmDebug:
        begin
          FpcOptions.Add('-Cr');
          FpcOptions.Add('-Co');
          FpcOptions.Add('-Sa');
          FpcOptions.Add('-CR');
          FpcOptions.Add('-g');
          FpcOptions.Add('-gl');
          FpcOptions.Add('-dDEBUG');
        end;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('CompileFpc: Mode?');
      {$endif}
    end;

    if (OS = Android) and (CPU = arm) then
    begin
      { Our platform is armeabi-v7a, see ToolAndroidPackage
        comments about armeabi-v7a.
        Note: the option below seems not necessary when using -CfVFPV3?
        At least, nothing crashes.
        Possibly -CfVFPV3 implies this anyway. }
      FpcOptions.Add('-CpARMV7A');

      { Necessary to work fast.
        See https://github.com/castle-engine/castle-engine/wiki/Android-FAQ#notes-about-compiling-with-hard-floats--cfvfpv3 }
      FpcOptions.Add('-CfVFPV3');

      { This allows to "sacrifice precision for performance"
        according to http://wiki.freepascal.org/ARM_compiler_options .

        But it causes too much precision loss?
        escape_universe fails with
        I/escape_universe( 7761): Exception: Exception "EInvalidGameConfig" :
        I/escape_universe( 7761): Gun auto_fire_interval cannot be <= 0

        Speed gain untested.

        For now unused. }
      //FpcOptions.Add('-OoFASTMATH');

      { This should *not* be defined (when compiling our code or RTL).
        It makes our code use -CaEABIHF/armeabi-v7a-hard
        https://android.googlesource.com/platform/ndk/+/353e653824b79c43b948429870d0abeedebde386/docs/HardFloatAbi.md
        which has incompatible call mechanism.

        And indeed, doing PlaySound crashes at alSourcef call (to OpenAL)
        from TInternalSoundSource.SetMinGain. Reproducible with escape_universe.

        fpcupdeluxe default cross-compiler to Android also uses this. }
      //FpcOptions.Add('-CaEABIHF');
    end;

    if Plugin then
    begin
      FpcOptions.Add('-dCASTLE_ENGINE_PLUGIN');
      { We need to add -fPIC otherwise compiling a shared library fails with

        /usr/bin/ld: .../castlewindow.o: relocation R_X86_64_32S against
          `U_CASTLEWINDOW_MENUITEMS' can not be used when making
          a shared object; recompile with -fPIC

        That is because FPC RTL is compiled with -fPIC for this platform,
        it seems. See
        http://lists.freepascal.org/pipermail/fpc-pascal/2014-November/043155.html
        http://lists.freepascal.org/pipermail/fpc-pascal/2014-November/043159.html

        """
        fpcmake automatically adds -Cg/-fPIC for x86-64 platforms,
        exactly because of this issue.
        """

        And http://wiki.freepascal.org/PIC_information explains about PIC:
        """
        fpcmake automatically adds -Cg/-fPIC for x86-64 platforms:
        * for freebsd, openbsd, netbsd, linux, solaris
        * for darwin -Cg is enabled by the compiler (see below)
        """
      }
      if (CPU = X86_64) and (OS in [Linux,FreeBSD,NetBSD,OpenBSD,Solaris]) then
        FpcOptions.Add('-fPIC');
    end;

    FpcOptions.Add(CompileFile);
    FpcOptions.Add('-FU' + CompilationOutputPath(coFpc, OS, CPU, WorkingDirectory));

    AddIOSOptions;

    if ExtraOptions <> nil then
      FpcOptions.AddRange(ExtraOptions);

    Writeln('FPC executing...');
    FpcExe := FindExeFpcCompiler;

    RunCommandIndirPassthrough(WorkingDirectory, FpcExe, FpcOptions.ToArray, FpcOutput, FpcExitStatus, '', '', @FilterFpcOutput);
    if FpcExitStatus <> 0 then
    begin
      if (Pos('Fatal: Internal error', FpcOutput) <> 0) or
         (Pos('Error: Compilation raised exception internally', FpcOutput) <> 0) then
      begin
        FpcLazarusCrashRetry(WorkingDirectory, 'FPC', 'FPC');
        RunCommandIndirPassthrough(WorkingDirectory, FpcExe, FpcOptions.ToArray, FpcOutput, FpcExitStatus, '', '', @FilterFpcOutput);
        if FpcExitStatus <> 0 then
          { do not retry compiling in a loop, give up }
          raise Exception.Create('Failed to compile');
      end else
        raise Exception.Create('Failed to compile');
    end;
  finally FreeAndNil(FpcOptions) end;
end;

procedure Compile(Compiler: TCompiler;
  const OS: TOS; const CPU: TCPU; const Plugin: boolean;
  const Mode: TCompilationMode; const WorkingDirectory, CompileFile: string;
  const SearchPaths, LibraryPaths: TStrings;
  const ExtraOptions: TStrings);
begin
  { resolve Compiler to something other than coAutodetect }
  if Compiler = coAutodetect then
  begin
    if FindExeFpcCompiler(false) <> '' then
      Compiler := coFpc
    else
    if FindDelphiPath(false) <> '' then
      Compiler := coDelphi
    else
      raise Exception.Create('Neither FPC nor Delphi found, cannot autodetect compiler');
  end;
  Assert(Compiler <> coAutodetect);

  case Compiler of
    coFpc: CompileFpc(OS, CPU, Plugin, Mode, WorkingDirectory, CompileFile,
      SearchPaths, LibraryPaths, ExtraOptions);
    coDelphi: CompileDelphi(OS, CPU, Mode, WorkingDirectory, CompileFile,
      SearchPaths, ExtraOptions);
    else raise EInternalError.Create('Compile: Compiler?');
  end;
end;

procedure CompileDelphi(const OS: TOS; const CPU: TCPU;
  const Mode: TCompilationMode; const WorkingDirectory, CompileFile: string;
  const SearchPaths: TStrings;
  const ExtraOptions: TStrings);
var
  CastleEngineSrc: String;
  DccOptions: TCastleStringList;

  { Add search namespaces, to keep basic units like SysUtils accessible
    without namespace. This follows the DPROJ settings generated by Delphi
    for new projects. }
  procedure AddSearchNamespaces;
  const
    SearchNamespacesGeneral = 'System;Xml;Data;Datasnap;Web;Soap';
    SearchNamespacesWindows = 'Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;Bde';
  var
    SearchNamespaces: String;
  begin
    { calculate SearchNamespaces }
    SearchNamespaces := SearchNamespacesGeneral;
    if OS in AllWindowsOSes then
      SearchNamespaces := SAppendPart(SearchNamespaces, ';', SearchNamespacesWindows);

    DccOptions.Add('-NS' + SearchNamespaces);
  end;

  procedure AddEnginePath(Path: string);
  begin
    Path := CastleEngineSrc + Path;
    if not DirectoryExists(Path) then
      WritelnWarning('Path', 'Path "%s" does not exist. Make sure that $CASTLE_ENGINE_PATH points to the directory containing Castle Game Engine sources.', [Path]);
    DccOptions.Add('-U' + Path);
    DccOptions.Add('-I' + Path);
  end;

  procedure AddEngineSearchPaths;
  var
    S: String;
  begin
    if CastleEngineSrc <> '' then
    begin
      for S in EnginePaths do
        AddEnginePath(S);
      for S in EnginePathsDelphi do
        AddEnginePath(S);
    end;
  end;

  procedure AddSearchPaths;
  var
    S: String;
  begin
    if SearchPaths <> nil then
      for S in SearchPaths do
      begin
        DccOptions.Add('-U' + S);
        DccOptions.Add('-I' + S);
      end;
  end;

  procedure AddOutputPaths;
  var
    OutPath: String;
  begin
    OutPath := CompilationOutputPath(coDelphi, OS, CPU, WorkingDirectory);
    { Looks like DCCxxx cannot handle parameters with spaces? Answers
        Fatal: F1026 File not found: 'Game.dpr'
      for
        -NUC:\Users\michalis\Documents\Castle Game Engine Projects\my-new-project-delphi3d\castle-engine-output\compilation\delphi\x86_64-win64\
      Workaround: pass relative paths. }
    OutPath := ExtractRelativePath(InclPathDelim(WorkingDirectory), OutPath);
    DccOptions.Add('-NU' + OutPath);
    DccOptions.Add('-NH' + OutPath);
    DccOptions.Add('-NO' + OutPath);
    DccOptions.Add('-NB' + OutPath);
    DccOptions.Add('-NX' + OutPath);
  end;

var
  DelphiPath, Dcc, DccExe: String;
  DccOutput: String;
  DccExitStatus: Integer;
begin
  DelphiPath := FindDelphiPath(true);

  { calculate Dcc, which is compiler basename with OS/CPU suffix.
    The combinations confirmed to be possible in Delphi 11:

      dcc32 - Win32
      dcc64 - Win64
      dccaarm - Android/Arm
      dccaarm64 - Android/Arm64
      dcciosarm64 - iOS/Arm64
      dcclinux64 - Linux/x86_64
      dccosx64 - macos/x86_64
      dccosxarm64 - macos/Arm64
  }
  Dcc := 'dcc';
  case OS of
    Win32, Win64: ;
    Android: Dcc += 'a';
    iOS    : Dcc += 'ios';
    Linux  : Dcc += 'linux';
    MacOSX : Dcc += 'osx';
    else raise Exception.CreateFmt('Operating system "%s" not supported by Delphi', [OSToString(OS)]);
  end;
  case CPU of
    i386   : Dcc += '32';
    x86_64 : Dcc += '64';
    Arm    : Dcc += 'arm';
    Aarch64: Dcc += 'arm64';
    else raise Exception.CreateFmt('CPU "%s" not supported by Delphi', [CPUToString(CPU)]);
  end;

  DccExe := DelphiPath + 'bin' + PathDelim + Dcc + ExeExtension;
  if not RegularFileExists(DccExe) then
    raise Exception.CreateFmt('Cannot find Delphi compiler for this OS/CPU: %s', [DccExe]);

  if CastleEnginePath <> '' then
    CastleEngineSrc := CastleEnginePath + 'src' + PathDelim
  else
    CastleEngineSrc := '';

  DccOptions := TCastleStringList.Create;
  try
    Writeln('Delphi compiler executing...');

    AddSearchNamespaces;
    AddEngineSearchPaths;
    AddSearchPaths;
    AddOutputPaths;

    // TODO: Do something more useful for release optimizations or debugging
    case Mode of
      cmRelease, cmValgrind: DccOptions.Add('-dRELEASE');
      cmDebug              : DccOptions.Add('-dDEBUG');
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('CompileDelphi: Mode?');
      {$endif}
    end;

    DccOptions.Add(CompileFile);

    if ExtraOptions <> nil then
      DccOptions.AddRange(ExtraOptions);

    RunCommandIndirPassthrough(WorkingDirectory, DccExe, DccOptions.ToArray, DccOutput, DccExitStatus);
    if DccExitStatus <> 0 then
      raise Exception.Create('Failed to compile');
  finally FreeAndNil(DccOptions) end;
end;

procedure RunLazbuild(const WorkingDirectory: String; const LazbuildOptions: TCastleStringList);
var
  LazbuildExe: String;
  LazbuildOutput: String;
  LazbuildExitStatus: Integer;
begin
  LazbuildExe := FindExeLazarus('lazbuild');
  if LazbuildExe = '' then
    raise EExecutableNotFound.Create('Cannot find "lazbuild" program. Make sure it is installed, and available on environment variable $PATH. If you use the CGE editor, you can also set Lazarus location in "Preferences".');

  RunCommandIndirPassthrough(WorkingDirectory,
    LazbuildExe, LazbuildOptions.ToArray, LazbuildOutput, LazbuildExitStatus, '', '', @FilterFpcOutput);
  if LazbuildExitStatus <> 0 then
  begin
    { Old lazbuild can fail with exception like this:

        An unhandled exception occurred at $0000000000575F5F:
        EAccessViolation: Access violation
          $0000000000575F5F line 590 of exttools.pas
          $000000000057A027 line 1525 of exttools.pas
          $000000000057B231 line 1814 of exttools.pas

      Simply retrying works.
    }
    if (Pos('Fatal: Internal error', LazbuildOutput) <> 0) or
       (Pos('EAccessViolation: Access violation', LazbuildOutput) <> 0) then
    begin
      FpcLazarusCrashRetry(WorkingDirectory, 'Lazarus (lazbuild)', 'Lazarus');
      RunCommandIndirPassthrough(WorkingDirectory,
        LazbuildExe, LazbuildOptions.ToArray, LazbuildOutput, LazbuildExitStatus, '', '', @FilterFpcOutput);
      if LazbuildExitStatus <> 0 then
        { do not retry compiling in a loop, give up }
        raise Exception.Create('Failed to compile');
    end else
      raise Exception.Create('Failed to compile');
  end else

  // lazbuild from Lazarus 1.6.4 doesn't support add-package-link
  if (Pos('Invalid option at position 3: "add-package-link"', LazbuildOutput) <> 0) and
     (LazbuildOptions.IndexOf('--add-package-link') <> -1) then
  begin
    Writeln('lazbuild does not support --add-package-link, retrying without it');
    LazbuildOptions.Delete(LazbuildOptions.IndexOf('--add-package-link'));
    RunCommandIndirPassthrough(WorkingDirectory,
      LazbuildExe, LazbuildOptions.ToArray, LazbuildOutput, LazbuildExitStatus, '', '', @FilterFpcOutput);
    if LazbuildExitStatus <> 0 then
      { do not retry compiling in a loop, give up }
      raise Exception.Create('Failed to compile');
  end;
end;

procedure RunLazbuild(const WorkingDirectory: String; const LazbuildOptions: array of String);
var
  L: TCastleStringList;
begin
  L := TCastleStringList.Create;
  try
    L.Assign(LazbuildOptions);
    RunLazbuild(WorkingDirectory, L);
  finally FreeAndNil(L) end;
end;

procedure CompileLazbuild(const OS: TOS; const CPU: TCPU;
  const Mode: TCompilationMode;
  const WorkingDirectory, LazarusProjectFile: string);
var
  LazbuildOptions: TCastleStringList;
begin
  LazbuildOptions := TCastleStringList.Create;
  try
    // register CGE packages first
    if CastleEnginePath <> '' then
    begin
      LazbuildOptions.Clear;
      LazbuildOptions.Add('--add-package-link');
      LazbuildOptions.Add(CastleEnginePath + 'packages' + PathDelim + 'castle_base.lpk');
      RunLazbuild(WorkingDirectory, LazbuildOptions);

      LazbuildOptions.Clear;
      LazbuildOptions.Add('--add-package-link');
      LazbuildOptions.Add(CastleEnginePath + 'packages' + PathDelim + 'castle_window.lpk');
      RunLazbuild(WorkingDirectory, LazbuildOptions);

      LazbuildOptions.Clear;
      LazbuildOptions.Add('--add-package-link');
      LazbuildOptions.Add(CastleEnginePath + 'packages' + PathDelim + 'castle_components.lpk');
      RunLazbuild(WorkingDirectory, LazbuildOptions);
    end;

    LazbuildOptions.Clear;
    LazbuildOptions.Add('--os=' + OSToString(OS));
    LazbuildOptions.Add('--cpu=' + CPUToString(CPU));
    { // Do not pass --build-mode, as project may not have it defined.
    if Mode = cmDebug then
      LazbuildOptions.Add('--build-mode=Debug')
    else
      LazbuildOptions.Add('--build-mode=Release');
    }

    { For historic reasons, Lazarus defaults to Carbon on macOS,
      even on 64-bit macOS where you cannot link with Carbon.
      And since macOS Catalina (10.15) all applications *must* be 64-bit
      (32-bit is no longer supported) so this is important.
      So we change it to cocoa.

      TODO: This likely prevents the project from using it's own,
      custom widgetset in case of macOS.

      But there doesn't seem any better way of fixing this per-project.
      I cannot use "Custom Options",

        if (TargetOS='darwin') and (TargetCPU='x86_64') then
          LCLWidgetType := 'cocoa';

      -- it looks like LCLWidgetType is ignored in "Custom Options".

      I cannot use "Additions and Overrides", as it doesn't seem to allow
      to choose widgetset per-platform (like per-OS, or per-OS-and-CPU).
      It would only allow to set Cocoa always.
      Or in a specific build mode, but then I would need to
      - maintain this build mode in my examples,
      - 2 times (for both Debug/Release, I would need a copy DebugMacOS and ReleaseMacOS)
      - and require it in all user projects (this is not acceptable).
    }
    if (OS = darwin) and (CPU = X86_64) then
      LazbuildOptions.Add('--widgetset=cocoa');
    LazbuildOptions.Add(LazarusProjectFile);

    RunLazbuild(WorkingDirectory, LazbuildOptions);
  finally FreeAndNil(LazbuildOptions) end;
end;

function CompilationOutputPath(const Compiler: TCompiler;
  const OS: TOS; const CPU: TCPU;
  const WorkingDirectory: string): string;
begin
  Result := TempOutputPath(WorkingDirectory) + 'compilation' + PathDelim;
  if Compiler = coDelphi then
    Result += 'delphi' + PathDelim;
  Result += CPUToString(CPU) + '-' + OSToString(OS) + PathDelim;
  CheckForceDirectories(Result);
end;

const
  CompilationModeNames: array [TCompilationMode] of string =
  ('release', 'valgrind', 'debug');

function ModeToString(const M: TCompilationMode): string;
begin
  Result := CompilationModeNames[M];
end;

function StringToMode(const S: string): TCompilationMode;
begin
  for Result in TCompilationMode do
    if AnsiSameText(CompilationModeNames[Result], S) then
      Exit;
  raise Exception.CreateFmt('Invalid compilation mode name "%s"', [S]);
end;

end.
