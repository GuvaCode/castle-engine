{
  Copyright 2023-2023 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Main "playing game" view, where most of the game logic takes place. }
unit GameViewPlay;

interface

uses Classes,
  CastleComponentSerialize, CastleUIControls, CastleControls,
  CastleKeysMouse, CastleViewport, CastleScene, CastleVectors, CastleCameras,
  CastleTransform;

type
  { Direction expressed a 4 possible horizontal directions.
    In the clockwise order. }
  TDirection = (dirNorth, dirEast, dirSouth, dirWest);

const
  { Convert TDirection to MainViewport.Camera.Direction vector.
    Check these values looking at MainViewport.Camera.Direction (in "All" tab)
    in editor. }
  DirectionVector: array [TDirection] of TVector3 = (
    (X:  0; Y: 0; Z: -1),
    (X:  1; Y: 0; Z:  0),
    (X:  0; Y: 0; Z:  1),
    (X: -1; Y: 0; Z:  0)
  );

type
  { Main "playing game" view, where most of the game logic takes place. }
  TViewPlay = class(TCastleView)
  published
    { Components designed using CGE editor.
      These fields will be automatically initialized at Start. }
    LabelFps: TCastleLabel;
    MainViewport: TCastleViewport;
    MainFog: TCastleFog;
  private
    { Always synchronized with MainViewport.Camera.Direction. }
    Direction: TDirection;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewPlay: TViewPlay;

implementation

uses SysUtils, Math,
  CastleLog, CastleStringUtils, CastleFilesUtils, CastleUtils,
  GameViewMenu;

{ TViewPlay ----------------------------------------------------------------- }

constructor TViewPlay.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/gameviewplay.castle-user-interface';
end;

procedure TViewPlay.Start;
begin
  inherited;
  { Make sure Dir and MainViewport.Camera.Direction are initially synchronized. }
  Direction := dirNorth;
  MainViewport.Camera.Direction := DirectionVector[Direction];
  { At design-time, we keep MainFog.VisibilityRange larger,
    otherwise it makes it hard to actually see level at design-time from top. }
  MainFog.VisibilityRange := 5;
end;

procedure TViewPlay.Stop;
begin
  inherited;
end;

procedure TViewPlay.Update(const SecondsPassed: Single; var HandleInput: Boolean);
begin
  inherited;
  { This virtual method is executed every frame (many times per second). }
  Assert(LabelFps <> nil, 'If you remove LabelFps from the design, remember to remove also the assignment "LabelFps.Caption := ..." from code');
  LabelFps.Caption := 'FPS: ' + Container.Fps.ToString;
end;

function TViewPlay.Press(const Event: TInputPressRelease): Boolean;
const
  { Time, in seconds, to perform move or rotation. }
  ActionDuration = 0.25;

  { Calculate "Value + Increase"
    doing typecasting as necessary between enums and integers,
    and making sure result is in TDir range. }
  function IncreaseDirection(const Value: TDirection; const Increase: Integer): TDirection;
  begin
    Result := TDirection(ChangeIntCycle(Ord(Value), Increase, Ord(High(TDirection))));
  end;

  procedure Move(const MoveDirection: TDirection);
  const
    GridSize = 1;
  var
    NewPos, Pos, Dir, Up: TVector3;
  begin
    MainViewport.Camera.GetWorldView(Pos, Dir, Up);
    NewPos := Pos + DirectionVector[MoveDirection] * GridSize;
    if not MainViewport.Items.WorldSegmentCollision(Pos, NewPos) then
      MainViewport.Camera.AnimateTo(NewPos, Dir, Up, ActionDuration);
  end;

  procedure Rotate(const RotationChange: Integer);
  var
    Pos, Dir, Up: TVector3;
  begin
    MainViewport.Camera.GetWorldView(Pos, Dir, Up);
    Direction := IncreaseDirection(Direction, RotationChange);
    Dir := DirectionVector[Direction];
    MainViewport.Camera.AnimateTo(Pos, Dir, Up, ActionDuration);
  end;

begin
  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  if not MainViewport.Camera.Animation then
  begin
    if Event.IsKey(keyW) then
    begin
      Move(IncreaseDirection(Direction, 0)); // Move along Direction
      Exit(true);
    end;
    if Event.IsKey(keyS) then
    begin
      Move(IncreaseDirection(Direction, 2)); // Move along the opposite of Direction
      Exit(true);
    end;
    if Event.IsKey(keyD) then
    begin
      Move(IncreaseDirection(Direction, 1)); // Move along Direction rotated to right (i.e. strafe right)
      Exit(true);
    end;
    if Event.IsKey(keyA) then
    begin
      Move(IncreaseDirection(Direction, -1)); // Move along Direction rotated to left (i.e. strafe left)
      Exit(true);
    end;

    if Event.IsKey(keyQ) then
    begin
      Rotate(-1);
      Exit(true);
    end;
    if Event.IsKey(keyE) then
    begin
      Rotate(1);
      Exit(true);
    end;
  end;

  if Event.IsKey(keyF5) then
  begin
    Container.SaveScreenToDefaultFile;
    Exit(true);
  end;

  if Event.IsKey(keyEscape) then
  begin
    Container.View := ViewMenu;
    Exit(true);
  end;
end;

end.
