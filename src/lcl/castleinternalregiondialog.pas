{
  Copyright 2023 Freedomax.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}
unit CastleInternalRegionDialog;

{$I castleconf.inc}

interface

uses
  Generics.Collections, Contnrs,
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  ButtonPanel, StdCtrls, ExtCtrls, ComCtrls, CastleVectors, CastleControl,
  CastleGLImages,
  castletransform, CastleKeysMouse,
  castlecontrols, CastleRectangles, CastleLCLUtils, CastleGLUtils, CastleColors;

type

  { TRegionDesignDialog }

  TRegionDesignDialog = class(TForm)
    ButtonPanel1: TButtonPanel;
    CastleControl1: TCastleControl;
    ColorDialog1: TColorDialog;
    StatusBar1: TStatusBar;

    procedure CastleControl1Motion(Sender: TObject; const Event: TInputMotion);
    procedure CastleControl1Press(Sender: TObject; const Event: TInputPressRelease);
    procedure CastleControl1Release(Sender: TObject;
      const Event: TInputPressRelease);
    procedure CastleControl1Render(Sender: TObject);
    procedure HelpButtonClick(Sender: TObject);
  strict private
  type
    TMovingRec = record
      Moving: boolean;
      StartTranslation: TVector2;
      StartMousePoint: TVector2;
    end;

    TControlPointRec = record
      Adjusting: boolean;
      Index: integer;
      Points: array[0..1] of TVector2Integer;
    end;

  const
    CircleRads = 8;
  var
    FImage: TDrawableImage;
    FRegion: TRegion;
    FScale: single;
    FTranslation: TVector2;
    FMovingImageRec: TMovingRec;
    FControlPointRec: TControlPointRec;
    procedure SetImage(AValue: TDrawableImage);
    procedure SetRegion(AValue: TRegion);
    procedure InitControlPoints;
    procedure Changed;
  protected
    function ScreenToImage(APoint: TVector2): TVector2Integer;
    function ImageToScreen(APoint: TVector2Integer): TVector2;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyChange;

    property Region: TRegion read FRegion write SetRegion;
    property Image: TDrawableImage read FImage write SetImage;
  end;


implementation

uses Math;

{$R *.lfm}

{ TRegionDesignDialog }

