{ This is NOT auto-generated, contrary to most CGE applications.

  This file is used to build and run the application on desktop (standalone) platforms,
  from various tools:
  - Castle Game Engine command-line build tool
  - Castle Game Engine editor
  - Lazarus IDE
  - Delphi IDE
}

{$ifdef MSWINDOWS} {$APPTYPE CONSOLE} { $apptype GUI} {$endif}

{ This adds icons and version info for Windows,
  automatically created by "castle-engine compile". }
{$ifdef CASTLE_AUTO_GENERATED_RESOURCES} {$R castle-auto-generated-resources.res} {$endif}

uses
  {$if defined(FPC) and (not defined(CASTLE_DISABLE_THREADS))}
    {$info Thread support enabled.}
    {$ifdef UNIX} CThreads, {$endif}
  {$endif}
  SysUtils, CastleAutoGenerated, CastleWindow, GameInitialize, CastleParameters,
  CastleApplicationProperties, CastleConsoleTester,

  { Testing (mainly) things inside Pascal standard library, not CGE }
  TestCompiler,
  TestSysUtils,
  {$ifdef FPC}TestFGL,{$endif}
  TestGenericsCollections,
  {$ifdef FPC}TestOldFPCBugs,{$endif}
  {$ifdef FPC}TestFPImage,{$endif}
  //TestToolFpcVersion,

  { Testing CGE units }
  TestCastleUtils,
  TestCastleRectangles,
  TestCastleFindFiles,
  TestCastleFilesUtils,
  TestCastleUtilsLists,
  TestCastleClassUtils,
  TestCastleVectors,
  TestCastleTriangles,
  TestCastleColors,
  TestCastleQuaternions,
  TestCastleRenderOptions,
  TestCastleKeysMouse,
  TestCastleImages,
  TestCastleInternalDataCompression,
  TestCastleImagesDraw,
  TestCastleBoxes,
  TestCastleFrustum,
  TestCastleInternalGLShadowVolumes,
  TestCastleFonts,
  TestCastleTransform,
  TestCastleParameters,
  TestCastleUIControls,
  TestCastleCameras,
  TestX3DFields,
  TestX3DNodes,
  TestX3DNodesOptimizedProxy,
  TestX3DNodesNurbs,
  TestCastleScene,
  TestCastleSceneCore,
  TestCastleSceneManager,
  TestCastleVideos,
  TestCastleSpaceFillingCurves,
  TestCastleStringUtils,
  TestCastleScript,
  TestCastleScriptVectors,
  TestCastleCubeMaps,
  TestCastleGLVersion,
  TestCastleCompositeImage,
  TestCastleTriangulate,
  TestCastleGame,
  TestCastleUriUtils,
  TestCastleXmlUtils,
  TestCastleCurves,
  TestCastleTimeUtils,
  TestCastleControls,
  TestCastleSoundEngine,
  TestCastleComponentSerialize,
  TestCastleDesignComponents,
  TestX3DLoadInternalUtils,
  TestCastleLevels,
  TestCastleDownload,
  TestCastleUnicode,
  TestCastleResources,
  TestX3DLoadGltf,
  TestCastleTiledMap,
  TestCastleInternalAutoGenerated,
  TestCastleLocalizationGetText,
  TestCastleViewport,
  TestCastleInternalRttiUtils,
  TestCastleShapes,
  TestCastleInternalDelphiUtils,
  TestCastleFileFilters,
  TestCastleWindow,
  TestCastleOpeningAndRendering3D,
  TestCastleWindowOpen;

var
  ConsoleTester: TCastleConsoleTester;
begin
  if Parameters.IndexOf('--console') = -1 then
  begin
    Application.MainWindow.OpenAndRun;
  end else
  begin
    { Avoid warnings about opening files too early. }
    ApplicationProperties._FileAccessSafe := true;
    ConsoleTester := TCastleConsoleTester.Create;
    try
      ConsoleTester.ParseParameters;
      ConsoleTester.Run;
    finally
      FreeAndNil(ConsoleTester);
    end;
  end;
end.
