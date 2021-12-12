{
  Copyright 2004-2021 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Main state, where most of the application logic takes place. }
unit GameStateMain;

interface

uses Classes,
  CastleUIState, CastleComponentSerialize, CastleUIControls, CastleControls,
  CastleKeysMouse, CastleNotifications;

type
  { Main state, where most of the application logic takes place. }
  TStateMain = class(TUIState)
  private
    { Components designed using CGE editor, loaded from gamestatemain.castle-user-interface. }
    RootGroup: TCastleUserInterface;
    LabelFps: TCastleLabel;
    Timer: TCastleTimer;
    LabelCharsPressed: TCastleLabel;
    LabelKeysPressed: TCastleLabel;
    LabelMousePressed: TCastleLabel;
    LabelTouches: TCastleLabel;
    LabelModifierKeys: TCastleLabel;

    { Other }
    Notifications: TCastleNotifications;
    procedure DoTimer(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
    function Release(const Event: TInputPressRelease): Boolean; override;
    function Motion(const Event: TInputMotion): Boolean; override;
    procedure Resize; override;
  end;

var
  StateMain: TStateMain;

implementation

uses SysUtils,
  CastleWindow, CastleVectors, CastleColors, CastleStringUtils;

{ TStateMain ----------------------------------------------------------------- }

constructor TStateMain.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/gamestatemain.castle-user-interface';
end;

procedure TStateMain.Start;
begin
  inherited;

  { Find components, by name, that we need to access from code }
  RootGroup := DesignedComponent('RootGroup') as TCastleUserInterface;
  LabelFps := DesignedComponent('LabelFps') as TCastleLabel;
  Timer := DesignedComponent('Timer') as TCastleTimer;
  LabelCharsPressed := DesignedComponent('LabelCharsPressed') as TCastleLabel;
  LabelKeysPressed := DesignedComponent('LabelKeysPressed') as TCastleLabel;
  LabelMousePressed := DesignedComponent('LabelMousePressed') as TCastleLabel;
  LabelTouches := DesignedComponent('LabelTouches') as TCastleLabel;
  LabelModifierKeys := DesignedComponent('LabelModifierKeys') as TCastleLabel;

  { Add TCastleNotifications from code, as for now we don't expose them in editor. }
  Notifications := TCastleNotifications.Create(FreeAtStop);
  Notifications.Anchor(hpMiddle);
  Notifications.Anchor(vpTop, -5);
  Notifications.TextAlignment := hpMiddle;
  Notifications.Color := Green;
  Notifications.MaxMessages := 15;
  Notifications.Timeout := 20000;
  InsertFront(Notifications);

  Timer.OnTimer := {$ifdef FPC}@{$endif}DoTimer;

  Notifications.Show('State started');
end;

function TStateMain.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle event

  { This virtual method is executed when user presses
    a key, a mouse button, or touches a touch-screen.

    Note that each UI control has also events like OnPress and OnClick.
    These events can be used to handle the "press", if it should do something
    specific when used in that UI control.
    The TStateMain.Press method should be used to handle keys
    not handled in children controls.
  }

  Notifications.Show('Press: ' + Event.ToString);

  case Event.KeyCharacter of
    { cursor tests: }
    'n': Container.OverrideCursor := mcNone;
    'd': Container.OverrideCursor := mcDefault;
    'w': Container.OverrideCursor := mcWait;
    's': Container.OverrideCursor := mcResizeHorizontal;
    { setting mouse position tests: }
    '1': Container.MousePosition := Vector2(0                  , 0);
    '2': Container.MousePosition := Vector2(Container.Width    , 0);
    '3': Container.MousePosition := Vector2(Container.Width    , Container.Height);
    '4': Container.MousePosition := Vector2(0                  , Container.Height);
    '5': Container.MousePosition := Vector2(Container.Width / 2, Container.Height / 2);
  end;

  // switching FullScreen
  if Event.IsKey(keyF11) {$ifdef DARWIN} and Container.Pressed[keyCtrl] {$endif} then
    Application.MainWindow.FullScreen := not Application.MainWindow.FullScreen;
end;

function TStateMain.Release(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle event

  Notifications.Show('Release: ' + Event.ToString);
end;

function TStateMain.Motion(const Event: TInputMotion): Boolean;
begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle event

  Notifications.Show(Format('Motion: old position %s, new position %s, delta %s', [
    Event.OldPosition.ToString,
    Event.Position.ToString,
    (Event.Position - Event.OldPosition).ToString
  ]));
end;

procedure TStateMain.Resize;
begin
  inherited; // allow the ancestor to handle event
  Notifications.Show(Format('Resize: new size (in real device pixels) %d %d, new size with UI scaling: %f %f', [
    Container.Width,
    Container.Height,
    RootGroup.EffectiveWidth,
    RootGroup.EffectiveHeight
  ]));
end;

procedure TStateMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);
var
  C: Char;
  Key: TKey;
  MouseButton: TCastleMouseButton;
  S: String;
  I: Integer;
begin
  inherited; // allow the ancestor to handle event

  { This virtual method is executed every frame.}

  LabelFps.Caption := 'FPS: ' + Container.Fps.ToString;

  S := '';
  for C := Low(C) to High(C) do
    if Container.Pressed.Characters[C] then
      S := SAppendPart(S, ', ', CharToNiceStr(C));
  S := 'Characters pressed: [' + S + ']';
  LabelCharsPressed.Caption := S;

  S := '';
  for Key := Low(Key) to High(Key) do
    if Container.Pressed[Key] then
      S := SAppendPart(S, ', ', KeyToStr(Key));
  S := 'Keys pressed: [' + S + ']';
  LabelKeysPressed.Caption := S;

  LabelModifierKeys.Caption := 'Modifier keys pressed: ' +
    ModifierKeysToNiceStr(Container.Pressed.Modifiers);

  S := '';
  for MouseButton := Low(MouseButton) to High(MouseButton) do
    if MouseButton in Container.MousePressed then
      S := SAppendPart(S, ', ', MouseButtonStr[MouseButton]);
  S := 'Mouse buttons pressed: [' + S + ']';
  LabelMousePressed.Caption := S;

  S := '';
  for I := 0 to Container.TouchesCount - 1 do
    S := SAppendPart(S, ', ', IntToStr(Container.Touches[I].FingerIndex));
  S := 'Fingers touched: [' + S + ']';
  LabelTouches.Caption := S;

  // Just a test that checking for keys, and using MessageOk, works from Update
  if Container.Pressed[keyF12] then
    Application.MainWindow.MessageOk('F12 key pressed. This is just a test that MessageOk works.', mtInfo);
end;

procedure TStateMain.DoTimer(Sender: TObject);
begin
  Notifications.Show(Format('Timer (every 5 seconds): Time now is %s', [FormatDateTime('tt', Time)]));
end;

end.