constructor TRegionDesignDialog.Create(AOwner: TComponent);
begin
  inherited;

  FScale := 1;
  FillChar(FControlPointRec, SizeOf(FControlPointRec), #0);
  FillChar(FMovingImageRec, SizeOf(FControlPointRec), #0);
end;

destructor TRegionDesignDialog.Destroy;
begin
  inherited;
end;

procedure TRegionDesignDialog.ApplyChange;
begin
  if Assigned(FRegion) then
  begin
    FRegion.AllSides := 0;
    FRegion.Left := Min(FControlPointRec.Points[0].X, FControlPointRec.Points[1].X);
    FRegion.Right := Image.Width - Max(FControlPointRec.Points[0].X,
      FControlPointRec.Points[1].X);
    FRegion.Bottom := Min(FControlPointRec.Points[0].Y, FControlPointRec.Points[1].Y);
    FRegion.Top := Image.Height - Max(FControlPointRec.Points[0].Y,
      FControlPointRec.Points[1].Y);
  end;
end;

procedure TRegionDesignDialog.CastleControl1Render(Sender: TObject);

  function ScreenRect: TFloatRectangle;
  begin
    Result := FloatRectangle(0, 0, Image.Width * FScale, Image.Height *
      FScale).Translate(FTranslation);
  end;

  procedure RenderPoint(const Point: TVector2);
  begin
    DrawCircle(Point, CircleRads, CircleRads, Vector4(0.864, 0.17, 0.03, 1));
  end;

  procedure RenderImage;
  begin
    if Assigned(Image) then  Image.Draw(ScreenRect);
  end;

  procedure RenderControlPoints;
  var
    pt0, pt1: TVector2;
    vLeft, vBottom, vWidth, vHeight: single;
  begin
    pt0 := ImageToScreen(FControlPointRec.Points[0]);
    pt1 := ImageToScreen(FControlPointRec.Points[1]);

    vLeft := Min(pt0.X, pt1.X);
    vBottom := Min(pt0.Y, pt1.Y);
    vWidth := ABS(pt0.X - pt1.X);
    vHeight := ABS(pt0.Y - pt1.Y);

    DrawRectangle(FloatRectangle(vLeft, vBottom, vWidth, vHeight),
      Vector4(1, 1, 1, 0.5));
    DrawRectangleOutline(FloatRectangle(vLeft, vBottom, vWidth, vHeight),
      CastleColors.Red, 2);
    RenderPoint(pt0);
    RenderPoint(pt1);
  end;

begin
  RenderImage;
  RenderControlPoints;
end;

procedure TRegionDesignDialog.HelpButtonClick(Sender: TObject);
begin
  if ColorDialog1.Execute then
    CastleControl1.Container.BackgroundColor :=
      Vector4(byte(ColorDialog1.Color) / 255, byte(ColorDialog1.Color shr 8) /
      255, byte(ColorDialog1.Color shr 16) / 255, 1);
end;

procedure TRegionDesignDialog.CastleControl1Press(Sender: TObject;
  const Event: TInputPressRelease);

  procedure GrowScale(beIncrease: boolean; ScreenPoint: TVector2);
  const
    PX = 0.7;
  var
    ImagePoint: TVector2Integer;
  begin
    ImagePoint := ScreenToImage(ScreenPoint);

    if beIncrease then
    begin
      if FScale < 1 then
        FScale := FScale + 0.1
      else if FScale < 2 then
        FScale := FScale + 0.2
      else if FScale < 6 then
        FScale := FScale + 0.4
      else
        FScale := FScale / PX;

      FScale := Min(FScale, 10000);
    end
    else
    begin
      if FScale > 6 then FScale := FScale * PX
      else if FScale > 2 then
        FScale := FScale - 0.4
      else
      if FScale > 0.6 then
        FScale := FScale - 0.2
      else if FScale > 0.2 then
        FScale := FScale - 0.1
      else
        FScale := FScale * PX;

      FScale := Max(FScale, 0.0001);
    end;

    { Zoom in on the pixel at the fixed mouse location. }
    FTranslation := FTranslation + ScreenPoint - ImageToScreen(ImagePoint);

  end;

var
  ScreenPt: array[0..1] of TVector2;
  i: integer;
  bTouchPoints: array[0..1] of boolean;
begin
  if (Event.EventType = TInputPressReleaseType.itMouseButton) and
    (Event.MouseButton = TCastleMouseButton.buttonLeft) and
    (not FControlPointRec.Adjusting) then
  begin
    for i := Low(FControlPointRec.Points) to High(FControlPointRec.Points) do
    begin
      ScreenPt[i] := ImageToScreen(FControlPointRec.Points[i]);
      bTouchPoints[i] := PointsDistance(ScreenPt[i], Event.Position) < CircleRads;
      if bTouchPoints[i] then
      begin
        FControlPointRec.Points[i] := ScreenToImage(Event.Position);
        FControlPointRec.Index := i;
        FControlPointRec.Adjusting := True;
        Changed;
        Exit;
      end;
    end;

    FControlPointRec.Points[0] := ScreenToImage(Event.Position);
    FControlPointRec.Points[1] := FControlPointRec.Points[0];
    FControlPointRec.Index := 1;
    FControlPointRec.Adjusting := True;
    Changed;
  end;

  if (Event.EventType = TInputPressReleaseType.itMouseButton) and
    (Event.MouseButton = TCastleMouseButton.buttonRight) and
    (not FMovingImageRec.Moving) then
  begin
    FMovingImageRec.StartMousePoint := Event.Position;
    FMovingImageRec.StartTranslation := FTranslation;
    FMovingImageRec.Moving := True;
    Exit;
  end;

  if (Event.EventType = TInputPressReleaseType.itMouseWheel) then
  begin
    GrowScale(Event.MouseWheelScroll > 0, Event.Position);
    Exit;
  end;
end;

procedure TRegionDesignDialog.CastleControl1Motion(Sender: TObject;
  const Event: TInputMotion);

  procedure UpdateCursorInfo(Point: TVector2);
  begin
    StatusBar1.Panels.Items[4].Text := Format('CursorPos: %f , %f', [Point.X, Point.Y]);
  end;

begin
  UpdateCursorInfo(Event.Position);

  if FControlPointRec.Adjusting then
  begin
    FControlPointRec.Points[FControlPointRec.Index] := ScreenToImage(Event.Position);
    Changed;
  end;

  if FMovingImageRec.Moving then
  begin
    FTranslation := Event.Position - FMovingImageRec.StartMousePoint +
      FMovingImageRec.StartTranslation;
  end;
end;

procedure TRegionDesignDialog.CastleControl1Release(Sender: TObject;
  const Event: TInputPressRelease);
begin
  if (Event.EventType = TInputPressReleaseType.itMouseButton) and
    (Event.MouseButton = TCastleMouseButton.buttonRight) and
    FMovingImageRec.Moving then
    FMovingImageRec.Moving := False;

  if (Event.EventType = TInputPressReleaseType.itMouseButton) and
    (Event.MouseButton = TCastleMouseButton.buttonLeft) and
    FControlPointRec.Adjusting then
    FControlPointRec.Adjusting := False;
end;

procedure TRegionDesignDialog.SetImage(AValue: TDrawableImage);
begin
  if FImage = AValue then Exit;

  FImage := AValue;
  if Assigned(FRegion) then InitControlPoints;
end;

procedure TRegionDesignDialog.SetRegion(AValue: TRegion);
begin
  if FRegion = AValue then Exit;
  FRegion := AValue;
  if Assigned(FImage) then InitControlPoints;
end;

procedure TRegionDesignDialog.InitControlPoints;
begin
  FControlPointRec.Points[0] :=
    Vector2Integer(Floor(FRegion.TotalLeft), Floor(FRegion.TotalBottom));
  FControlPointRec.Points[1] :=
    Vector2Integer(FImage.Width - Floor(FRegion.TotalRight), FImage.Height -
    Floor(FRegion.TotalTop));
  Changed;
end;

procedure TRegionDesignDialog.Changed;
begin
  StatusBar1.Panels.Items[0].Text :=
    Format('Left: %d', [Min(FControlPointRec.Points[0].X,
    FControlPointRec.Points[1].X)]);
  StatusBar1.Panels.Items[1].Text :=
    Format('Bottom: %d', [Min(FControlPointRec.Points[0].Y,
    FControlPointRec.Points[1].Y)]);
  StatusBar1.Panels.Items[2].Text :=
    Format('Width: %d', [Abs(FControlPointRec.Points[0].X -
    FControlPointRec.Points[1].X)]);
  StatusBar1.Panels.Items[3].Text :=
    Format('Height: %d', [Abs(FControlPointRec.Points[0].Y -
    FControlPointRec.Points[1].Y)]);
end;

function TRegionDesignDialog.ScreenToImage(APoint: TVector2): TVector2Integer;
begin
  APoint := APoint - FTranslation;
  APoint := APoint / FScale;

  Result.X := Round(APoint.X);
  Result.Y := Round(APoint.Y);
end;

function TRegionDesignDialog.ImageToScreen(APoint: TVector2Integer): TVector2;
var
  pt: TVector2;
begin
  pt.X := APoint.X;
  pt.Y := APoint.Y;

  pt := pt * FScale;
  Result := pt + FTranslation;
end;

end.
