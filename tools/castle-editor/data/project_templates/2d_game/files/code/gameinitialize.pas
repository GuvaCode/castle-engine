{ Game initialization.
  This unit is cross-platform.
  It will be used by the platform-specific program or library file.

  Feel free to use this code as a starting point for your own projects.
  (This code is in public domain, unlike most other CGE code which
  is covered by the LGPL license variant, see the COPYING.txt file.) }
unit GameInitialize;

interface

implementation

uses SysUtils,
  CastleWindow, CastleLog, CastleUIState
  { CASTLE-INITIALIZATION-USES-BEGIN }
  // The content here may be automatically updated by CGE editor.
  , GameStateMenu
  , GameStatePlay
  { CASTLE-INITIALIZATION-USES-END };

var
  Window: TCastleWindowBase;

{ One-time initialization of resources. }
procedure ApplicationInitialize;
begin
  { Adjust container settings for a scalable UI (adjusts to any window size in a smart way). }
  Window.Container.LoadSettings('castle-data:/CastleSettings.xml');

  { Create game states and set initial state }
  { CASTLE-STATE-CREATE-BEGIN }
  // The content here may be automatically updated by CGE editor.
  StatePlay := TStatePlay.Create(Application);
  StateMenu := TStateMenu.Create(Application);
  { CASTLE-STATE-CREATE-END }

  TUIState.Current := StateMenu;
end;

initialization
  { Initialize Application.OnInitialize. }
  Application.OnInitialize := @ApplicationInitialize;

  { Create and assign Application.MainWindow. }
  Window := TCastleWindowBase.Create(Application);
  Window.ParseParameters; // allows to control window size / fullscreen on the command-line
  Application.MainWindow := Window;

  { You should not need to do *anything* more in the unit "initialization" section.
    Most of your game initialization should happen inside ApplicationInitialize.
    In particular, it is not allowed to read files before ApplicationInitialize
    (because in case of non-desktop platforms,
    some necessary resources may not be prepared yet). }
end.
